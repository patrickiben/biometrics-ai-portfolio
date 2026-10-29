"""Trusted execution of immutable guided analysis revisions (no shell commands)."""
from __future__ import annotations

import hashlib
import csv
import html
import json
import os
from pathlib import Path
import re
import secrets
import subprocess
import sys
import zipfile

if __package__ in {None, ""}:
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from toolkit_launcher.runtime import ROOT, InputError, atomic_json, safe_path, timestamp

MODULES = {"r_tlf", "sas_tlf", "sas_monitor", "interpretation", "vaccine"}
BUILD_ID = re.compile(r"setup-[a-f0-9]{24}\Z")
RUN_ID = re.compile(r"run-[a-f0-9]{32}\Z")
SHA = re.compile(r"[a-f0-9]{64}\Z")
RESULTS = ("analysis_report.html", "output_manifest.json", "qc.json", "execution_status.csv", "software_versions.csv")
MAX_BUNDLE = 128 * 1024 * 1024
ENGINE_FILES = ("toolkit_launcher/analysis_runner.R", "toolkit_launcher/analysis_monitor.R",
                "toolkit_launcher/analysis_vaccine.R",
                "toolkit_launcher/analysis_jobs.py", "assets/theme/tokens.css")


def read_json(path, limit=2 * 1024 * 1024):
    if path.is_symlink() or not path.is_file() or path.stat().st_size > limit:
        raise InputError("The saved analysis record is missing, linked or too large.")
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (ValueError, UnicodeError):
        raise InputError("The saved analysis record cannot be read.") from None


def verify_bundle(root, module_id, build_id, expected_sha):
    if not isinstance(module_id, str) or module_id not in MODULES or not isinstance(build_id, str) or not BUILD_ID.fullmatch(build_id):
        raise InputError("Choose a generated analysis package from this module.")
    if not isinstance(expected_sha, str) or not SHA.fullmatch(expected_sha):
        raise InputError("Generate a new package with this toolkit before running its analysis.")
    bundle = safe_path(root, f"template_outputs/{module_id}/{build_id}", exists=False)
    manifest_path = safe_path(bundle, "analysis_bundle.json")
    manifest = read_json(manifest_path)
    if hashlib.sha256(manifest_path.read_bytes()).hexdigest() != expected_sha:
        raise InputError("This package's integrity record changed. Generate a new package before running.")
    files = manifest.get("files") if isinstance(manifest, dict) else None
    if (not isinstance(manifest, dict) or manifest.get("schema") != 1 or manifest.get("module_id") != module_id
            or not isinstance(files, dict) or not files or len(files) > 3000):
        raise InputError("This package has no valid analysis file inventory. Generate it again.")
    total = 0
    for name, digest in files.items():
        if not isinstance(digest, str) or not SHA.fullmatch(digest):
            raise InputError("This package contains an invalid file fingerprint.")
        path = safe_path(bundle, name)
        total += path.stat().st_size
        if total > MAX_BUNDLE or hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            raise InputError("A generated input or program changed. Generate a new package before running.")
    observed = set()
    for path in bundle.rglob("*"):
        if path.is_symlink():
            raise InputError("Analysis packages cannot contain linked files or folders.")
        if path.is_file():
            observed.add(path.relative_to(bundle).as_posix())
    if observed - {"analysis_bundle.json", "study-setup.zip"} != set(files):
        raise InputError("Files were added to or removed from this package. Generate a new package before running.")
    # Real generated revisions pin the installed implementation at preview time.
    # Tiny unit-test fixtures may omit source provenance entirely.
    provenance = bundle / "source_fingerprints.json"
    if "source_fingerprints.json" in files:
        source_hashes = read_json(provenance)
        if not isinstance(source_hashes, dict):
            raise InputError("The package source provenance is invalid.")
        for name in ENGINE_FILES:
            if name in source_hashes:
                current = hashlib.sha256(safe_path(ROOT, name).read_bytes()).hexdigest()
                if source_hashes[name] != current:
                    raise InputError("The installed analysis implementation changed since this package was generated. Preview and generate a new revision.")
    return bundle


def resolve_build(root, module_id, build_id):
    if not isinstance(module_id, str) or module_id not in MODULES or not isinstance(build_id, str) or not BUILD_ID.fullmatch(build_id):
        raise InputError("Choose a generated analysis package from this module.")
    history = read_json(safe_path(root, f"toolkit_configuration/{module_id}.builds.json"))
    if not isinstance(history, list):
        raise InputError("This module's generated-package history cannot be read.")
    matches = [record for record in history if isinstance(record, dict) and record.get("build_id") == build_id]
    if len(matches) != 1 or matches[0].get("module_id") != module_id or matches[0].get("engine") != "r":
        raise InputError("Generate a runnable package with this toolkit before running its analysis.")
    record = matches[0]
    bundle = verify_bundle(root, module_id, build_id, record.get("bundle_sha256"))
    return record, bundle


def engine_fingerprint():
    # Pin every interpreted execution component and its report theme, not only
    # the entry point that sources them. Sorted JSON makes this cross-platform.
    files = {name: hashlib.sha256(safe_path(ROOT, name).read_bytes()).hexdigest()
             for name in ENGINE_FILES}
    return hashlib.sha256(json.dumps(files, sort_keys=True).encode("utf-8")).hexdigest()


def prepare_run(root, module_id, build_id):
    record, bundle = resolve_build(root, module_id, build_id)
    run_id = "run-" + secrets.token_hex(16)
    relative = f"template_runs/{module_id}/{run_id}"
    run_root = safe_path(root, relative, exists=False)
    run_root.mkdir(parents=True, mode=0o700)
    plan = {"schema": 1, "module_id": module_id, "project_root": str(root), "build_id": build_id,
            "run_id": run_id, "build_root": str(bundle), "run_root": str(run_root), "source_root": str(ROOT),
            "bundle_sha256": record["bundle_sha256"], "engine_sha256": engine_fingerprint(), "created_at": timestamp(), "approved": False}
    atomic_json(run_root / "plan.json", plan)
    return plan, relative


def validate_plan(path):
    plan = read_json(path)
    if not isinstance(plan, dict) or plan.get("schema") != 1 or plan.get("source_root") != str(ROOT):
        raise InputError("This analysis run was not created by the installed toolkit.")
    module = plan.get("module_id")
    run_id = plan.get("run_id")
    if not isinstance(module, str) or module not in MODULES or not isinstance(run_id, str) or not RUN_ID.fullmatch(run_id):
        raise InputError("This analysis run has an invalid identifier.")
    if plan.get("engine_sha256") != engine_fingerprint():
        raise InputError("The installed analysis engine changed. Start a new analysis run.")
    root = Path(plan["project_root"])
    if not root.is_absolute() or root.is_symlink() or not root.is_dir():
        raise InputError("The private project folder is unavailable.")
    run_root = safe_path(root, f"template_runs/{module}/{run_id}", exists=False)
    if plan.get("run_root") != str(run_root) or path != run_root / "plan.json":
        raise InputError("This run must stay in its private results folder.")
    bundle = verify_bundle(root, module, plan.get("build_id"), plan.get("bundle_sha256"))
    if plan.get("build_root") != str(bundle):
        raise InputError("The selected package does not belong to this run.")
    return plan, root, run_root


def verify_results(run_root, plan=None):
    for name in RESULTS:
        safe_path(run_root, name)
    qc = read_json(run_root / "qc.json")
    manifest = read_json(run_root / "output_manifest.json")
    if not isinstance(qc, dict) or qc.get("schema") != 1 or qc.get("passed") is not True or qc.get("status") != "passed" or qc.get("all_selected_outputs_completed") is not True or qc.get("approved") is not False:
        raise InputError("The analysis completed with failed or incomplete QC. Review its diagnostic report.")
    if not isinstance(manifest, dict) or manifest.get("schema") != 1 or manifest.get("status") != "succeeded":
        raise InputError("The analysis output manifest is incomplete. Review its diagnostics.")
    outputs = manifest.get("outputs")
    if not isinstance(outputs, list) or not outputs:
        raise InputError("The analysis did not produce any selected outputs.")
    for item in outputs:
        if not isinstance(item, dict) or item.get("status") != "completed" or not isinstance(item.get("files"), list) or not item["files"]:
            raise InputError("At least one requested analysis output failed or is missing.")
        for name in item["files"]:
            safe_path(run_root, name)
    if plan is not None:
        for key in ("module_id", "build_id", "run_id", "bundle_sha256", "engine_sha256"):
            if manifest.get(key) != plan.get(key):
                raise InputError("The result provenance does not match this analysis run.")
        if manifest.get("approved") is not False:
            raise InputError("The analysis cannot grant scientific approval.")
        profile = read_json(Path(plan["build_root"]) / "setup_profile.json")
        values = profile.get("values", {}) if isinstance(profile, dict) else {}
        module = plan["module_id"]
        expected = values.get("outputs") if module in {"r_tlf", "sas_tlf", "vaccine"} else values.get("checks") if module == "sas_monitor" else ["interpretation"]
        actual = [item.get("id") for item in outputs]
        if (not isinstance(expected, list) or not expected or any(not isinstance(x, str) for x in expected)
                or len(set(expected)) != len(expected) or len(actual) != len(expected) or set(actual) != set(expected)):
            raise InputError("The result inventory does not contain every selected output exactly once.")
        with (run_root / "execution_status.csv").open(newline="", encoding="utf-8-sig") as stream:
            status = list(csv.DictReader(stream))
        if (len(status) != len(expected) or {row.get("output") for row in status} != set(expected)
                or any(row.get("status") != "completed" for row in status)):
            raise InputError("The execution status table does not confirm every selected output.")
    return manifest


def invalidate_results(run_root, message, provenance=False):
    """A failed adapter verdict must also be visible inside downloaded artifacts."""
    def existing(name):
        try:
            value = read_json(run_root / name)
            return value if isinstance(value, dict) else {}
        except (InputError, OSError):
            return {}
    qc = existing("qc.json")
    qc.update(schema=1, passed=False, status="failed", all_selected_outputs_completed=False, approved=False)
    previous_errors = qc.get("errors", [])
    qc["errors"] = (previous_errors if isinstance(previous_errors, list) else []) + [message]
    manifest = existing("output_manifest.json")
    manifest.update(schema=1, status="failed", approved=False, execution_error=message)
    if provenance:
        # Results from a changed input or implementation cannot be represented as
        # the selected immutable revision. Retain only logs and diagnostics.
        for path in (run_root / "outputs").rglob("*"):
            if path.is_symlink():
                path.unlink()
            elif path.is_file() and path.name not in {"program.log", "error.txt"}:
                path.unlink()
        items = manifest.get("outputs", [])
        for item in items if isinstance(items, list) else []:
            if not isinstance(item, dict):
                continue
            for name in item.get("files", []) if isinstance(item.get("files"), list) else []:
                try:
                    path = safe_path(run_root, name)
                    if path.name not in {*RESULTS, "program.log", "error.txt", "plan.json", "execution_error.json"}:
                        path.unlink()
                except (InputError, OSError, TypeError):
                    pass
            item["status"] = "invalidated"
            item["files"] = []
        status_path = run_root / "execution_status.csv"
        if status_path.is_file() and not status_path.is_symlink():
            with status_path.open(newline="", encoding="utf-8-sig") as stream:
                rows = list(csv.DictReader(stream))
            with status_path.open("w", newline="", encoding="utf-8") as stream:
                writer = csv.DictWriter(stream, fieldnames=(list(rows[0]) if rows else ["output", "status", "error"]))
                writer.writeheader()
                for row in rows:
                    row.update(status="invalidated", error=message)
                    writer.writerow(row)
    atomic_json(run_root / "qc.json", qc)
    atomic_json(run_root / "output_manifest.json", manifest)
    report = run_root / "analysis_report.html"
    previous = report.read_text(encoding="utf-8") if report.is_file() and not report.is_symlink() else ""
    if provenance or not previous:
        content = ("<button class='theme-toggle'>Light / dark</button><button class='print-report'>Print / save PDF</button>"
                   "<h1>Analysis failed</h1><p>Numerical results were invalidated because this run's provenance could not be verified.</p>"
                   "<p>" + html.escape(message) + "</p><p>No scientific approval was issued. Generate a new revision and rerun.</p>")
        if previous and "<main>" in previous and "</main>" in previous:
            report.write_text(re.sub(r"<main>.*?</main>", lambda _: "<main>" + content + "</main>", previous, count=1, flags=re.S), encoding="utf-8")
        else:
            theme = safe_path(ROOT, "assets/theme/tokens.css").read_text(encoding="utf-8")
            report.write_text("<!doctype html><html lang='en'><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'><title>Analysis failed</title><style>" + theme +
                              "body{background:var(--bg);color:var(--text);font:16px system-ui}main{padding:24px}button{padding:8px;background:var(--surface);color:var(--text)}</style><main>" + content +
                              "</main><script>document.querySelector('.theme-toggle').onclick=()=>{const d=document.documentElement;d.dataset.theme=d.dataset.theme==='dark'?'light':'dark'};document.querySelector('.print-report').onclick=()=>print()</script></html>", encoding="utf-8")
    else:
        banner = "<section role='alert'><h1>Analysis run failed</h1><p>" + html.escape(message) + "</p><p>No scientific approval was issued.</p></section>"
        previous = previous.replace("All selected outputs completed.", "The overall analysis run failed. Review its diagnostic record.")
        report.write_text(previous.replace("<main>", "<main>" + banner, 1) if "<main>" in previous else banner + previous, encoding="utf-8")


def archive_results(run_root):
    pending = run_root / ".results.zip"
    try:
        with zipfile.ZipFile(pending, "w", zipfile.ZIP_DEFLATED) as archive:
            total = 0
            for path in sorted(run_root.rglob("*")):
                if path.is_symlink():
                    raise InputError("A result points outside its run folder; the ZIP was not created.")
                if not path.is_file() or path.name in {"plan.json", ".results.zip", "results.zip"}:
                    continue
                name = path.relative_to(run_root).as_posix()
                safe_path(run_root, name)
                total += path.stat().st_size
                if total > 512 * 1024 * 1024:
                    raise InputError("Results exceed the 512 MB download limit. Open the private project folder to review them.")
                archive.write(path, name)
        pending.replace(run_root / "results.zip")
    finally:
        pending.unlink(missing_ok=True)


def execute(plan_path, r_path):
    """Called by a fixed launcher command; descendants remain in its owned job."""
    run_root = None
    provenance_failure = False
    try:
        plan, root, run_root = validate_plan(plan_path)
        print("Running the selected study package. Scientific approval remains separate.", flush=True)
        result = subprocess.run([r_path, "--vanilla", str(ROOT / "toolkit_launcher/analysis_runner.R"), str(plan_path)], cwd=run_root)
        # Recheck source snapshots before accepting results; no result is silently
        # relabelled after inputs change outside the launcher while R is running.
        try:
            validate_plan(plan_path)
        except (InputError, OSError, ValueError):
            provenance_failure = True
            raise
        if result.returncode:
            raise InputError("The analysis engine reported a failure. Review the run log and diagnostic files.")
        try:
            verify_results(run_root, plan)
        except (InputError, OSError, ValueError):
            provenance_failure = True
            raise
        archive_results(run_root)
        print("Analysis and automated QC completed. Review the report before study use; no scientific approval was issued.", flush=True)
        return 0
    except Exception as error:
        message = str(error) if isinstance(error, (InputError, ValueError)) else "The analysis could not finish. Review the run log and runtime installation."
        print(message, file=sys.stderr, flush=True)
        if run_root is not None:
            invalidate_results(run_root, message, provenance=provenance_failure)
            atomic_json(run_root / "execution_error.json", {"schema": 1, "status": "failed", "error": message, "approved": False, "finished_at": timestamp()})
            try:
                archive_results(run_root)
            except (InputError, OSError, ValueError) as archive_error:
                print("Diagnostic archive unavailable: " + str(archive_error), file=sys.stderr, flush=True)
        return 1


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("This runner is started by the toolkit's Run analysis button.")
    raise SystemExit(execute(Path(sys.argv[1]), sys.argv[2]))
