#!/usr/bin/env bash
###############################################################################
# Trial-Management Validation Harness: runner.
# Runs the automatable checks of the 10 gates against THIS repository's SAS/R TLF
# pseudocode libraries + synthetic ADaM, and emits EVIDENCE_LEDGER.md + ledger.json.
# Most checks are structural (files, patterns, counts); G1 re-runs the synthetic study;
# G9 recomputes the sandbox's PK, BE and AE results; G10 reads the last seeded-defect run
# (teeth/run_teeth.sh), which measures what the other gates catch.
# G5 is a manual record, not computed here; G7 stays "not signed" until a named
# statistician signs it. SAS is never executed (no license).
# Automate detection; the biostatistician signs. 100% synthetic data; no PHI.
# Usage:  bash validation_harness/run_harness.sh
###############################################################################
set -uo pipefail
HDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HDIR/.." && pwd)"
cd "$REPO"
SAS=sas_tlf_pseudocode; R=r_tlf_pseudocode
GATE=(); GUARDS=(); STATUS=(); EVID=()
add(){ GATE+=("$1"); GUARDS+=("$2"); STATUS+=("$3"); EVID+=("$4"); }
green(){ [ "$1" = green ] && echo green || echo red; }

echo "== Trial-Management Validation Harness =="

# ---- G1 Reproducibility & environment --------------------------------------
# Parse check: every .R file in the repository, hidden directories such as .github included and
# .git excluded, each file counted once (paths are normalized before unique()).
read RTOT RBAD < <(Rscript -e 'f<-list.files(".",pattern="[.]R$",recursive=TRUE,full.names=TRUE,all.files=TRUE); f<-f[!grepl("(^|/)[.]git(/|$)",f)]; f<-unique(normalizePath(f)); b<-sum(vapply(f,function(x)inherits(try(parse(x),silent=TRUE),"try-error"),logical(1))); cat(length(f),b)' 2>/dev/null)
# doubles are written at 12 significant digits, exactly as run_lifecycle.R writes them
REPRO=$(Rscript -e 'setwd("'"$REPO"'"); suppressWarnings(source("sim_lifecycle/simulate_adam.R")); set.seed(2026); s<-simulate_study(sample_design("BE",N=40),seed=2026); td<-tempfile(); dir.create(td); for(nm in c("adsl","adex","adpc","adpp","adae","advs","adlb","adeg")) { d<-s[[nm]]; dbl<-vapply(d,is.double,logical(1)); d[dbl]<-lapply(d[dbl],signif,digits=12); write.csv(d,file.path(td,paste0(nm,".csv")),row.names=FALSE) }; same<-vapply(c("adsl","adex","adpc","adpp","adae","advs","adlb","adeg"),function(nm) identical(readLines(file.path(td,paste0(nm,".csv"))),readLines(file.path("sim_lifecycle/out",paste0(nm,".csv")))),logical(1)); cat(sum(same))' 2>/dev/null)
G1=green; [ "${RBAD:-1}" = 0 ] && [ "${REPRO:-0}" = 8 ] || G1=red
add "G1 Reproducibility & environment" "the sandbox's eight committed output files regenerate byte for byte from code and seed, and every R program parses" "$G1" \
    "$RTOT R files parse (${RBAD:-?} fail; every .R file in the repository, each counted once, hidden directories included, .git excluded); the synthetic study regenerates ${REPRO:-0} of 8 committed ADaM-shaped files (adsl, adex, adpc, adpp, adae, advs, adlb, adeg) byte for byte from seed 2026 (base R)"

# ---- G2 Numeric-provenance (numbers <- validated tool) ---------------------
# Log-scale geometric statistics, program by program (checks/g2_geo.py). Until 2026-10-26 this was
# a repo-wide grep that one file anywhere could satisfy. The R programs are found by content
# (pkstats(), geomean or geocv, a Geo Mean or Geo CV% column, exp(mean()) or 10^mean(), or a model
# with a dose, treatment, period or sequence term). Comments are ignored and strings are never read
# as code. Display wrappers (sprintf(), round(), format(), ...) are unwrapped and every branch of
# if/else, ifelse, if_else, coalesce, case_when, pmin and pmax is checked on its own: each branch of
# every geomean and Geo Mean column must be NA, a geometric name or function of the file, or exactly
# exp() of a log-scale mean (mean(), coef() or similar of a natural-log value; 10^ of a log10 one),
# so exp(log(mean(x))) and mean(exp(log(x))) fail; each branch of every geocv and Geo CV% column must
# be NA, a geometric-CV name or function, or exactly [100*]sqrt(exp(V) - 1) or sqrt(expm1(V)) with V a
# natural-log variance. NA counts only as a branch of the column or statistic being checked: a name
# assigned only NA (an empty-data row, say) is not a geometric name. Every model response
# must be log-derived, and each program must use log() or pkstats(), whose body is held to the same
# rules. Each SAS twin at the same path (assignments read also after else, when or otherwise, and
# round() unwrapped) must assign geomean only as missing, a geometric name, or exp() of a PROC MEANS
# mean of a natural-log variable (10** for log10), geocv only as missing, a geometric-CV name or
# [100*]sqrt(exp(V)-1) of a natural-log variance or squared SD (a variable assigned only missing is
# not a geometric name), and every MODEL response must be
# log-derived; it must also call a passing %pkstats or back-transform its own such mean in the same
# base (a model-only program's twin must fit a MODEL). The script prints
# <passing> <checked> <evidence>; G2 is green only when the two counts are equal and not 0.
read -r GEO GEOTOT GEOE < <(python3 validation_harness/checks/g2_geo.py "$R" "$SAS")
NDIST=$(( $(grep -rl 'n_distinct(USUBJID)' $R 2>/dev/null | wc -l) + $(grep -rl 'CLASS USUBJID\|distinct USUBJID' $SAS 2>/dev/null | wc -l) ))
DRAFT=$(grep -rilE 'hallucinat|reject.*number|number.*not (in|from)|selftest|self-test' tlf_interpret 2>/dev/null | wc -l | tr -d ' ')
G2=green; { [ "${GEOTOT:-0}" -gt 0 ] && [ "${GEO:-0}" = "${GEOTOT:-x}" ] && [ "$NDIST" -gt 0 ] && [ "$DRAFT" -gt 0 ]; } || G2=red
add "G2 PK and count convention scans" "PK programs use log-scale geometric statistics, counts use distinct participants, and the drafter's number check has a self-test (pattern scans; they do not show where a reported number comes from)" "$G2" \
    "per-program scans: ${GEOE:-the per-program check did not run}; distinct-participant counting in $NDIST programs; drafter number-validation self-test present ($DRAFT)"

# ---- G3 Data conformance & integrity (CDISC + no PHI) ----------------------
CONF=$(Rscript validation_harness/checks/conformance.R sim_lifecycle/out 2>/dev/null | grep G3_VERDICT | awk '{print $2}')
SUBJ=$(grep -rniE '\bsubjects?\b' $SAS $R 2>/dev/null | grep -ivE 'subjid|usubjid' | wc -l | tr -d ' ')
# scan SHIPPED DELIVERABLE surfaces (analysis data + docs) for participant PHI. Excludes the raw
# public-registry calibration corpus (sim_lifecycle/data/, not a deliverable) and infra dirs.
PII=$(grep -rniE '[0-9]{3}-[0-9]{3}-[0-9]{4}|[a-z]{2,}\.[a-z]{2,}@[a-z]+\.(com|net)' "$REPO" \
      --include='*.csv' --include='*.html' --include='*.md' 2>/dev/null \
      | grep -vE 'sim_lifecycle/data/|/validation_harness/|noreply|example\.(com|net)|https?://|@author|Copyright \(c\)' | wc -l | tr -d ' ')
G3=green; { [ "${CONF:-FAIL}" = PASS ] && [ "$SUBJ" = 0 ] && [ "$PII" = 0 ]; } || G3=red
add "G3 Data structure & integrity" "the analysis data passes the custom structural checks (not Pinnacle 21 or CDISC CORE), is intact, and PHI-free" "$G3" \
    "custom structural checks ${CONF:-?} (checks/conformance.R; not Pinnacle 21 or CDISC CORE); $SUBJ trial-sense 'subject' in programs; $PII PHI/PII hits in deliverable data/docs (raw public-registry calibration corpus excluded)"

# ---- G4 Double-programming parity (SAS <-> R) ------------------------------
NSAS=$(find $SAS -name '*.sas' ! -name '00_setup*' | wc -l | tr -d ' ')
NR=$(find $R -name '*.R' ! -name '00_setup*' | wc -l | tr -d ' ')
read MM COLL < <(python3 - <<'PY'
import re,glob,os,collections
def num(p):
    t=open(p,encoding="utf-8",errors="ignore").read()
    m=re.search(r'num\s*=\s*"?([0-9]+(?:\.[0-9]+)+)',t); return m.group(1) if m else None
mm=0; coll=0
for des in os.listdir("sas_tlf_pseudocode"):
    dd=f"sas_tlf_pseudocode/{des}"
    if not os.path.isdir(dd): continue
    for sas in glob.glob(f"{dd}/*.sas"):
        name=os.path.basename(sas)[:-4]
        if name.startswith("00_setup"): continue
        rf=f"r_tlf_pseudocode/{des}/{name}.R"
        if os.path.exists(rf) and num(sas)!=num(rf): mm+=1
    for lang,ext in (("sas_tlf_pseudocode","sas"),("r_tlf_pseudocode","R")):
        by=collections.defaultdict(list)
        for f in glob.glob(f"{lang}/{des}/*.{ext}"):
            n=os.path.basename(f);
            if n.startswith("00_setup"): continue
            k=num(f)
            if k: by[k].append(n)
        coll+=sum(1 for v in by.values() if len(v)>1)
print(mm,coll)
PY
)
G4=green; { [ "$NSAS" = "$NR" ] && [ "${MM:-1}" = 0 ] && [ "${COLL:-1}" = 0 ] && [ "${RBAD:-1}" = 0 ]; } || G4=red
add "G4 SAS/R twin structural parity" "the SAS and R twins line up program for program (structure only)" "$G4" \
    "$NSAS SAS / $NR R twin programs; $MM twin TLF-number mismatches; $COLL within-design number collisions; all R parse. Structural only: SAS is not executed (no license), so no outputs are compared, and the R twins were written to mirror the SAS"

# ---- G5 Adversarial QC panel (manual record) -------------------------------
# Not computed by this script: a hand-entered record of an AI-agent review panel.
REVER="6 previously-pending twin pairs re-verified by the panel (5 confirmed, 1 sad/t_lab_marked_abnormal denominator gap found and fixed)"
add "G5 Adversarial QC panel" "no skeptical reader can break the deliverable" "manual" \
    "manual record, not computed here: an AI-agent review panel reported 51 P0/P1 parity findings resolved; $REVER. Human review of these findings is not yet recorded"

# ---- G6 Regulatory & reporting standard -----------------------------------
EDISH=$(grep -rilE "\bedish\b|hy'?s.?law" $SAS $R 2>/dev/null | grep -viE 'readme|index' | wc -l | tr -d ' ')
# ICH E14 conventions, checked by pattern (not a regulatory review): every categorical QTc
# program tests >450/>480/>500 ms and change >30/>60 ms, and every QTc change figure uses the
# one convention consistent with those categories: reference lines at 30 and 60 ms (the E14
# categorical thresholds for an increase from baseline) and no +10 ms line. The 10 ms threshold
# applies to the upper bound of a placebo-corrected mean effect in a thorough QT study, which
# these descriptive change figures do not estimate.
read E14CAT E14CATN E14TEN E14CAT3060 E14FIGN < <(python3 - <<'PY'
import glob,re
cat=glob.glob("r_tlf_pseudocode/*/t_ecg_qtc_categorical.R")+glob.glob("sas_tlf_pseudocode/*/t_ecg_qtc_categorical.sas")
fig=glob.glob("r_tlf_pseudocode/*/f_qtc_change.R")+glob.glob("sas_tlf_pseudocode/*/f_qtc_change.sas")
def ok_cat(p):
    t=open(p,encoding="utf-8",errors="ignore").read()
    return all(re.search(r">\s*"+n+r"\b",t) for n in ("450","480","500","30","60"))
def ten(p):
    t=open(p,encoding="utf-8",errors="ignore").read()
    return bool(re.search(r"yintercept\s*=\s*10\b|refline\s+10\b",t))
def cat3060(p):
    t=open(p,encoding="utf-8",errors="ignore").read()
    return bool(re.search(r"yintercept\s*=\s*30\b|refline\s+30\b",t)) and bool(re.search(r"yintercept\s*=\s*60\b|refline\s+60\b",t))
n10=sum(map(ten,fig)); n36=sum(map(cat3060,fig))
print(sum(map(ok_cat,cat)),len(cat),n10,n36,len(fig))
PY
)
G6=green; { [ "${COLL:-1}" = 0 ] && [ "$EDISH" = 0 ] && [ "$E14CATN" -gt 0 ] && [ "$E14CAT" = "$E14CATN" ] && [ "$E14FIGN" -gt 0 ] && [ "$E14CAT3060" = "$E14FIGN" ] && [ "$E14TEN" = 0 ]; } || G6=red
add "G6 Reporting conventions" "TLF numbering, scope and ICH E14 conventions hold (pattern checks, not a regulatory review)" "$G6" \
    "$COLL TLF-number collisions; $EDISH out-of-scope eDISH/Hy's terms in programs; ICH E14 categorical thresholds (>450/480/500 ms, change >30/60 ms) in $E14CAT/$E14CATN QTc tables; QTc change figures: $E14CAT3060/$E14FIGN draw the 30/60 ms ICH E14 categorical reference lines and $E14TEN draw a +10 ms line (the convention is 30/60 ms on every figure, no +10 ms line)"

# ---- G7 AI-governance documentation (accountability needs a signature) ------
# The scans below can only show that the AI-use limits are written down and that no PHI
# turns up. The gate guards accountability, which needs a named statistician's signature,
# so it reports "not signed" (never green) until that sign-off exists; failed scans are red.
# generic scan: no experimental / non-standard / unvalidated method labels in the analysis programs
JARG=$(grep -rniE 'experimental (engine|method|analytic)|research-grade (engine|model)|non-standard (analytic )?method|unvalidated (engine|model)' sas_tlf_pseudocode r_tlf_pseudocode sim_lifecycle 2>/dev/null | wc -l | tr -d ' ')
GOV=$(grep -rilE 'frozen|temperature 0|human[ -]gate|pinned|human approv' tlf_interpret 2>/dev/null | wc -l | tr -d ' ')
G7="not signed"; { [ "$JARG" = 0 ] && [ "$PII" = 0 ] && [ "$GOV" -gt 0 ]; } || G7=red
add "G7 AI-governance documentation present" "the drafter's AI-use limits (frozen model, human gate) are written down and no PHI turns up (file scans); accountability needs a named statistician's signature, not yet given" "$G7" \
    "$JARG experimental/non-standard method labels in analysis programs; $PII PHI hits; frozen-model + human-gate discipline documented in $GOV tlf_interpret files. Not signed: the scans pass, but no one has signed for AI use"

# ---- G8 Package & GUI consistency (whole package) --------------------------
python3 package_qc.py >/dev/null 2>&1; PKGRC=$?
PKGN=$(grep -oE '[0-9]+ issue' package_qc_report.md 2>/dev/null | grep -oE '[0-9]+' | head -1)
PKGP=$(grep -oE 'Scanned [0-9]+ HTML' package_qc_report.md 2>/dev/null | grep -oE '[0-9]+' | head -1)
G8=green; [ "${PKGRC:-1}" = 0 ] || G8=red
add "G8 Package & GUI consistency" "the package is navigable, linked, and internally consistent" "$G8" \
    "package_qc.py: ${PKGN:-?} issues across ${PKGP:-?} HTML pages, the Markdown files and the text of the published spreadsheets, Word files, decks, PDFs and JSON (broken links, retired content, missing or orphaned pages, terminology, framing and count drift)"

# ---- G9 Independent recomputation -----------------------------------------
# A separately written recomputation (never sources the sandbox code) of ADPP and of the
# driver's printed results from ADPC, ADEX, ADSL and ADAE; relative tolerance 1e-6.
G9OUT=$(Rscript validation_harness/checks/independent_recompute.R sim_lifecycle/out 2>/dev/null)
G9V=$(printf '%s\n' "$G9OUT" | awk '/^G9_VERDICT/{print $2}')
G9P=$(printf '%s\n' "$G9OUT" | awk '/^G9_PROFILES/{print $2}')
G9M=$(printf '%s\n' "$G9OUT" | awk '/^G9_MAXREL/{print $2}')
G9E=$(printf '%s\n' "$G9OUT" | sed -n 's/^G9_ENGINES //p')
G9N=$(printf '%s\n' "$G9OUT" | grep -cE '^CHECK .* (PASS|FAIL)( |$)')
G9F=$(printf '%s\n' "$G9OUT" | grep -cE '^CHECK .* FAIL( |$)')
G9=green; [ "${G9V:-FAIL}" = PASS ] || G9=red
add "G9 Independent recomputation" "the sandbox's NCA parameters (ADPP) and printed results (geometric means and CV%, GMR and 90% CI, AE participant counts) match a separately written recomputation from ADPC, ADEX, ADSL and ADAE (same author: a re-derivation, not double programming by a second person)" "$G9" \
    "${G9P:-0} profiles compared; maximum relative difference ${G9M:-NA} (tolerance 1e-6); ${G9F:-?} of ${G9N:-?} checks failed; engines: ${G9E:-none} (checks/independent_recompute.R; AUC(0-t) from the predose zero, BLQ as 0)"

# ---- G10 Harness sensitivity (seeded defects) ------------------------------
# Reads teeth/results/summary.json, written by teeth/run_teeth.sh. Green only while that run
# used the current frozen registry and the current gate scripts; otherwise "stale". Survivors
# are disclosures of what the harness misses, not failures.
read -r G10 G10E < <(python3 - <<'PY'
import hashlib, json, os
T = "validation_harness/teeth"
def sha(p):
    return hashlib.sha256(open(p, "rb").read()).hexdigest()
reg = sha(f"{T}/defects.csv") if os.path.exists(f"{T}/defects.csv") else None
frozen = open(f"{T}/defects.sha256").read().split()[0] if os.path.exists(f"{T}/defects.sha256") else None
try:
    S = json.load(open(f"{T}/results/summary.json", encoding="utf-8"))
except Exception:
    S = None
why = []
if reg is None:
    why.append("no defect registry")
elif frozen != reg:
    why.append("defects.csv no longer matches its frozen hash in defects.sha256")
if S is None:
    why.append("no seeded-defect run recorded")
else:
    if S.get("registry_sha256") != reg:
        why.append("the last run used a different registry")
    changed = [p for p, h in S.get("gate_scripts", {}).items() if not os.path.exists(p) or sha(p) != h]
    if changed:
        why.append("changed since the last run: " + ", ".join(changed))
    if S.get("partial"):
        why.append("the last run covered only part of the registry")
if reg:
    import subprocess
    chk = subprocess.run(["python3", f"{T}/apply_defect.py", f"{T}/defects.csv", "--check-all", "."],
                         capture_output=True, text=True)
    if chk.returncode != 0:
        gone = [l.split(":")[0] for l in chk.stdout.splitlines() if "occurs" in l or "does not exist" in l]
        why.append("the registry no longer applies to the current code (" + ", ".join(gone) + ")")
ev = []
if reg:
    import csv
    n = len(list(csv.DictReader(open(f"{T}/defects.csv", encoding="utf-8", newline=""))))
    ev.append(f"registry of {n} defects frozen at sha256 {reg}")
if S:
    c = S.get("counts", {})
    ev.append(f"last run {S.get('run_date')}: " + ", ".join(f"{k} {c.get(k, 0)}" for k in ("CAUGHT", "SURVIVED", "EQUIVALENT", "NOT APPLICABLE")))
    surv = [f"{r['id']} ({r['defect']})" for r in S.get("rows", []) if r.get("class") == "SURVIVED"]
    if surv:
        ev.append("survived (disclosed, not failures): " + "; ".join(surv))
    ev.append("the counts describe this hand-picked list only, not a detection rate (teeth/run_teeth.sh)")
txt = "; ".join(ev)
if why:
    txt = "stale: " + "; ".join(why) + ". " + txt
print(("green" if not why else "stale") + " " + txt.replace("|", "/").replace("\n", " "))
PY
)
add "G10 Harness sensitivity" "the harness's own reach: a pre-registered list of programming defects is planted one at a time in a throwaway copy, the outputs are regenerated so G1 cannot fire, and each defect is recorded as caught (by which gate or test), survived, equivalent or not applicable (QC-process engineering; it measures the harness, not a statistical method)" "${G10:-stale}" \
    "${G10E:-stale: the summary could not be read}"

# ---- emit ledger -----------------------------------------------------------
STAMP="$(date '+%Y-%m-%d %H:%M %Z')"; RVER="$(Rscript -e 'cat(R.version.string)' 2>/dev/null)"
n=${#GATE[@]}; greens=0; manual=0; unsigned=0
for s in "${STATUS[@]}"; do
  [ "$s" = green ] && greens=$((greens+1)); [ "$s" = manual ] && manual=$((manual+1)); [ "$s" = "not signed" ] && unsigned=$((unsigned+1))
done
scanned=$((n-manual-unsigned))
{
  echo "# Evidence Ledger: Trial-Management Validation Harness"
  echo
  echo "_Generated $STAMP · $RVER · $greens of $scanned automated gates green, $manual manual record, $unsigned not signed · run on this repo's synthetic deliverables · human sign-off pending on every gate._"
  echo
  echo "| Gate | Guards (the fragile object) | Status | Evidence (automated) | Human sign-off |"
  echo "|---|---|:--:|---|---|"
  for i in $(seq 0 $((n-1))); do
    badge="${STATUS[$i]}"
    echo "| **${GATE[$i]}** | ${GUARDS[$i]} | $badge | ${EVID[$i]} | ☐ pending |"
  done
  echo
  echo "> **The split:** every evidence cell above is produced by this script except G5, which is a"
  echo "> manual record. G7's scans pass, but its status stays \"not signed\" until a named statistician"
  echo "> signs for AI use. G10 reads the last seeded-defect run (teeth/run_teeth.sh) and turns \"stale\""
  echo "> when the registry or a gate script changes after it. Most checks are structural; SAS is never"
  echo "> executed. The **Human sign-off** column"
  echo "> is not automated: a named biostatistician reviews each gate and signs, and no gate is signed yet."
  echo "> Re-run: \`bash validation_harness/run_harness.sh\`"
} > validation_harness/EVIDENCE_LEDGER.md

# ledger.json: emit via env vars (avoids array-quoting pitfalls)
export _G="$(printf '%s\n' "${GATE[@]}")"; export _U="$(printf '%s\n' "${GUARDS[@]}")"
export _S="$(printf '%s\n' "${STATUS[@]}")"; export _E="$(printf '%s\n' "${EVID[@]}")"
export _STAMP="$STAMP" _RVER="$RVER" _GREENS="$greens" _N="$n" _MANUAL="$manual" _UNSIGNED="$unsigned"
python3 - <<'PY'
import os,json,re
g=os.environ["_G"].splitlines(); u=os.environ["_U"].splitlines()
s=os.environ["_S"].splitlines(); e=os.environ["_E"].splitlines()
rows=[{"gate":a,"guards":b,"status":c,"evidence":d,"sign_off":"pending"} for a,b,c,d in zip(g,u,s,e)]
L={"generated":os.environ["_STAMP"],"r_version":os.environ["_RVER"],
   "green":int(os.environ["_GREENS"]),"manual":int(os.environ["_MANUAL"]),"unsigned":int(os.environ["_UNSIGNED"]),
   "total":int(os.environ["_N"]),"gates":rows}
txt=json.dumps(L,indent=1,ensure_ascii=False)
open("validation_harness/ledger.json","w",encoding="utf-8").write(txt)
# keep the copy embedded in index.html (used when the page is opened from disk) in step
p="validation_harness/index.html"; h=open(p,encoding="utf-8").read()
h=re.sub(r'(<script id="ledger" type="application/json">\n).*?(\n</script>)',lambda m:m.group(1)+txt+m.group(2),h,count=1,flags=re.S)
open(p,"w",encoding="utf-8").write(h)
PY
echo; echo "Ledger: $greens of $scanned automated gates green, $manual manual, $unsigned not signed -> validation_harness/EVIDENCE_LEDGER.md + ledger.json (+ index.html copy)"
