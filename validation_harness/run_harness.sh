#!/usr/bin/env bash
###############################################################################
# Trial-Management Validation Harness: runner.
# Runs the automatable checks of the 8 gates against THIS repository's SAS/R TLF
# pseudocode libraries + synthetic ADaM, and emits EVIDENCE_LEDGER.md + ledger.json.
# Most checks are structural (files, patterns, counts); G1 re-runs the synthetic study.
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
read RTOT RBAD < <(Rscript -e 'f<-list.files(c("'$R'","sim_lifecycle","'$SAS'/.."),pattern="[.]R$",recursive=TRUE,full.names=TRUE); f<-unique(f); b<-sum(vapply(f,function(x)inherits(try(parse(x),silent=TRUE),"try-error"),logical(1))); cat(length(f),b)' 2>/dev/null)
REPRO=$(Rscript -e 'setwd("'"$REPO"'"); suppressWarnings(source("sim_lifecycle/simulate_adam.R")); set.seed(2026); s<-simulate_study(sample_design("BE",N=40),seed=2026); td<-tempfile(); dir.create(td); for(nm in c("adsl","adex","adpc","adpp","adae","advs","adlb","adeg")) write.csv(s[[nm]],file.path(td,paste0(nm,".csv")),row.names=FALSE); same<-vapply(c("adsl","adex","adpc","adpp","adae","advs","adlb","adeg"),function(nm) identical(readLines(file.path(td,paste0(nm,".csv"))),readLines(file.path("sim_lifecycle/out",paste0(nm,".csv")))),logical(1)); cat(sum(same))' 2>/dev/null)
G1=green; [ "${RBAD:-1}" = 0 ] && [ "${REPRO:-0}" = 8 ] || G1=red
add "G1 Reproducibility & environment" "the sandbox's eight committed output files regenerate byte for byte from code and seed, and every R program parses" "$G1" \
    "$RTOT R programs parse (${RBAD:-?} fail); the synthetic study regenerates ${REPRO:-0} of 8 committed ADaM-shaped files (adsl, adex, adpc, adpp, adae, advs, adlb, adeg) byte for byte from seed 2026 (base R)"

# ---- G2 Numeric-provenance (numbers <- validated tool) ---------------------
GEO=$(grep -rl 'exp(mean(log' $R 2>/dev/null | wc -l | tr -d ' ')
NDIST=$(( $(grep -rl 'n_distinct(USUBJID)' $R 2>/dev/null | wc -l) + $(grep -rl 'CLASS USUBJID\|distinct USUBJID' $SAS 2>/dev/null | wc -l) ))
DRAFT=$(grep -rilE 'hallucinat|reject.*number|number.*not (in|from)|selftest|self-test' tlf_interpret 2>/dev/null | wc -l | tr -d ' ')
G2=green; { [ "$GEO" -gt 0 ] && [ "$NDIST" -gt 0 ] && [ "$DRAFT" -gt 0 ]; } || G2=red
add "G2 PK and count convention scans" "PK programs use log-scale geometric statistics, counts use distinct participants, and the drafter's number check has a self-test (pattern scans; they do not show where a reported number comes from)" "$G2" \
    "static scans: geometric-on-log-scale in $GEO PK programs; distinct-participant counting in $NDIST programs; drafter number-validation self-test present ($DRAFT)"

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
# program tests >450/>480/>500 ms and change >30/>60 ms; every QTc change figure draws the
# +10 ms reference line, or every one draws the 30/60 ms lines (one convention, applied uniformly).
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
G6=green; { [ "${COLL:-1}" = 0 ] && [ "$EDISH" = 0 ] && [ "$E14CATN" -gt 0 ] && [ "$E14CAT" = "$E14CATN" ] && [ "$E14FIGN" -gt 0 ] && { [ "$E14TEN" = "$E14FIGN" ] || [ "$E14CAT3060" = "$E14FIGN" ]; }; } || G6=red
add "G6 Reporting conventions" "TLF numbering, scope and ICH E14 conventions hold (pattern checks, not a regulatory review)" "$G6" \
    "$COLL TLF-number collisions; $EDISH out-of-scope eDISH/Hy's terms in programs; ICH E14 categorical thresholds (>450/480/500 ms, change >30/60 ms) in $E14CAT/$E14CATN QTc tables; QTc change figures: $E14TEN/$E14FIGN draw the +10 ms mean-effect line and $E14CAT3060/$E14FIGN draw 30/60 ms lines (one convention must apply to all)"

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
  echo "_Generated $STAMP · $RVER · $greens of $scanned scan-based gates green, $manual manual record, $unsigned not signed · run on this repo's synthetic deliverables · human sign-off pending on every gate._"
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
  echo "> signs for AI use. Most checks are structural; SAS is never executed. The **Human sign-off** column"
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
echo; echo "Ledger: $greens of $scanned scan-based gates green, $manual manual, $unsigned not signed -> validation_harness/EVIDENCE_LEDGER.md + ledger.json (+ index.html copy)"
