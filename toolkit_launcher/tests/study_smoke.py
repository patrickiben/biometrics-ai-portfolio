#!/usr/bin/env python3
"""CI smoke: private GUI restore and worked-study jobs through the real supervisor.

Run after the study workflow has restored and checked its baseline environment.
An explicit --allow-install authorizes the same private install action as the UI.
No global package library or original study output is written by this test.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from toolkit_launcher import jobs
from toolkit_launcher.runtime import ROOT, Workspace, source_files


EXPECTED = (
    "study/01_design/sample_size.csv",
    "study/03_adam/data/adsl.csv",
    "study/03_adam/data/adpp.xpt",
    "study/03_adam/data/json/adpp.json",
    "study/04_analysis/be_results.csv",
    "study/04_analysis/tlf/t_14_1_2.rtf",
    "study/04_analysis/report/report.html",
    "study/05_qc/qc_ledger.json",
    "study/06_csr/csr_section11.html",
    "study/06_csr/csr_check.json",
    "study/run_manifest.json",
    "study/index.html",
)


def fingerprint_source():
    return {name: hashlib.sha256(path.read_bytes()).hexdigest() for name, path in source_files(ROOT)}


def probe_renv(rscript, libraries=(), env=None):
    """Ask renv itself for the expanded platform-specific cache locations."""
    expression = (
        ".libPaths(c(commandArgs(TRUE),.libPaths())); "
        "if(!requireNamespace('renv',quietly=TRUE)) stop('The baseline renv restore must run before this smoke test'); "
        "cat('TOOLKIT_RENV=',normalizePath(find.package('renv'),winslash='/'),'\\n',sep=''); "
        "for(p in renv::paths$cache()) cat('TOOLKIT_CACHE=',p,'\\n',sep='')"
    )
    result = subprocess.run([rscript, "--vanilla", "-e", expression, *map(str, libraries)], cwd=ROOT,
                            env=env, capture_output=True, text=True, timeout=60)
    if result.returncode:
        raise RuntimeError("Could not inspect the baseline renv environment:\n" + result.stdout + result.stderr)
    package, caches = None, []
    for line in result.stdout.splitlines():
        if line.startswith("TOOLKIT_RENV="):
            package = Path(line.split("=", 1)[1])
        elif line.startswith("TOOLKIT_CACHE="):
            caches.append(Path(line.split("=", 1)[1]))
    if package is None or not (package / "DESCRIPTION").is_file() or not caches:
        raise RuntimeError("The baseline renv package/cache locations were not reported.")
    return package, caches


def seed_private_cache(root, plan, evidence):
    """Read the CI baseline cache; copy packages so all later writes stay private."""
    candidates = []
    library_root = ROOT / "study/renv/library"
    if library_root.is_dir():
        for directory, dirs, _files in os.walk(library_root, followlinks=False):
            if "renv" in dirs and (Path(directory) / "renv/DESCRIPTION").is_file():
                candidates.append(Path(directory))
    command = plan["commands"][0]
    package, source_caches = probe_renv(command["argv"][0], candidates)
    private_library = Path(command["env"]["R_LIBS_USER"])
    shutil.copytree(package, private_library / "renv", symlinks=False)
    target_env = dict(os.environ, **command["env"])
    _package, target_caches = probe_renv(command["argv"][0], [private_library], env=target_env)
    target = target_caches[0]
    private_root = (root.parent / "runtime").resolve()
    if not target.resolve().is_relative_to(private_root):
        raise RuntimeError("renv resolved its new cache outside the private project runtime.")
    copied = []
    for source in source_caches:
        if not source.is_dir():
            continue
        if source.resolve() == target.resolve() or target.resolve().is_relative_to(source.resolve()):
            raise RuntimeError("The baseline and private renv caches must be separate.")
        print(f"Copying baseline cache into private runtime: {source} -> {target}", flush=True)
        shutil.copytree(source, target, dirs_exist_ok=True, symlinks=False)
        copied.append(str(source))
    record = {"bootstrap_renv": str(package), "source_caches_copied": copied, "private_cache": str(target),
              "private_library_before_restore": str(private_library)}
    (evidence / "cache-seed.json").write_text(json.dumps(record, indent=2) + "\n")
    if not copied:
        print("No baseline cache directory exists; the explicit private restore may download locked packages.", flush=True)


def run_action(workspace, project_id, action, options, deadline, evidence):
    print(f"\nStarting GUI supervisor action: {action}", flush=True)
    record = workspace.start(project_id, action, options)
    logfile = workspace.job_dir / (record["id"] + ".log")
    cursor = 0
    last_notice = time.monotonic()
    while True:
        if logfile.is_file():
            with logfile.open("rb") as stream:
                stream.seek(cursor)
                chunk = stream.read()
                cursor = stream.tell()
            if chunk:
                print(chunk.decode("utf-8", errors="replace"), end="", flush=True)
                last_notice = time.monotonic()
        state = workspace.job_state(record["id"])
        if state["status"] != "running":
            # The last child write can land after the previous read.
            if logfile.is_file():
                with logfile.open("rb") as stream:
                    stream.seek(cursor)
                    print(stream.read().decode("utf-8", errors="replace"), end="", flush=True)
                shutil.copy2(logfile, evidence / (action + ".log"))
            (evidence / (action + ".json")).write_text(json.dumps(state, indent=2) + "\n")
            if state["status"] != "succeeded":
                raise RuntimeError(f"{action} finished with {state['status']}: {state.get('error')}")
            return state
        if time.monotonic() >= deadline:
            workspace.stop_job(record["id"])
            raise RuntimeError(f"{action} exceeded the smoke-test time budget; its process group was stopped.")
        if time.monotonic() - last_notice >= 30:
            print(f"{action} is still running…", flush=True)
            last_notice = time.monotonic()
        time.sleep(.5)


def verify_outputs(root, run_state, evidence):
    missing = [name for name in EXPECTED if not (root / name).is_file() or not (root / name).stat().st_size]
    if missing:
        raise AssertionError("The private rebuild did not recreate: " + ", ".join(missing))
    manifest = json.loads((root / "study/run_manifest.json").read_text())
    lock = json.loads((root / "study/renv.lock").read_text())
    if manifest.get("synthetic") is not True or manifest.get("r_version") != lock["R"]["Version"]:
        raise AssertionError("The rebuilt study manifest has the wrong synthetic/R-version identity.")
    results = manifest.get("results", {})
    if not results.get("qc_checks") or results.get("qc_pass") != results["qc_checks"]:
        raise AssertionError("The private worked-study QC ledger did not pass every expected check.")
    baseline = json.loads((ROOT / "study/run_manifest.json").read_text())
    if results != baseline["results"]:
        raise AssertionError("The private worked-study results differ from the baseline checked earlier in CI.")
    for name in ("study/01_design/sample_size.csv", "study/03_adam/data/adsl.csv", "study/04_analysis/be_results.csv"):
        if (root / name).read_bytes() != (ROOT / name).read_bytes():
            raise AssertionError("The private rebuild changed a deterministic baseline output: " + name)
    for package, version in manifest.get("packages", {}).items():
        if lock["Packages"].get(package, {}).get("Version") != version:
            raise AssertionError(f"The rebuilt manifest reports an unpinned package: {package} {version}")
    advertised = {item["path"] for item in run_state["outputs"]}
    if not {"study/run_manifest.json", "study/04_analysis/report/report.html"} <= advertised:
        raise AssertionError("The supervisor did not expose the rebuilt report and manifest to the GUI.")
    if "<html" not in (root / "study/04_analysis/report/report.html").read_text().lower():
        raise AssertionError("Quarto did not produce an HTML report.")
    for name in EXPECTED:
        target = evidence / "outputs" / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(root / name, target)
    return {"recreated_outputs": list(EXPECTED), "manifest_results": results, "locked_packages": len(lock["Packages"])}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--allow-install", action="store_true", help="Permit the private locked-package restore used by CI")
    parser.add_argument("--evidence", type=Path, required=True, help="Evidence folder outside the checkout")
    parser.add_argument("--timeout-seconds", type=int, default=1500)
    args = parser.parse_args(argv)
    if not args.allow_install:
        parser.error("--allow-install is required to test the explicit package-install action")
    if not 60 <= args.timeout_seconds <= 2700:
        parser.error("--timeout-seconds must be between 60 and 2700")
    evidence = args.evidence.expanduser().resolve()
    if evidence == ROOT or evidence.is_relative_to(ROOT):
        parser.error("Store smoke evidence outside the checkout")
    evidence.mkdir(parents=True, exist_ok=True)
    summary = {"status": "running", "scope": "Real GUI supervisor: private study.install followed by study.run"}
    workspace = None
    before = fingerprint_source()
    start = time.monotonic()
    deadline = start + args.timeout_seconds
    try:
        runtimes = jobs.detect_runtimes()
        for runtime in ("r", "quarto"):
            if not runtimes[runtime]["available"]:
                raise RuntimeError(f"The CI smoke requires {runtime}; complete the workflow's setup steps first.")
        base = Path(tempfile.mkdtemp(prefix="toolkit-study-smoke-", dir=os.environ.get("RUNNER_TEMP")))
        workspace = Workspace(base / "private")
        project = workspace.create_project("CI worked-study private restore")
        root = workspace.project(project["id"])
        summary.update(project_id=project["id"], project_root=str(root), runtimes=runtimes)
        install_plan = jobs.build_plan("study.install", root, {"allow_install": True}, settings=workspace.settings)
        seed_private_cache(root, install_plan, evidence)
        # Copied outputs must not make a broken rebuild look successful.
        for name in EXPECTED:
            (root / name).unlink(missing_ok=True)
        run_action(workspace, project["id"], "study.install", {"allow_install": True}, deadline, evidence)
        state = run_action(workspace, project["id"], "study.run", {}, deadline, evidence)
        summary.update(verify_outputs(root, state, evidence))
        if fingerprint_source() != before:
            raise AssertionError("The GUI workflow changed a file in the original checkout.")
        if (root / "study/renv/library").exists():
            raise AssertionError("Study packages were installed inside the copied source tree.")
        summary.update(status="passed", checkout_unchanged=True)
        print("\nPASS: private GUI install/run rebuilt the full worked study and report; original checkout unchanged.", flush=True)
        return 0
    except Exception as exc:
        summary.update(status="failed", error=str(exc))
        print(f"\nFAIL: {exc}", file=sys.stderr, flush=True)
        return 1
    finally:
        if workspace:
            workspace.close()
            log_target = evidence / "supervisor-jobs"
            shutil.copytree(workspace.job_dir, log_target, dirs_exist_ok=True)
        summary["elapsed_seconds"] = round(time.monotonic() - start, 2)
        (evidence / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")


if __name__ == "__main__":
    raise SystemExit(main())
