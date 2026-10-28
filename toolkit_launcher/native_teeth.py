"""Portable seeded-defect runner using Python file operations and fixed R argv.

The frozen registry, layered tests, output comparison and classification rules
are the original Bash runner's. The adapter fingerprints itself in each result
so later source changes make G10 stale. Only disposable copies are mutated.
"""
from __future__ import annotations

import argparse
import csv
import datetime
import filecmp
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

from native_harness import command, read, rscript_path, sha

GATE_SCRIPTS = (
    "validation_harness/run_harness.sh", "validation_harness/checks/conformance.R",
    "validation_harness/checks/g2_geo.py", "validation_harness/checks/independent_recompute.R", "package_qc.py",
    "sasr_monitoring_wiki/trialmon_tests/testthat/helper-trialmon.R",
    "sasr_monitoring_wiki/trialmon_tests/testthat/test-boundaries.R",
    "sasr_monitoring_wiki/trialmon_tests/testthat/test-hyslaw-grid.R",
    "sasr_monitoring_wiki/trialmon_tests/testthat/test-logic.R",
    "sasr_monitoring_wiki/trialmon_tests/testthat/test-server.R",
    "uat_irt/tests/test-logic.R", "validation_harness/teeth/run_teeth.sh",
    "validation_harness/teeth/apply_defect.py", "toolkit_launcher/native_harness.py",
    "toolkit_launcher/native_teeth.py", "toolkit_launcher/stub_profile.R",
)
EXECUTED = (
    "sim_lifecycle/run_lifecycle.R", "sim_lifecycle/simulate_adam.R", "sim_lifecycle/priors.R",
    "tlf_interpret/R/", "sasr_monitoring_wiki/trialmon_shiny/R/", "sasr_monitoring_wiki/trialmon_shiny/app.R",
)
TRIALMON_TESTS = ("test-boundaries.R", "test-hyslaw-grid.R", "test-logic.R", "test-server.R")

GENERATOR = '''suppressWarnings(source("sim_lifecycle/simulate_adam.R")); s <- simulate_study(sample_design("BE", N = 40), seed = 2026); for (nm in c("adsl","adex","adpc","adpp","adae","advs","adlb","adeg")) { d <- s[[nm]]; dbl <- vapply(d, is.double, logical(1)); d[dbl] <- lapply(d[dbl], signif, digits = 12); write.csv(d, sprintf("sim_lifecycle/out/%s.csv", nm), row.names = FALSE) }'''
TRIALMON = '''
files <- c("test-boundaries.R", "test-hyslaw-grid.R", "test-logic.R", "test-server.R")
r <- tryCatch(as.data.frame(testthat::test_dir("sasr_monitoring_wiki/trialmon_tests/testthat", reporter = "silent",
       stop_on_failure = FALSE, stop_on_warning = FALSE)), error = function(e) {
         cat("TRIALMON test runner error: ", conditionMessage(e), "\n", sep = ""); NULL
       })
for (f in files) {
  x <- if (is.null(r)) NULL else r[r$file == f, ]
  st <- if (is.null(x) || !nrow(x)) "ERROR" else if (sum(x$failed) + sum(x$error) > 0) "FAIL" else "PASS"
  cat("test trialmon/", f, " ", st, "\n", sep = "")
}
'''
FINGERPRINT = '''source("R/logic.R"); source("R/hyslaw_grid.R")
tm <- trialmon_load("data"); hl <- hyslaw_load("data")
for (x in list(trialmon_worklist(tm), trialmon_worklist(tm, trialmon_settings(alp_convention = TRUE)),
               hys_screen(tm$adlb), hyslaw_app_grid(tm, hl))) utils::write.csv(x, stdout(), row.names = FALSE)'''


def copy_project(root: Path, destination: Path):
    # destination is always a new child of this run's unique temporary folder.
    shutil.copytree(root, destination,
                    ignore=shutil.ignore_patterns(".git", "node_modules", ".quarto", "__pycache__", "package_qc_report.md"),
                    symlinks=False)


def write_result(result, path: Path):
    path.write_text(result.stdout + result.stderr, encoding="utf-8")
    return result.returncode


def run_layers(root: Path, tag: str, logs: Path, rr: str):
    facts = []
    driver = command([rr, "sim_lifecycle/run_lifecycle.R"], root)
    drc = write_result(driver, logs / (tag + ".driver.txt"))
    grc = 0
    if drc:
        grc = write_result(command([rr, "-e", GENERATOR], root), logs / (tag + ".generator.txt"))
    facts += [f"driver {drc}", f"generator {grc}"]
    # A failed runner must not reuse the ledger shipped with the copied project.
    (root / "validation_harness/ledger.json").unlink(missing_ok=True)
    harness = command([sys.executable, root / "toolkit_launcher/native_harness.py", root], root)
    write_result(harness, logs / (tag + ".harness.txt"))
    try:
        ledger = json.loads(read(root / "validation_harness/ledger.json"))
        facts += ["gate " + g["gate"].split()[0] + " " + g["status"].replace(" ", "_") for g in ledger["gates"]]
    except (OSError, ValueError, KeyError):
        facts.append("gate ledger unreadable")
    tests = command([rr, "-e", TRIALMON], root)
    write_result(tests, logs / (tag + ".tests.txt"))
    for name in TRIALMON_TESTS:
        match = re.search(r"^test trialmon/" + re.escape(name) + r" (PASS|FAIL|ERROR)$", tests.stdout, re.M)
        facts.append(f"test trialmon/{name} {match.group(1) if match else 'ERROR'}")
    uat = command([rr, "uat_irt/tests/test-logic.R"], root)
    write_result(uat, logs / (tag + ".uat.txt"))
    facts.append("test uat_irt/test-logic.R " + ("PASS" if uat.returncode == 0 else "FAIL"))
    fp = command([rr, "-e", FINGERPRINT], root / "sasr_monitoring_wiki/trialmon_shiny")
    write_result(fp, logs / (tag + ".trialmon.txt"))
    out = logs / (tag + ".out")
    out.mkdir()
    for path in (root / "sim_lifecycle/out").glob("*.csv"):
        shutil.copy2(path, out / path.name)
    (logs / (tag + ".facts")).write_text("\n".join(facts) + "\n", encoding="utf-8")
    return facts


def check_baseline(facts):
    """A missing check is not evidence that the unmutated copy passed."""
    gates, tests, other = {}, {}, {}
    for line in facts:
        parts = line.split()
        if len(parts) == 3 and parts[0] == "gate": gates[parts[1]] = parts[2]
        elif len(parts) == 3 and parts[0] == "test": tests[parts[1]] = parts[2]
        elif len(parts) == 2: other[parts[0]] = parts[1]
    bad = [f"{g} {gates.get(g, 'missing')}" for g in [f"G{i}" for i in range(1, 11)]
           if g not in ("G5", "G7", "G10") and gates.get(g) != "green"]
    required = ["trialmon/" + t for t in TRIALMON_TESTS] + ["uat_irt/test-logic.R"]
    bad += [f"{name} {tests.get(name, 'missing')}" for name in required if tests.get(name) != "PASS"]
    bad += [f"{name} exit {other.get(name, 'missing')}" for name in ("driver", "generator") if other.get(name) != "0"]
    if bad:
        raise ValueError("The unmutated copy does not pass every layer (" + "; ".join(bad) + "). No results written; see the baseline logs.")


def classify(root, logs, out, only, registry_hash, ids, r_version):
    E = {"_REPO": str(root), "_REG": str(root / "validation_harness/teeth/defects.csv"),
         "_LOGS": str(logs), "_OUT": str(out), "_ONLY": only, "_HASH": registry_hash,
         "_IDS": " ".join(ids), "_GATES": " ".join(GATE_SCRIPTS),
         "_EXEC": " ".join(EXECUTED), "_RVER": r_version}
    repo, logs, out = E["_REPO"], E["_LOGS"], E["_OUT"]
    with open(E["_REG"], encoding="utf-8", newline="") as handle:
        rows = {r["id"]: r for r in csv.DictReader(handle)}
    ids = E["_IDS"].split()
    def facts(tag):
        f = {"gate": {}, "test": {}}
        p = os.path.join(logs, tag + ".facts")
        for line in Path(p).read_text(encoding="utf-8").splitlines() if os.path.exists(p) else []:
            k = line.split()
            if not k:
                continue
            if k[0] in ("gate", "test") and len(k) == 3:
                f[k[0]][k[1]] = k[2]
            elif len(k) == 2:
                f[k[0]] = k[1]
        return f
    def text(tag, ext):
        p = os.path.join(logs, f"{tag}.{ext}")
        return Path(p).read_text(encoding="utf-8", errors="replace") if os.path.exists(p) else None
    base = facts("BASE")
    # a valid measurement needs every layer passing on the unmutated copy
    bad = [f"{g} {s}" for g, s in base["gate"].items() if g not in ("G5", "G7", "G10") and s != "green"]
    bad += [f"{t} {s}" for t, s in base["test"].items() if s != "PASS"]
    bad += [f"{k} exit {base.get(k)}" for k in ("driver", "generator") if base.get(k) != "0"]
    if bad:
        raise SystemExit("run_teeth: the unmutated copy does not pass every layer (" + "; ".join(bad) + "); no results written")
    def label(r):
        return re.split(r"(?<=[^0-9])\.\s", r["rationale"], maxsplit=1)[0].rstrip(".")
    def parse_pred(p):
        cls, _, lay = p.partition(":")
        return cls.strip(), [x.strip() for x in lay.split(";") if x.strip()]
    executed = E["_EXEC"].split()
    def runs(path):
        return any(path == e or (e.endswith("/") and path.startswith(e)) for e in executed)
    with open(os.path.join(repo, "sim_lifecycle/out/adpc.csv"), encoding="utf-8", newline="") as handle:
        adpc = list(csv.DictReader(handle))
    pre = [r for r in adpc if r["ATPTN"] in ("0", "0.0")]
    pos = sum(1 for r in pre if r["AVAL"] not in ("", "NA") and float(r["AVAL"]) > 0)
    tcols = [c for c in adpc[0].keys() if c in ("AFRLT", "ARELTM", "ARRLT", "ATPTREF", "ADTM")]
    na_evidence = (f"ADPC has {len(pre)} predose records, {pos} above zero, so a 5% predose exclusion never fires; "
                   f"actual-time variables in ADPC: {', '.join(tcols) if tcols else 'none'} (only nominal ATPTN)")
    results = []
    for i in ids:
        r = rows[i]; f = facts(i)
        pcls, players = parse_pred(r["predicted_catcher"])
        res = {"id": i, "defect": label(r), "defect_class": r["class"], "file": r["file"], "predicted": r["predicted_catcher"]}
        if f.get("na") == "1":
            res.update({"class": "NOT APPLICABLE", "layers": "", "differs": "", "note": na_evidence})
        else:
            layers = []
            if f.get("generator") not in (None, "0"):
                layers.append("generator error")
            elif f.get("driver") not in (None, "0"):
                layers.append("driver error")
            for g, s in f["gate"].items():
                if g not in ("G5", "G10") and s != base["gate"].get(g):
                    layers.append(g)
            for t, s in f["test"].items():
                if s != "PASS" and base["test"].get(t) == "PASS":
                    layers.append(t)
            differs = []
            for fn in sorted(os.listdir(os.path.join(logs, "BASE.out"))):
                a, b = os.path.join(logs, "BASE.out", fn), os.path.join(logs, i + ".out", fn)
                if not os.path.exists(b) or not filecmp.cmp(a, b, shallow=False):
                    differs.append(fn)
            if text("BASE", "driver.txt") != text(i, "driver.txt"):
                differs.append("printed driver output")
            if text("BASE", "trialmon.txt") != text(i, "trialmon.txt"):
                differs.append("TRIALMON screening outputs")
            if layers:
                cls, note = "CAUGHT", ""
            elif not differs and runs(r["file"]):
                cls, note = "EQUIVALENT", ("no output or printed result differs from the unmutated copy on the shipped data "
                                           "(diff); not proof that the change has no effect on other data")
            else:
                cls = "SURVIVED"
                note = ("no layer runs this program, so nothing can differ or fail" if not runs(r["file"])
                        else "outputs differ from the unmutated copy, but no layer fails")
            res.update({"class": cls, "layers": "; ".join(layers), "differs": "; ".join(differs), "note": note})
        al = [x.strip() for x in res["layers"].split(";") if x.strip()]
        res["status"] = "as predicted" if res["class"] == pcls and all(p in al for p in players) else "differs from prediction"
        res["beyond_prediction"] = "; ".join(x for x in al if x not in players)
        results.append(res)
    day = datetime.date.today().isoformat()
    cols = ["id", "defect", "defect_class", "file", "predicted", "class", "layers", "status", "beyond_prediction", "differs", "note"]
    csv_name = f"teeth_{day}.csv"
    with open(os.path.join(out, csv_name), "w", encoding="utf-8", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=cols); w.writeheader(); w.writerows(results)
    def sha(p):
        return hashlib.sha256((Path(repo) / p).read_bytes()).hexdigest()
    counts = {k: sum(1 for x in results if x["class"] == k) for k in ("CAUGHT", "SURVIVED", "EQUIVALENT", "NOT APPLICABLE")}
    S = {"run_date": day, "r_version": E["_RVER"], "registry": "validation_harness/teeth/defects.csv",
         "registry_sha256": E["_HASH"], "n_defects": len(rows), "n_run": len(results), "partial": bool(E["_ONLY"]),
         "gate_scripts": {p: sha(p) for p in E["_GATES"].split()}, "runner": "portable-python",
         "baseline": {"gates": base["gate"], "tests": base["test"]},
         "counts": counts, "as_predicted": sum(1 for x in results if x["status"] == "as predicted"),
         "as_predicted_rule": "same class as predicted, and every predicted catcher among the layers that caught it (a defect caught by more layers than predicted still matches; beyond_prediction lists the extra layers)",
         "results_csv": f"validation_harness/teeth/results/{csv_name}" if not E["_ONLY"] else os.path.join(out, csv_name),
         "rows": results,
         "note": "Counts by class for this hand-picked, pre-registered list; they estimate nothing beyond it (no detection rate, no interval). Survivors are disclosures, not failures. EQUIVALENT is decided by diff on the shipped data, so it is not proof that a change has no effect."}
    txt = json.dumps(S, indent=1, ensure_ascii=False)
    (Path(out) / "summary.json").write_text(txt + "\n", encoding="utf-8")
    if not E["_ONLY"]:
        p = os.path.join(repo, "validation_harness/index.html")
        h = Path(p).read_text(encoding="utf-8")
        h2 = re.sub(r'(<script id="teeth-data" type="application/json">\n).*?(\n</script>)', lambda m: m.group(1) + txt + m.group(2), h, count=1, flags=re.S)
        if h2 != h:
            Path(p).write_text(h2, encoding="utf-8")
    print()
    for x in results:
        print(f"{x['id']}  {x['class']:<14} {x['layers'] or '-':<55} {x['status']}")
    print("counts:", ", ".join(f"{k} {v}" for k, v in counts.items()), f"(as predicted: {S['as_predicted']} of {len(results)})")
    print("results:", os.path.join(out, csv_name), "and", os.path.join(out, "summary.json"))


def run(root: Path, only="", out: Path | None = None):
    root = root.resolve()
    td = root / "validation_harness/teeth"
    registry = td / "defects.csv"
    if not registry.is_file() or not (td / "defects.sha256").is_file():
        raise ValueError("The complete frozen defect registry is required.")
    wanted = read(td / "defects.sha256").split()[0]
    have = sha(registry)
    if have != wanted:
        raise ValueError("defects.csv does not match its frozen hash; refusing to run.")
    applies = command([sys.executable, td / "apply_defect.py", registry, "--check-all", root], root)
    if applies.returncode:
        raise ValueError("The registry no longer applies to this project: " + applies.stdout)
    with registry.open(encoding="utf-8", newline="") as handle:
        rows = list(csv.DictReader(handle))
    requested = [x.strip() for x in only.split(",") if x.strip()]
    ids = [row["id"] for row in rows if not requested or row["id"] in requested]
    unknown = set(requested) - {row["id"] for row in rows}
    if unknown:
        raise ValueError("Unknown defect IDs: " + ", ".join(sorted(unknown)))
    parent = Path(os.environ.get("TEETH_WORK", tempfile.gettempdir())).expanduser().resolve()
    if parent == root or root in parent.parents:
        raise ValueError("The defect-test work folder must be outside the toolkit project.")
    parent.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix="toolkit-teeth-", dir=parent))
    logs = work / "logs"
    logs.mkdir()
    out = out.expanduser().resolve() if out else (work / "results" if requested else td / "results")
    if requested and out == (td / "results").resolve():
        raise ValueError("Partial runs cannot overwrite the committed full-run results folder.")
    out.mkdir(parents=True, exist_ok=True)
    rr = rscript_path()
    # Reproduction is deliberately model-free, including when this adapter is
    # invoked directly instead of through the control panel.
    profile = root / "toolkit_launcher/stub_profile.R"
    if not profile.is_file():
        raise ValueError("The deterministic drafting profile is missing from the project.")
    os.environ["R_PROFILE_USER"] = str(profile)
    print(f"Seeded-defect run: registry {have}; {len(ids)} selected defects; logs {logs}", flush=True)
    print("Running the unmutated baseline", flush=True)
    baseline = work / "BASE"
    copy_project(root, baseline)
    try:
        facts = run_layers(baseline, "BASE", logs, rr)
    finally:
        shutil.rmtree(baseline)
    check_baseline(facts)
    print("Baseline passed every automatic layer", flush=True)
    for index, did in enumerate(ids, 1):
        print(f"Defect {index}/{len(ids)}: {did}", flush=True)
        applies = command([sys.executable, td / "apply_defect.py", registry, did, root, "--check"], root)
        write_result(applies, logs / (did + ".apply.txt"))
        if applies.returncode == 3:
            (logs / (did + ".facts")).write_text("na 1\n", encoding="utf-8")
            continue
        if applies.returncode:
            raise ValueError(f"{did} no longer applies; stopping. See {logs}.")
        copy = work / did
        copy_project(root, copy)
        try:
            applied = command([sys.executable, td / "apply_defect.py", registry, did, copy], root)
            with (logs / (did + ".apply.txt")).open("a", encoding="utf-8") as handle:
                handle.write(applied.stdout + applied.stderr)
            if applied.returncode:
                raise ValueError(f"{did} could not be planted; stopping. See {logs}.")
            run_layers(copy, did, logs, rr)
        finally:
            shutil.rmtree(copy)
    version = command([rr, "-e", "cat(R.version.string)"], root).stdout.strip()
    classify(root, logs, out, only, have, ids, version)
    print(f"Detailed logs retained at {logs}", flush=True)
    return out


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    parser.add_argument("--only", default="")
    parser.add_argument("--out", type=Path)
    args = parser.parse_args(argv)
    try:
        run(args.root, args.only, args.out)
    except (OSError, ValueError, subprocess.SubprocessError) as exc:
        print("Toolkit seeded-defect check: " + str(exc), file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
