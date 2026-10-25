#!/usr/bin/env bash
###############################################################################
# run_teeth.sh: the seeded-defect ("teeth") run behind gate G10 of the validation harness.
#
# Measures what the harness and the module tests catch. For each defect in the frozen registry
# (defects.csv, whose SHA-256 is in defects.sha256; the run refuses to start if they differ):
#   1. copy the working tree (not .git) to a throwaway folder, $TMPDIR/teeth/<id>/; no branch
#   2. plant the defect with apply_defect.py (abort unless old_str occurs exactly once)
#   3. regenerate the sandbox outputs (Rscript sim_lifecycle/run_lifecycle.R) over the copy's
#      committed outputs, so G1's byte-for-byte check cannot fire. If the driver stops with an
#      error, the eight domain files are written straight from simulate_study() (as G1 writes
#      them), so the later layers still see the defect's data
#   4. run bash validation_harness/run_harness.sh and the module tests (TRIALMON testthat files
#      one by one, uat_irt/tests/test-logic.R)
#   5. classify against the unmutated copy, run through the same steps:
#        CAUGHT          a layer that passes on the unmutated copy fails (the layers are listed:
#                        a gate, a test file, or the driver or generator stopping with an error)
#        EQUIVALENT      nothing caught it, the defect sits in code the run executes, and no
#                        output or printed result differs from the unmutated copy (by diff).
#                        The diff runs on the shipped data only, so EQUIVALENT means "no
#                        effect on this data", not proof that the change has no effect
#        SURVIVED        nothing caught it otherwise (outputs differ, or no layer runs the code)
#        NOT APPLICABLE  the registry marks the defect inapplicable to this sandbox (file n/a)
#   A defect counts "as predicted" when its class matches the prediction and every predicted
#   catcher is among the layers that actually caught it (more layers than predicted still match;
#   beyond_prediction lists them).
# The counts describe this hand-picked list only; they are not a detection rate.
#
# Writes results/teeth_<date>.csv and results/summary.json (registry hash, gate-script hashes,
# counts by class, one row per defect) and refreshes the copy embedded in
# validation_harness/index.html (#teeth-data, shown in the #teeth section). run_harness.sh turns
# G10 "stale" when the registry or a gate script changes after this run.
#
# Usage: bash validation_harness/teeth/run_teeth.sh [--only D00,D05] [--out DIR]
#   --only  run some defects; the results then go to --out (default $TMPDIR/teeth/results), never
#           to results/, and the page is not touched
#   Needs R (base R; testthat, shiny, bslib, DT and ggplot2 for the TRIALMON tests), python3, rsync.
# Synthetic data only. QC-process engineering adapted from the teeth check in the author's
# consilience-engine software; it measures the harness, it is not a statistical method.
###############################################################################
set -uo pipefail
TDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$TDIR/../.." && pwd)"
REG="$TDIR/defects.csv"
ONLY=""; OUT=""
WORK="${TEETH_WORK:-${TMPDIR:-/tmp}/teeth}"; WORK="${WORK%/}"
while [ $# -gt 0 ]; do
  case "$1" in
    --only) ONLY="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    *) echo "run_teeth: unknown argument $1"; exit 4 ;;
  esac
done

# ---- the registry must be the frozen one --------------------------------------
sha(){ python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$1"; }
WANT=$(awk 'NR==1{print $1}' "$TDIR/defects.sha256" 2>/dev/null)
HAVE=$( [ -f "$REG" ] && sha "$REG" )
if [ -z "${WANT:-}" ] || [ "${HAVE:-}" != "$WANT" ]; then
  echo "run_teeth: defects.csv (sha256 ${HAVE:-missing}) does not match the frozen hash in defects.sha256 (${WANT:-missing}); refusing to run"
  exit 2
fi
if ! python3 "$TDIR/apply_defect.py" "$REG" --check-all "$REPO" > /dev/null; then
  python3 "$TDIR/apply_defect.py" "$REG" --check-all "$REPO" | grep -v ': applies\|not applicable'
  echo "run_teeth: the registry no longer applies to this tree; refusing to run"; exit 2
fi
case "$WORK/" in "$REPO"/*) echo "run_teeth: the work folder must be outside the repository"; exit 4 ;; esac
if [ -n "$ONLY" ]; then OUT="${OUT:-$WORK/results}"; else OUT="${OUT:-$TDIR/results}"; fi
mkdir -p "$WORK/logs" "$OUT"
LOGS="$WORK/logs"

# the scripts whose behavior the results describe; G10 turns stale when any of them changes
GATE_SCRIPTS="validation_harness/run_harness.sh validation_harness/checks/conformance.R
validation_harness/checks/independent_recompute.R package_qc.py
sasr_monitoring_wiki/trialmon_tests/testthat/helper-trialmon.R
sasr_monitoring_wiki/trialmon_tests/testthat/test-boundaries.R
sasr_monitoring_wiki/trialmon_tests/testthat/test-hyslaw-grid.R
sasr_monitoring_wiki/trialmon_tests/testthat/test-logic.R
sasr_monitoring_wiki/trialmon_tests/testthat/test-server.R
uat_irt/tests/test-logic.R validation_harness/teeth/run_teeth.sh validation_harness/teeth/apply_defect.py"
# code the run executes (the driver and generator, the drafting check they call, and the TRIALMON
# code the tests and the output fingerprint load): only a defect here can be EQUIVALENT
EXECUTED="sim_lifecycle/run_lifecycle.R sim_lifecycle/simulate_adam.R sim_lifecycle/priors.R
tlf_interpret/R/ sasr_monitoring_wiki/trialmon_shiny/R/ sasr_monitoring_wiki/trialmon_shiny/app.R"

mkcopy(){ rm -rf "$1"; mkdir -p "$1"
  rsync -a --exclude='.git' --exclude='node_modules' --exclude='.quarto' --exclude='package_qc_report.md' "$REPO/" "$1/"; }

# run every layer on one copy; facts go to $LOGS/<tag>.*
run_layers(){ local C="$1" T="$2"
  : > "$LOGS/$T.facts"
  ( cd "$C" && Rscript sim_lifecycle/run_lifecycle.R ) > "$LOGS/$T.driver.txt" 2>&1; local drc=$? grc=0
  if [ $drc -ne 0 ]; then
    ( cd "$C" && Rscript -e 'suppressWarnings(source("sim_lifecycle/simulate_adam.R")); s <- simulate_study(sample_design("BE", N = 40), seed = 2026); for (nm in c("adsl","adex","adpc","adpp","adae","advs","adlb","adeg")) { d <- s[[nm]]; dbl <- vapply(d, is.double, logical(1)); d[dbl] <- lapply(d[dbl], signif, digits = 12); write.csv(d, sprintf("sim_lifecycle/out/%s.csv", nm), row.names = FALSE) }' ) > "$LOGS/$T.generator.txt" 2>&1; grc=$?
  fi
  echo "driver $drc" >> "$LOGS/$T.facts"; echo "generator $grc" >> "$LOGS/$T.facts"
  ( cd "$C" && bash validation_harness/run_harness.sh ) > "$LOGS/$T.harness.txt" 2>&1
  python3 - "$C/validation_harness/ledger.json" >> "$LOGS/$T.facts" <<'PY'
import json, sys
try:
    L = json.load(open(sys.argv[1], encoding="utf-8"))
    for g in L["gates"]:
        print("gate", g["gate"].split()[0], g["status"].replace(" ", "_"))
except Exception as e:
    print("gate ledger unreadable")
PY
  ( cd "$C" && Rscript -e '
files <- c("test-boundaries.R", "test-hyslaw-grid.R", "test-logic.R", "test-server.R")
r <- tryCatch(as.data.frame(testthat::test_dir("sasr_monitoring_wiki/trialmon_tests/testthat", reporter = "silent",
       stop_on_failure = FALSE, stop_on_warning = FALSE)), error = function(e) NULL)
for (f in files) {
  x <- if (is.null(r)) NULL else r[r$file == f, ]
  st <- if (is.null(x) || !nrow(x)) "ERROR" else if (sum(x$failed) + sum(x$error) > 0) "FAIL" else "PASS"
  cat("test trialmon/", f, " ", st, "\n", sep = "")
}' ) > "$LOGS/$T.tests.txt" 2>&1
  grep '^test ' "$LOGS/$T.tests.txt" >> "$LOGS/$T.facts"
  if ( cd "$C" && Rscript uat_irt/tests/test-logic.R ) > "$LOGS/$T.uat.txt" 2>&1; then echo "test uat_irt/test-logic.R PASS" >> "$LOGS/$T.facts"
  else echo "test uat_irt/test-logic.R FAIL" >> "$LOGS/$T.facts"; fi
  # output fingerprint: the nine sandbox files are diffed directly; TRIALMON's screening outputs here
  ( cd "$C/sasr_monitoring_wiki/trialmon_shiny" && Rscript -e 'source("R/logic.R"); source("R/hyslaw_grid.R")
tm <- trialmon_load("data"); hl <- hyslaw_load("data")
for (x in list(trialmon_worklist(tm), trialmon_worklist(tm, trialmon_settings(alp_convention = TRUE)),
               hys_screen(tm$adlb), hyslaw_app_grid(tm, hl))) utils::write.csv(x, stdout(), row.names = FALSE)' ) > "$LOGS/$T.trialmon.txt" 2>&1
  mkdir -p "$LOGS/$T.out"; cp "$C"/sim_lifecycle/out/*.csv "$LOGS/$T.out/"
}

echo "== Seeded-defect run (G10): registry sha256 $HAVE, work folder $WORK =="
echo "-- unmutated copy"
mkcopy "$WORK/BASE"; run_layers "$WORK/BASE" BASE; rm -rf "$WORK/BASE"
cat "$LOGS/BASE.facts" | tr '\n' ' '; echo

IDS=$(python3 - "$REG" "$ONLY" <<'PY'
import csv, sys
ids = [r["id"] for r in csv.DictReader(open(sys.argv[1], encoding="utf-8", newline=""))]
only = [x for x in sys.argv[2].split(",") if x]
print(" ".join(i for i in ids if not only or i in only))
PY
)
for ID in $IDS; do
  rm -rf "$LOGS/$ID".*
  python3 "$TDIR/apply_defect.py" "$REG" "$ID" "$REPO" --check > "$LOGS/$ID.apply.txt"; rc=$?
  if [ $rc -eq 3 ]; then echo "-- $ID not applicable"; echo "na 1" > "$LOGS/$ID.facts"; continue; fi
  echo "-- $ID"
  mkcopy "$WORK/$ID"
  if ! python3 "$TDIR/apply_defect.py" "$REG" "$ID" "$WORK/$ID" >> "$LOGS/$ID.apply.txt"; then
    echo "run_teeth: $ID did not apply; stopping"; cat "$LOGS/$ID.apply.txt"; exit 2
  fi
  run_layers "$WORK/$ID" "$ID"; rm -rf "$WORK/$ID"
done

# ---- classify, write the results, refresh the page copy ----------------------------
export _REPO="$REPO" _REG="$REG" _LOGS="$LOGS" _OUT="$OUT" _ONLY="$ONLY" _HASH="$HAVE" _IDS="$IDS"
export _GATES="$GATE_SCRIPTS" _EXEC="$EXECUTED" _RVER="$(Rscript -e 'cat(R.version.string)' 2>/dev/null)"
python3 - <<'PY'
import csv, datetime, filecmp, hashlib, json, os, re
E = os.environ
repo, logs, out = E["_REPO"], E["_LOGS"], E["_OUT"]
rows = {r["id"]: r for r in csv.DictReader(open(E["_REG"], encoding="utf-8", newline=""))}
ids = E["_IDS"].split()
def facts(tag):
    f = {"gate": {}, "test": {}}
    p = os.path.join(logs, tag + ".facts")
    for line in open(p, encoding="utf-8") if os.path.exists(p) else []:
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
    return open(p, encoding="utf-8", errors="replace").read() if os.path.exists(p) else None
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
adpc = list(csv.DictReader(open(os.path.join(repo, "sim_lifecycle/out/adpc.csv"), encoding="utf-8")))
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
    return hashlib.sha256(open(os.path.join(repo, p), "rb").read()).hexdigest()
counts = {k: sum(1 for x in results if x["class"] == k) for k in ("CAUGHT", "SURVIVED", "EQUIVALENT", "NOT APPLICABLE")}
S = {"run_date": day, "r_version": E["_RVER"], "registry": "validation_harness/teeth/defects.csv",
     "registry_sha256": E["_HASH"], "n_defects": len(rows), "n_run": len(results), "partial": bool(E["_ONLY"]),
     "gate_scripts": {p: sha(p) for p in E["_GATES"].split()},
     "baseline": {"gates": base["gate"], "tests": base["test"]},
     "counts": counts, "as_predicted": sum(1 for x in results if x["status"] == "as predicted"),
     "as_predicted_rule": "same class as predicted, and every predicted catcher among the layers that caught it (a defect caught by more layers than predicted still matches; beyond_prediction lists the extra layers)",
     "results_csv": f"validation_harness/teeth/results/{csv_name}" if not E["_ONLY"] else os.path.join(out, csv_name),
     "rows": results,
     "note": "Counts by class for this hand-picked, pre-registered list; they estimate nothing beyond it (no detection rate, no interval). Survivors are disclosures, not failures. EQUIVALENT is decided by diff on the shipped data, so it is not proof that a change has no effect."}
txt = json.dumps(S, indent=1, ensure_ascii=False)
open(os.path.join(out, "summary.json"), "w", encoding="utf-8").write(txt + "\n")
if not E["_ONLY"]:
    p = os.path.join(repo, "validation_harness/index.html")
    h = open(p, encoding="utf-8").read()
    h2 = re.sub(r'(<script id="teeth-data" type="application/json">\n).*?(\n</script>)', lambda m: m.group(1) + txt + m.group(2), h, count=1, flags=re.S)
    if h2 != h:
        open(p, "w", encoding="utf-8").write(h2)
print()
for x in results:
    print(f"{x['id']}  {x['class']:<14} {x['layers'] or '-':<55} {x['status']}")
print("counts:", ", ".join(f"{k} {v}" for k, v in counts.items()), f"(as predicted: {S['as_predicted']} of {len(results)})")
print("results:", os.path.join(out, csv_name), "and", os.path.join(out, "summary.json"))
PY
