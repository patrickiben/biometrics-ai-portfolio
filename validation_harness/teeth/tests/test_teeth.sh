#!/usr/bin/env bash
###############################################################################
# Tests for the seeded-defect run (G10), the independent recomputation (G9) and the pieces
# they rely on. Run from anywhere:  bash validation_harness/teeth/tests/test_teeth.sh
# Set TEETH_SKIP_RUN=1 to skip the one slow test (a real run of D00, about two minutes).
# Temporary files go under $TMPDIR (outside the repository). Synthetic data only.
###############################################################################
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
T="$REPO/validation_harness/teeth"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/teeth-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok(){ if [ "$1" = 0 ]; then pass=$((pass+1)); echo "ok   $2"; else fail=$((fail+1)); echo "FAIL $2"; fi; }

# ---- apply_defect.py aborts on a missing or duplicated old_str, and never touches a checkout ----
mkdir -p "$TMP/copy/src"
printf 'a <- 1\nb <- 2\nb <- 2\n' > "$TMP/copy/src/x.R"
cat > "$TMP/reg.csv" <<'CSV'
"id","class","file","old_str","new_str","predicted_catcher","rationale"
"X1","test","src/x.R","zzz <- 9","zzz <- 8","SURVIVED","Missing old_str. Must abort."
"X2","test","src/x.R","b <- 2","b <- 3","SURVIVED","Duplicated old_str. Must abort."
"X3","test","src/x.R","a <- 1","a <- 5","SURVIVED","Unique old_str. Must apply."
"X4","test","n/a","","","NOT APPLICABLE","Not applicable. Nothing to plant."
CSV
before=$(cat "$TMP/copy/src/x.R")
python3 "$T/apply_defect.py" "$TMP/reg.csv" X1 "$TMP/copy" > /dev/null; rc=$?
[ $rc = 2 ] && [ "$(cat "$TMP/copy/src/x.R")" = "$before" ]; ok $? "apply_defect aborts on a missing old_str and changes nothing (exit $rc)"
python3 "$T/apply_defect.py" "$TMP/reg.csv" X2 "$TMP/copy" > /dev/null; rc=$?
[ $rc = 2 ] && [ "$(cat "$TMP/copy/src/x.R")" = "$before" ]; ok $? "apply_defect aborts on a duplicated old_str and changes nothing (exit $rc)"
python3 "$T/apply_defect.py" "$TMP/reg.csv" X4 "$TMP/copy" > /dev/null; rc=$?
[ $rc = 3 ]; ok $? "apply_defect reports a not-applicable row (exit $rc)"
mkdir "$TMP/copy/.git"
python3 "$T/apply_defect.py" "$TMP/reg.csv" X3 "$TMP/copy" > /dev/null; rc=$?
[ $rc = 4 ] && [ "$(cat "$TMP/copy/src/x.R")" = "$before" ]; ok $? "apply_defect refuses a git checkout (exit $rc)"
rmdir "$TMP/copy/.git"
python3 "$T/apply_defect.py" "$TMP/reg.csv" X3 "$TMP/copy" > /dev/null; rc=$?
[ $rc = 0 ] && grep -q '^a <- 5$' "$TMP/copy/src/x.R"; ok $? "apply_defect plants a unique old_str in a throwaway copy"
python3 "$T/apply_defect.py" "$T/defects.csv" --check-all "$REPO" > "$TMP/check.txt"; rc=$?
[ $rc = 0 ]; ok $? "every applicable registry row occurs exactly once in the current tree"

# ---- the hash guard refuses an edited registry -------------------------------------------
mkdir -p "$TMP/fake/validation_harness/teeth"
cp "$T/run_teeth.sh" "$T/apply_defect.py" "$T/defects.csv" "$T/defects.sha256" "$TMP/fake/validation_harness/teeth/"
sed -i.bak 's/SURVIVED/CAUGHT: G2/' "$TMP/fake/validation_harness/teeth/defects.csv"
out=$(TEETH_WORK="$TMP/work" bash "$TMP/fake/validation_harness/teeth/run_teeth.sh" 2>&1); rc=$?
[ $rc = 2 ] && printf '%s' "$out" | grep -q "refusing to run"; ok $? "run_teeth refuses an edited registry (exit $rc)"
want=$(awk 'NR==1{print $1}' "$T/defects.sha256")
have=$(python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$T/defects.csv")
[ "$want" = "$have" ]; ok $? "the committed registry matches its frozen hash"

# ---- G9: green with max relative difference < 1e-6 on the baseline; red after a 1% AUCLST bump ----
g9=$(cd "$REPO" && Rscript validation_harness/checks/independent_recompute.R sim_lifecycle/out 2>&1); rc=$?
mx=$(printf '%s\n' "$g9" | awk '/^G9_MAXREL/{print $2}')
[ $rc = 0 ] && printf '%s' "$g9" | grep -q "G9_VERDICT PASS" && python3 -c "import sys; sys.exit(0 if float('$mx') < 1e-6 else 1)"
ok $? "G9 passes on the committed sandbox outputs, max relative difference $mx < 1e-6"
mkdir -p "$TMP/out"; cp "$REPO"/sim_lifecycle/out/*.csv "$TMP/out/"
Rscript -e 'f <- commandArgs(TRUE)[1]; p <- read.csv(f, stringsAsFactors = FALSE); i <- which(p$PARAMCD == "AUCLST")[1]; p$AVAL[i] <- p$AVAL[i] * 1.01; write.csv(p, f, row.names = FALSE)' "$TMP/out/adpp.csv"
g9b=$(cd "$REPO" && Rscript validation_harness/checks/independent_recompute.R "$TMP/out" 2>&1); rc=$?
[ $rc = 1 ] && printf '%s' "$g9b" | grep -q "G9_VERDICT FAIL" && printf '%s' "$g9b" | grep -q "CHECK NCA parameters vs ADPP *FAIL"
ok $? "G9 goes red when one AUCLST in ADPP is raised by 1% (exit $rc)"
! grep -qE '^[^#]*source\(' "$REPO/validation_harness/checks/independent_recompute.R"; ok $? "G9 sources no code (it never loads simulate_adam.R or run_lifecycle.R)"

# ---- the Hy's Law grid, G6 scope and the package check -----------------------------------
gr=$(cd "$REPO" && Rscript -e 'r <- as.data.frame(testthat::test_dir("sasr_monitoring_wiki/trialmon_tests/testthat", filter = "hyslaw-grid", reporter = "silent", stop_on_failure = FALSE)); cat(nrow(r), sum(r$failed) + sum(r$error))' 2>&1 | tail -1)
[ "${gr#* }" = 0 ] && [ "${gr%% *}" -gt 0 ]; ok $? "the grid tests pass: exact verdicts for 901 to 907, narrative flags agree, label says potential Hy's Law ($gr)"
n6=$(cd "$REPO" && grep -rilE "\bedish\b|hy'?s.?law" sas_tlf_pseudocode r_tlf_pseudocode 2>/dev/null | grep -viE 'readme|index' | wc -l | tr -d ' ')
[ "$n6" = 0 ]; ok $? "G6 scope: no eDISH or Hy's Law terms in the TLF libraries ($n6 files)"
(cd "$REPO" && python3 package_qc.py > /dev/null 2>&1); rc=$?
[ $rc = 0 ]; ok $? "package_qc.py exits 0 (exit $rc)"

# ---- D00 (comment-only control) classifies as EQUIVALENT in a real run ---------------------
if [ "${TEETH_SKIP_RUN:-0}" = 1 ]; then
  echo "skip D00 run (TEETH_SKIP_RUN=1)"
else
  TEETH_WORK="$TMP/work" bash "$T/run_teeth.sh" --only D00 --out "$TMP/res" > "$TMP/d00.txt" 2>&1; rc=$?
  cls=$(python3 -c 'import json,sys; s=json.load(open(sys.argv[1])); print([r["class"] for r in s["rows"] if r["id"]=="D00"][0])' "$TMP/res/summary.json" 2>/dev/null)
  [ $rc = 0 ] && [ "$cls" = EQUIVALENT ]; ok $? "D00 (comment-only edit) classifies as EQUIVALENT ($cls)"
fi

echo "teeth tests: $pass passed, $fail failed"
[ $fail = 0 ]
