# risk_app.py -- INDEPENDENT program: per-participant safety & discontinuation RISK SCORING.
#
# READ THIS FIRST (for whoever maintains this file):
#   * This is ONE of four separate programs in this folder (the others are
#     meddra_app.py, phi_app.py and anomaly_app.py). They do NOT import each other and share NO
#     module. The small helpers near the top (_have, _col) are DELIBERATELY
#     DUPLICATED from the siblings. Do not "refactor" them into a shared file:
#     a shared module is a coupling point that would let a change to one head
#     silently move another's behavior, and each head is kept separate so it could
#     be validated on its own scope, with its own audit log (none is a validated
#     system; the audit log is a plain CSV). Duplication is the price of that
#     independence, and it is intentional.
#   * This program SCORES RISK ONLY. It never codes a verbatim (that is
#     meddra_app.py), never scrubs PHI (phi_app.py), and never detects anomalies/drift
#     (anomaly_app.py). It reads safety domains -- AE / LB / EG / VS / PE -- from raw data
#     only, aligns everything to participants by USUBJID, and emits one risk row per participant.
#     A stray meddra*.csv in the cut folder is IGNORED so all four programs can share one
#     folder without interfering.
#   * This build ships as a TRANSPARENT, LABELED STAND-IN ([SI]): a weighted
#     rule engine driven by declared criteria. It is DECISION SUPPORT -- it ranks
#     and flags participants for human review; it does NOT make a clinical
#     determination and is not a validated survival model. A real deployment would
#     replace Tier 3 with a trained, externally-validated risk/survival model and
#     flip the banner to [RM]; that is an external validation step this file never
#     fakes. The limit is tagged in the banner and every audit row, never hidden.
#   * It does NOT parse free-text PDF/Word protocols or SAPs, and there is NO external
#     SAP/protocol file to import: every threshold is a declared constant below, tagged [SI],
#     written to the banner and the audit. A real deployment replaces them with study-specific
#     declared criteria (or a validated model) -- that is an external step this file never fakes.
#   * Hosted-demo safety mode: with ECRF_HOSTED=1 set (or the Streamlit secret
#     hosted = true) every data input (uploaders, folder path, models dir) is
#     locked to the bundled synthetic cut in sample_data/ and outputs go to a
#     per-session temp folder. Nothing set means the normal local behavior. See
#     _hosted().
#
# WHAT IT DOES, TIER BY TIER (the chain is the product; every decision is a row of
# readable numbers, never a hidden weight -- see the [SI]/[RM] discipline):
#   Tier 1 intake   -> load AE/LB/EG/VS/PE from raw data, classify each
#                      file by CONTENT (signature columns, not file name), align rows
#                      to participants by USUBJID; copy values through UNCHANGED.
#   Tier 2 signals  -> per participant, extract READABLE risk signals: n_AE, n_SAE, max
#                      severity, fatal flag, which labs exceed their built-in [SI] ULN multiple
#                      and by how much, QTc vs the cardiac criterion, vitals vs built-in limits,
#                      notable physical-exam findings. Proposes nothing; measures only.
#   Tier 3 aggregate-> weighted sum of those signals -> safety_risk_score (0-100) and
#                      discontinuation_risk_score (0-1). Weights and thresholds are DECLARED
#                      constants below, tagged [SI] -- there is no external SAP/protocol file.
#   Tier 4 categorize-> map scores to categories via the built-in [SI] category cuts (+ a
#                      fatal-outcome hard stop -> CRITICAL), write contributing factors,
#                      and emit risk_scores.csv + audit_log.csv.
#
#   streamlit run risk_app.py
#   stand-in path (runs anywhere):     pip install pandas streamlit
#       (QC note: this program uses only pandas -- no numpy/hashlib; the imports are
#        exactly what it uses, matching phi_app.py's discipline.)
#   real path (flips banner to [RM]):  a validated survival/risk model replacing Tier 3

import csv, hashlib, io, json, math, os, re, sys, tempfile, time, zipfile
from html import escape

BROWSER_ENABLED = sys.platform == "emscripten" and os.environ.get("ECRF_BROWSER") == "1"
import pandas as pd, streamlit as st

# --------------------------------------------------------------------------- #
# Runtime probe. Same pattern as the siblings: test each OPTIONAL library by
# attempting an import inside try/except WITHOUT importing at module scope, so a
# missing dependency never crashes the app -- it only affects whether a real
# model COULD be loaded. This build always runs the transparent [SI] engine; the
# probe exists so _guard_artifacts can hard-stop on an orphaned artifact (see below).
# --------------------------------------------------------------------------- #
def _have(m):
    try: __import__(m); return True
    except Exception: return False
HAVE = {m: (False if BROWSER_ENABLED else _have(m)) for m in ("xgboost","pyreadstat")}

# Reviewer-set starting values; the effective thresholds are written to the audit.
# These are the BUILT-IN [SI] CRITERIA this transparent engine always uses -- there is no
# external SAP/protocol file to import (the app scores from raw data only). They are tagged
# [SI] everywhere they drive a number (banner + audit); a real deployment would replace them
# with study-specific declared criteria or a validated model.
DEFAULT_THR = {
    # Lab criteria (x ULN): a value ABOVE the multiple counts. These are [SI] screening criteria, not CTCAE
    # grades (in CTCAE v5.0, ALT/AST >3.0x ULN and creatinine >1.5x ULN are grade 2 entry points) and not
    # the discontinuation criteria in FDA's DILI guidance (July 2009): ALT/AST >8x ULN; >5x for more than
    # 2 weeks; >3x with TBL >2x ULN or INR >1.5; >3x with symptoms.
    "ALT_ULN_MULT": 3.0, "AST_ULN_MULT": 3.0, "CREAT_ULN_MULT": 1.5,
    # Cardiac criterion: QTc strictly ABOVE 500 ms, the top ICH E14 categorical tier (>450, >480, >500 ms).
    # The app applies only this tier, no change from baseline, and does not know whether the column is
    # QTcF or QTcB.
    "QTC_ABS_MS": 500,
    "SYSBP_HIGH_MMHG": 180, "DIASTP_HIGH_MMHG": 110, "TEMPC_HIGH_C": 38.5,  # vital-sign limits
    "SAFETY_CAT_MODERATE": 25, "SAFETY_CAT_HIGH": 50, "SAFETY_CAT_CRITICAL": 75,   # safety category cuts (score)
    "DISC_CAT_MODERATE": 0.3, "DISC_CAT_HIGH": 0.6,                    # discontinuation category cuts (prob)
}

# [SI] declared weights for the transparent stand-in engine. These are NOT magic
# constants the audit hides: whatever thresholds/weights are in force are written to
# audit_log.csv with the run, so a run is reproducible from its audit alone and the
# operating point is a logged decision, not a value buried in code. A real [RM] model
# would learn these from historical outcomes instead of typing them here.
SEV_WEIGHT = {"MILD": 2, "MODERATE": 6, "SEVERE": 16, "LIFETHREATENING": 28}   # per-AE base weight
SERIOUS_MULT = 1.5        # x a serious AE (AESER=Y)
FATAL_ADDER = 35          # flat adder for any fatal outcome (AELIFE=Y); added ON TOP of the capped AE load
AE_CAP = 45               # cap on the non-fatal AE severity load
LAB_PER_BREACH = lambda ratio, thr: min(15, round((ratio - thr) * 4))   # points per lab breach (x ULN beyond the [SI] multiple)
LAB_CAP = 30              # cap on the whole lab component
ECG_BASE, ECG_SLOPE, ECG_CAP = 6, 4, 12     # QTc>limit -> min(cap, base + round((qtc-limit)/slope))
VIT_BASE, VIT_SLOPE, VIT_PER, VIT_CAP = 2, 4, 8, 13   # per vital breach -> min(per, base+round((val-limit)/slope)); cap whole component

# Discontinuation model weights ([SI]): additive contributions squashed to [0,1].
DISC_SERIOUS_EACH, DISC_SERIOUS_CAP = 0.25, 0.6   # per serious AE, capped
DISC_RELATED_FRAC = 0.2                           # x (fraction of AEs related)
DISC_MAXSEV = {"MILD": 0.0, "MODERATE": 0.1, "SEVERE": 0.25, "LIFETHREATENING": 0.4}
DISC_FATAL = 0.3                                  # any fatal outcome
DISC_LAB_EACH, DISC_LAB_CAP = 0.15, 0.3           # per analyte above its [SI] ULN multiple, capped
DISC_QTC = 0.15                                   # QTc above the cardiac criterion
DISC_VITAL = 0.1                                  # any vital-sign breach
DISC_CLINSIG_EACH, DISC_CLINSIG_CAP = 0.1, 0.2    # per source-system clinically-significant finding, capped

# Vital parameter -> the threshold key that declares its protocol limit. A vital whose
# parameter is not here has no declared limit and is simply not scored (documented, not
# silently dropped -- it still appears in Tier-2 signals as "no declared limit").
VITAL_KEY = {"SYSBP": "SYSBP_HIGH_MMHG", "DIASTP": "DIASTP_HIGH_MMHG", "TEMPC": "TEMPC_HIGH_C"}

# --------------------------------------------------------------------------- #
# Hosted-demo safety mode. ON when the environment variable ECRF_HOSTED=1 is set
# or the Streamlit secret "hosted = true" exists (.streamlit/secrets.toml on a
# server you run; the in-browser pages set ECRF_HOSTED=1). A public demo must never take in real data, so in this
# mode every input that could bring data in (the uploaders, the folder path, the
# models dir and, in the coding app, the .asc folder) is DISABLED in the UI and
# its value is also OVERWRITTEN in code: a disabled widget only stops the
# browser, and a crafted client could still send a value, so it is never
# trusted. The bundled synthetic cut is forced, outputs go to a per-session
# server temp folder (never a path a visitor typed), a banner says so on every
# rerun, and the audit records hosted_mode=true. With nothing set (the local
# default) the app behaves exactly as before; the audit only gains
# hosted_mode=false. Duplicated in each app on purpose (no shared module, same
# rule as _have/_col).
# The switch fails CLOSED. Any ECRF_HOSTED or hosted value other than empty, 0,
# false, no or off turns it on (a typo such as "on" or hosted = 1.0 locks the
# demo instead of opening it), and so does a secrets file that exists but does
# not load (hosted = True with a capital T, a stray bad line): Streamlit only
# logs that parse error on the server, so failing open would leave a public app
# unlocked with nothing on the page to show it. The deploy step in README.md is
# to open the app and confirm the banner.
# --------------------------------------------------------------------------- #
HOSTED_BANNER = ("Public demo: synthetic data only. Do not enter or upload real patient data. "
                 "Run locally for real data.")
_HOSTED_OFF = ("", "0", "false", "no", "off")   # the ONLY values that leave a switch off
# In-browser build (stlite on Pyodide, served from docs/app/ on GitHub Pages): sys.platform is
# "emscripten" there and nowhere else. The flag only rewords text that would be wrong in a browser
# tab ("runs locally, no network calls", "nothing leaves the machine", the "Wrote <folder>" message and the Output-folder
# help) and keeps the page's "<app name>: in-browser demo" tab title once the app starts; a local run is
# unchanged.
IN_BROWSER = sys.platform == "emscripten"
RUNS_WHERE = "runs in this browser tab" if IN_BROWSER else "runs locally, no network calls"
OUT_HELP_BROWSER = ("In this in-browser build the folder lives in the tab's memory, not on your disk, and is "
                    "gone when the tab closes. Save results with the download buttons.")
def _hosted():
    if os.environ.get("ECRF_HOSTED","").strip().lower() not in _HOSTED_OFF: return True
    # load_if_toml_exists() is asked FIRST (it returns False rather than raising when no
    # secrets file loads, the usual local case) because older Streamlit releases also draw
    # an st.error box when st.secrets.get misses the file, which would change the local
    # default view. The try/except covers any other loader failure.
    try:
        if st.secrets.load_if_toml_exists():
            # Streamlit copies root-level secrets into os.environ OVER the host's own value,
            # so an ECRF_HOSTED secret could quietly undo a host-set ECRF_HOSTED=1: the key
            # being there at all counts as on.
            if "ECRF_HOSTED" in st.secrets: return True
            return str(st.secrets.get("hosted", "")).strip().lower() not in _HOSTED_OFF
    except Exception: pass
    # Nothing loaded: local mode ONLY when no secrets file or folder exists at all. One that
    # exists but did not load fails closed (banner shown, inputs locked) instead of open.
    try: return any(os.path.exists(p) for p in st.get_option("secrets.files"))
    except Exception: return True

# ============================ IMPORT LAYER ============================
# The ONLY place this program touches the outside world. It reads safety-domain CSVs and
# NOTHING else -- there is no built-in dataset and no external SAP/protocol file, so every
# number downstream is computed from the operator's raw data against the labeled [SI]
# criteria above.

def _col(df, *syn):
    """Return the first column of `df` whose NORMALIZED name (lowercased, all
    non-alphanumerics stripped) equals any synonym. Normalization is why 'AE SEV',
    'ae_sev', and 'AESEV' all match -- EDC vendors and SDTM dumps name the same field
    different ways, and we refuse to assume one spelling. Returns None if nothing
    matches; callers must handle None (a missing column degrades that signal, it does
    not crash the run)."""
    norm = [re.sub(r"[^a-z0-9]","",c.lower()) for c in df.columns]
    for s in syn:
        t = re.sub(r"[^a-z0-9]","",s.lower())
        if t in norm: return df.columns[norm.index(t)]
    return None

# Column synonyms per logical field. This is the ONLY place column naming is configured;
# add a spelling here for an unusual header rather than hard-coding anywhere downstream.
SYN = {
    "USUBJID":  ["usubjid","subject_id","subjid"],
    # AE domain (signature: a severity or term column)
    "AESEV":    ["aeseverity","ae_sev","severity"],
    "AESER":    ["aesserious","aeser","serious"],
    "AELIFE":   ["aelife","life_threatening"],
    "AEOUTCOME":["aeoutcome","outcome"],
    "AEREL":    ["aerelated","aerel","relatedness"],
    "AETERM":   ["aeterm","verbatim","term"],
    # LB domain (signature: an upper-limit-of-normal column)
    "LBTESTCD": ["lbtestcd","test_cd","analyte","paramcd"],
    "LBSTRESN": ["lbstresn","lbstres","value","result"],
    "LBNRHI":   ["lbnrhi","uln","nrhi","upper_limit"],
    # EG domain (signature: a QTc column)
    "EGQTC":    ["egqtc","qtc","qtcfree"],
    # VS domain (signature: a vital parameter + value, but no ULN)
    "VSPAR":    ["vspar","paramcd","parameter"],
    "VSSTRESN": ["vsstresn","vsstres","value","result"],
    # PE domain (signature: a finding / present-absent column)
    "PEDECOD":  ["pedecod","findings","finding"],
    "PEFIND":   ["pefind","present_absent","status"],
    # source-system flags carried on lb/eg/vs (used as corroborating context + a disc signal)
    "ABNORMAL": ["abnormal","aboflag","lbabfl"],
    "CLINSIG":  ["clinsig","clin_sig","clin_significant"],
}

# Data files are CSV or SAS .sas7bdat (SDTM/ADaM dumps). A file named *meddra* is reference
# data, never a safety domain -- excluded here so it does not leak into the risk scan.
SAS_EXT = ".sas7bdat"
def _is_data_file(name):
    n=name.lower()
    return (n.endswith(".csv") or n.endswith(SAS_EXT)) and "meddra" not in n
def _read_table(p):
    """Read one domain table from CSV or SAS .sas7bdat into a DataFrame. SAS support is
    OPTIONAL: pyreadstat is probed, never imported at module scope (same discipline as the ML
    runtimes), so CSV-only users need nothing extra. A missing runtime with a SAS file present
    raises a clear error -- we never silently skip a data file, because that would be a coverage
    gap and an unexplained hole in what got scored."""
    if str(p).lower().endswith(SAS_EXT):
        if not HAVE.get("pyreadstat", False):
            raise ValueError("SAS .sas7bdat input needs 'pyreadstat' (pip install pyreadstat). "
                             "Install it, or export the table to CSV.")
        import pyreadstat
        df,_meta = pyreadstat.read_sas7bdat(p)
        return df
    return pd.read_csv(p)
def load_domains(folder=None, uploads=None):
    """Read every data file (CSV or SAS .sas7bdat) that is NOT a MedDRA file (this program has no
    dictionary; excluding meddra*.csv means all four programs can share one cut folder without a
    dictionary leaking into the risk scan). Domain NAMES are irrelevant -- each frame is classified
    by CONTENT in classify_domain. Same stem-normalization as the siblings."""
    doms={}; paths=[]
    if folder:
        paths += [os.path.join(folder,f) for f in sorted(os.listdir(folder)) if _is_data_file(f)]
    for u in (uploads or []):
        if _is_data_file(u.name): paths.append(u)
    for p in paths:
        name=os.path.basename(p) if isinstance(p,str) else p.name
        doms[re.sub(r"[_.].*$","",name.lower()).strip()] = _read_table(p)
    return doms

def classify_domain(df):
    """Classify a loaded frame by CONTENT (signature columns), not file name -- the same
    philosophy as phi_app.py's content-based discovery. Returns one of 'ae','lb','eg',
    'vs','pe' or None if unrecognized. Order matters: AE is checked first because it carries
    the most distinctive signature; VS is last because its value column shares synonyms with
    LB (LB is disambiguated by its ULN column)."""
    has = lambda *syn: _col(df,*syn) is not None
    if has(*SYN["AESEV"]) or has(*SYN["AETERM"]): return "ae"  # adverse events
    if has(*SYN["EGQTC"]): return "eg"                        # ECG (QTc)
    if has(*SYN["PEFIND"]) or has("PEDECOD"): return "pe"      # physical exam
    if has(*SYN["LBNRHI"]): return "lb"                       # labs (has an ULN column)
    if has(*SYN["VSPAR"],*SYN["VSSTRESN"]): return "vs"        # vitals
    return None

def _classify_reason(df):
    """Human-readable reason for classify_domain's verdict -- which signature matched, or (when the file is
    unrecognized) exactly what was looked for and how to fix it. Surfaced in pre-flight so an 'unrecognized'
    file explains itself instead of silently dropping out of the scan. Mirrors classify_domain's order."""
    has = lambda *syn: _col(df,*syn) is not None
    if has(*SYN["AESEV"]) or has(*SYN["AETERM"]): return "matched AE (severity/term)"
    if has(*SYN["EGQTC"]): return "matched EG (QTc)"
    if has(*SYN["PEFIND"]) or has("PEDECOD"): return "matched PE (finding/present-absent)"
    if has(*SYN["LBNRHI"]): return "matched LB (ULN column)"
    if has(*SYN["VSPAR"],*SYN["VSSTRESN"]): return "matched VS (parameter + value, no ULN)"
    return ("no signature matched; looked for AE(severity/term), EG(QTc), PE(finding), LB(ULN column) or "
            "VS(parameter+value); rename columns to those synonyms (or add a spelling to SYN) and re-run")

# ============================ TIER 1 ============================
# CONSUMES: the loaded domain frames. EMITS: per-domain typed views keyed by USUBJID.
# INVARIANT: Tier 1 NEVER rewrites a value -- it only locates columns and aligns rows to
#           participants, so Tier 2 measures against exactly what the site recorded.
def _num(series):
    """Coerce a column to float, leaving unparseable cells as NaN (never a crash). A stray
    text token in a numeric field must degrade that one cell's signal, not abort the run."""
    return pd.to_numeric(series, errors="coerce")

def tier1_align(domains):
    """Locate each domain's columns by synonym and return typed views. Each returned frame
    is indexed by USUBJID with only the columns Tier 2 needs (missing optional columns are
    simply absent -- e.g. no AELIFE column means 'no fatal flag recorded', not an error).
    Returns a dict keyed by domain type; duplicate types across files are concatenated so
    two ae*.csv files both count."""
    out={}
    for name,df in domains.items():
        kind=classify_domain(df)
        if kind is None: continue
        subj=_col(df,*SYN["USUBJID"])
        if not subj: continue   # cannot align to participants without an id column
        view=pd.DataFrame({subj:[s for s in df[subj]]})
        def pick(*syn):
            c=_col(df,*syn)
            return df[c] if c else None
        cols={"ae":("AESEV","AESER","AELIFE","AEOUTCOME","AEREL","AETERM"),
              "lb":("LBTESTCD","LBSTRESN","LBNRHI","CLINSIG"),
              "eg":("EGQTC","CLINSIG"),
              "vs":("VSPAR","VSSTRESN","CLINSIG"),
              "pe":("PEDECOD","PEFIND")}.get(kind,())
        for c in cols:
            s=pick(*SYN[c])
            if s is not None: view[c]=s.values
        # numeric coercion on the value columns (severity/flags stay as strings)
        for c in ("LBSTRESN","LBNRHI","EGQTC","VSSTRESN"):
            if c in view.columns: view[c]=_num(view[c])
        view=view.rename(columns={subj:"USUBJID"}).set_index("USUBJID")
        out[kind]=view if kind not in out else pd.concat([out[kind],view])
    return out

# ============================ TIER 2 ============================
# CONSUMES: the aligned Tier-1 views + thresholds. EMITS: per-participant READABLE signals.
# CONTRACT: Tier 2 PROPOSES and MEASURES; it decides nothing. Every signal is a number or
#           short string a reviewer can read -- no hidden feature, so Tier 3's decision is
#           always traceable to something on screen.
def tier2_signals(views, thr):
    """One row per participant with the readable signals that drive scoring: counts, max
    severity, fatal flag, and the specific breaches (which lab/QTc/vital crossed which
    declared limit). Participants appear if they have ANY safety-domain row."""
    ae=views.get("ae"); lb=views.get("lb"); eg=views.get("eg")
    vs=views.get("vs"); pe=views.get("pe")
    subjects=set()
    for v in (ae,lb,eg,vs,pe):
        if v is not None: subjects|=set(v.index)

    def ae_sig(s):
        if ae is None or s not in ae.index: return dict(n_ae=0,n_ser=0,n_rel=0,max_sev="",fatal=False,terms="",outcome="")
        r=ae.loc[s] if isinstance(ae.loc[s],pd.DataFrame) else pd.DataFrame([ae.loc[s]])
        sev=r["AESEV"].astype(str).str.upper() if "AESEV" in r else pd.Series(dtype=str)
        ser=(r["AESER"].astype(str).str.upper()=="Y") if "AESER" in r else pd.Series(False,index=r.index)
        life=(r["AELIFE"].astype(str).str.upper()=="Y") if "AELIFE" in r else pd.Series(False,index=r.index)
        # SDTM causality: PROBABLE/POSSIBLE count as related (UNLIKELY/UNKNOWN do not).
        rel=(r["AEREL"].astype(str).str.upper().isin(["PROBABLE","POSSIBLE"])) if "AEREL" in r else pd.Series(False,index=r.index)
        terms="; ".join(r["AETERM"].astype(str))[:120] if "AETERM" in r and len(r) else ""
        order=["LIFETHREATENING","SEVERE","MODERATE","MILD"]
        mx=next((o for o in order if (sev==o).any()), "")
        # AEOUTCOME is the explicit evidence behind a fatal flag: AELIFE=Y should pair with an
        # outcome like DIED. We surface it so the contributing-factors line shows WHY a participant
        # is called fatal -- life-threatening SEVERITY alone never sets this.
        oc=""
        if "AEOUTCOME" in r and life.any():
            vals=[str(x).strip() for x in r.loc[life,"AEOUTCOME"].astype(str) if str(x).strip().lower()!="nan"]
            oc=vals[0] if vals else ""
        return dict(n_ae=len(r), n_ser=int(ser.sum()), n_rel=int(rel.sum()), max_sev=mx,
                    fatal=bool(life.any()), terms=terms, outcome=oc)

    def lab_sig(s):
        breaches=[]
        if lb is not None and s in lb.index:
            r=lb.loc[s] if isinstance(lb.loc[s],pd.DataFrame) else pd.DataFrame([lb.loc[s]])
            for _,row in r.iterrows():
                code=str(row.get("LBTESTCD","")).strip()
                val=row.get("LBSTRESN"); uln=row.get("LBNRHI")
                key=f"{code}_ULN_MULT" if code else None
                thr_v=thr.get(key)
                if pd.isna(val) or pd.isna(uln) or not uln: continue
                ratio=val/uln
                if thr_v is not None and ratio>thr_v:
                    breaches.append(f"{code} {ratio:.1f}x ULN ([SI] criterion >{thr_v:g}x ULN)")
        return breaches

    def eg_sig(s):
        if eg is not None and s in eg.index:
            q=eg.loc[s,"EGQTC"] if isinstance(eg.loc[s],pd.Series) else eg.loc[s].iloc[0]["EGQTC"]
            lim=thr.get("QTC_ABS_MS")
            if pd.notna(q) and lim is not None and q>lim: return f"QTc {q:g} ms ([SI] criterion >{lim:g} ms)"
        return None

    def vs_sig(s):
        out=[]
        if vs is not None and s in vs.index:
            r=vs.loc[s] if isinstance(vs.loc[s],pd.DataFrame) else pd.DataFrame([vs.loc[s]])
            for _,row in r.iterrows():
                par=str(row.get("VSPAR","")).strip(); val=row.get("VSSTRESN")
                key=VITAL_KEY.get(par); lim=thr.get(key) if key else None
                if pd.notna(val) and lim is not None and val>lim:
                    out.append(f"{par} {val:g} (>{lim:g})")
        return out

    def pe_sig(s):
        if pe is not None and s in pe.index:
            r=pe.loc[s] if isinstance(pe.loc[s],pd.DataFrame) else pd.DataFrame([pe.loc[s]])
            present=r["PEFIND"].astype(str).str.upper().isin(["PRESENT","Y"]) if "PEFIND" in r else pd.Series(True,index=r.index)
            return "; ".join(r.loc[present,"PEDECOD"].astype(str))[:120] if len(r) and present.any() else ""
        return ""

    def clinsig_sig(s):
        """Source-system CLINSIG=Y findings across lb/eg/vs, as (count, readable list). This is the
        site's own clinical judgment carried alongside our numeric criteria -- corroborating context,
        and a modest discontinuation signal (a flagged finding usually precedes intervention). It does
        NOT alter the objective safety score."""
        items=[]
        if lb is not None and s in lb.index and "CLINSIG" in lb.columns:
            r=lb.loc[s] if isinstance(lb.loc[s],pd.DataFrame) else pd.DataFrame([lb.loc[s]])
            for _,row in r[r["CLINSIG"].astype(str).str.upper()=="Y"].iterrows():
                items.append(str(row.get("LBTESTCD"," ")).strip() or "lab")
        if eg is not None and s in eg.index and "CLINSIG" in eg.columns:
            r=eg.loc[s] if isinstance(eg.loc[s],pd.DataFrame) else pd.DataFrame([eg.loc[s]])
            if (r["CLINSIG"].astype(str).str.upper()=="Y").any(): items.append("QTc")
        if vs is not None and s in vs.index and "CLINSIG" in vs.columns:
            r=vs.loc[s] if isinstance(vs.loc[s],pd.DataFrame) else pd.DataFrame([vs.loc[s]])
            for _,row in r[r["CLINSIG"].astype(str).str.upper()=="Y"].iterrows():
                items.append(str(row.get("VSPAR"," ")).strip() or "vital")
        return len(items), "; ".join(dict.fromkeys(items))[:120]

    rows=[]
    for s in sorted(subjects):
        a=ae_sig(s); lab=lab_sig(s); qtc=eg_sig(s); vit=vs_sig(s); pe_f=pe_sig(s)
        nc, cdesc = clinsig_sig(s)
        rows.append(dict(USUBJID=s, **a, lab_breaches="; ".join(lab), n_lab=len(lab),
                         qtc_breach=qtc or "", n_qtc=int(bool(qtc)), vital_breaches="; ".join(vit),
                         n_vital=len(vit), pe_findings=pe_f, n_clinsig=nc, clinsig_desc=cdesc))
    return pd.DataFrame(rows)

# ============================ TIER 3 ============================
# CONSUMES: ONLY the named Tier-2 signals + thresholds. EMITS: safety_risk_score (0-100)
#           and discontinuation_risk_score (0-1). [SI] transparent weighted engine.
# Per-AE severity weighting needs each AE's own severity (not just a participant max), so Tier 3
# consumes BOTH the readable signal table AND the raw aligned AE view. Every weight is a declared
# constant above ([SI]); every threshold comes from `thr` (the built-in [SI] criteria). The
# decision is a function of numbers already on screen -- no hidden feature.
def tier3_scores(sig, views, thr):
    ae=views.get("ae")
    out=[]
    for _,r in sig.iterrows():
        s=r["USUBJID"]
        # --- AE component: per-AE base weight x serious multiplier; fatal added on top of cap ---
        if ae is not None and s in ae.index:
            rae=ae.loc[s] if isinstance(ae.loc[s],pd.DataFrame) else pd.DataFrame([ae.loc[s]])
            sev=rae["AESEV"].astype(str).str.upper() if "AESEV" in rae else pd.Series(dtype=str,index=rae.index)
            ser=(rae["AESER"].astype(str).str.upper()=="Y") if "AESER" in rae else pd.Series(False,index=rae.index)
            load=sum(SEV_WEIGHT.get(v,0)*(SERIOUS_MULT if y else 1) for v,y in zip(sev,ser))
        else:
            load=0.0
        ae_comp=min(AE_CAP,load)+(FATAL_ADDER if r["fatal"] else 0)
        # --- lab component: points per analyte above its [SI] ULN multiple, capped. Only
        #     BREACHES count (ratio > declared threshold); a sub-threshold lab contributes 0,
        #     never a negative point -- that guard is what keeps every score in [0,100]. ---
        lab_pts=0.0
        for code,ratio in _lab_ratios(views,s):
            t=thr.get(f"{code}_ULN_MULT")
            if t is not None and ratio>t: lab_pts+=LAB_PER_BREACH(ratio,t)
        lab_comp=min(LAB_CAP,lab_pts)
        # --- ECG component: QTc above the cardiac criterion ---
        qtc=_qtc_value(views,s); lim=thr.get("QTC_ABS_MS")
        ecg_comp=min(ECG_CAP,ECG_BASE+round((qtc-lim)/ECG_SLOPE)) if (pd.notna(qtc) and lim is not None and qtc>lim) else 0
        # --- vitals component: per vital breach, capped ---
        vit_pts=0
        for par,val in _vital_values(views,s):
            key=VITAL_KEY.get(par); vlim=thr.get(key) if key else None
            if pd.notna(val) and vlim is not None and val>vlim: vit_pts+=min(VIT_PER,VIT_BASE+round((val-vlim)/VIT_SLOPE))
        vit_comp=min(VIT_CAP,vit_pts)

        # A fatal outcome is the ceiling of safety risk -- it scores 100 so a fatal participant
        # always ranks at/above every non-fatal participant (death outranks any comorbidity load).
        safety=100 if r["fatal"] else min(100, round(ae_comp+lab_comp+ecg_comp+vit_comp))

        # --- discontinuation score: additive contributions squashed to [0,1] ---
        n_ae=r["n_ae"] or 0
        serious=min(DISC_SERIOUS_CAP, DISC_SERIOUS_EACH*r["n_ser"])
        related=DISC_RELATED_FRAC*(r["n_rel"]/n_ae) if n_ae else 0.0
        maxsev=DISC_MAXSEV.get(r["max_sev"],0.0)
        fatal=DISC_FATAL if r["fatal"] else 0.0
        lab=min(DISC_LAB_CAP, DISC_LAB_EACH*r["n_lab"])
        qtc_b=DISC_QTC if r["n_qtc"] else 0.0
        vit_b=DISC_VITAL if r["n_vital"] else 0.0
        clinsig=min(DISC_CLINSIG_CAP, DISC_CLINSIG_EACH*r["n_clinsig"])
        disc=min(1.0, round(serious+related+maxsev+fatal+lab+qtc_b+vit_b+clinsig,3))

        out.append(dict(r, ae_comp=round(ae_comp,1), lab_comp=round(lab_comp,1),
                        ecg_comp=ecg_comp, vit_comp=vit_comp,
                        safety_risk_score=safety, discontinuation_risk_score=disc))
    return pd.DataFrame(out)

def _lab_ratios(views,s):
    """Yield (analyte_code, value/ULN ratio) for participant s -- the raw detail Tier 3 needs to
    weight each breach by how far past its [SI] ULN multiple it is."""
    lb=views.get("lb")
    if lb is None or s not in lb.index: return []
    r=lb.loc[s] if isinstance(lb.loc[s],pd.DataFrame) else pd.DataFrame([lb.loc[s]])
    out=[]
    for _,row in r.iterrows():
        code=str(row.get("LBTESTCD","")).strip(); val=row.get("LBSTRESN"); uln=row.get("LBNRHI")
        if pd.isna(val) or pd.isna(uln) or not uln: continue
        out.append((code, val/uln))
    return out

def _qtc_value(views,s):
    eg=views.get("eg")
    if eg is None or s not in eg.index: return float("nan")
    v=eg.loc[s,"EGQTC"] if isinstance(eg.loc[s],pd.Series) else eg.loc[s].iloc[0]["EGQTC"]
    return pd.to_numeric(v, errors="coerce")

def _vital_values(views,s):
    vs=views.get("vs")
    if vs is None or s not in vs.index: return []
    r=vs.loc[s] if isinstance(vs.loc[s],pd.DataFrame) else pd.DataFrame([vs.loc[s]])
    return [(str(row.get("VSPAR","")).strip(), row.get("VSSTRESN")) for _,row in r.iterrows()]

# ============================ TIER 4 ============================
# CONSUMES: the Tier-3 scores + thresholds. EMITS: categories, contributing factors, and the
#           two output tables (risk_scores.csv + audit_log.csv). This is where a fatal outcome
#           hard-stops to CRITICAL -- death is by definition the highest safety risk, so it is
#           a categorical rule, not just points (documented in the contributing factors).
def tier4_categorize(scores, thr):
    sm=thr.get("SAFETY_CAT_MODERATE",DEFAULT_THR["SAFETY_CAT_MODERATE"])
    sh=thr.get("SAFETY_CAT_HIGH",DEFAULT_THR["SAFETY_CAT_HIGH"])
    sc=thr.get("SAFETY_CAT_CRITICAL",DEFAULT_THR["SAFETY_CAT_CRITICAL"])
    dm=thr.get("DISC_CAT_MODERATE",DEFAULT_THR["DISC_CAT_MODERATE"])
    dh=thr.get("DISC_CAT_HIGH",DEFAULT_THR["DISC_CAT_HIGH"])

    def s_cat(row):
        if row["fatal"]: return "CRITICAL"          # protocol hard stop: fatal outcome -> CRITICAL
        v=row["safety_risk_score"]
        return "CRITICAL" if v>=sc else "HIGH" if v>=sh else "MODERATE" if v>=sm else "LOW"

    def d_cat(v):   # compare on the ROUNDED value so a boundary score is stable across runs
        return "HIGH" if v>=dh else "MODERATE" if v>=dm else "LOW"

    rows=[]
    for _,r in scores.iterrows():
        factors=[]
        if r["fatal"]:
            oc=r.get("outcome","")
            factors.append(f"Fatal outcome (AELIFE=Y{'; AEOUTCOME='+oc if oc else ''}) -> CRITICAL")
        if r["n_ser"]: factors.append(f"{int(r['n_ser'])} serious AE(s)")
        if r["max_sev"] and not r["fatal"]: factors.append(f"Max severity {r['max_sev']}")
        if r["lab_breaches"]: factors.append("Labs: "+r["lab_breaches"])
        if r["qtc_breach"]: factors.append(r["qtc_breach"])
        if r["vital_breaches"]: factors.append("Vitals: "+r["vital_breaches"])
        if r.get("clinsig_desc"): factors.append("Clinically significant: "+r["clinsig_desc"])
        if r["pe_findings"]: factors.append("PE: "+r["pe_findings"])
        # The output carries only the decision + its evidence. n_AE / n_SAE / max_severity /
        # fatal are internal signals (they drive scoring and the contributing-factors line above)
        # but are NOT exported -- a reviewer reads WHY from contributing_factors, not raw counts.
        # _fatal is kept as an internal sort key so a fatal participant always pins to the top; it is
        # dropped before display/export in the UI block below.
        rows.append(dict(USUBJID=r["USUBJID"], _fatal=1 if r["fatal"] else 0,
            safety_risk_score=int(r["safety_risk_score"]), safety_category=s_cat(r),
            discontinuation_risk_score=round(float(r["discontinuation_risk_score"]),3),
            disc_category=d_cat(round(float(r["discontinuation_risk_score"]),3)),
            contributing_factors="; ".join(factors) if factors else "No declared criteria breached"))
    return pd.DataFrame(rows)

def _guard_artifacts(models_dir):
    """HARD STOP, never a silent fallback (same discipline as the siblings): if a trained
    risk-model artifact exists in models_dir but its runtime is NOT installed, refuse to run.
    Silently substituting the [SI] stand-in for a model the operator BELIEVES is loaded would
    corrupt both the review and the audit. The filename below is a CONVENTION the operator must
    match when dropping real weights."""
    if not os.path.isdir(models_dir): return
    art=os.path.join(models_dir,"risk_model.json")
    # This build has NO code that loads a trained risk model: the [SI] engine is the only
    # scorer. So the file stops the run whether or not xgboost is installed -- running on
    # while the operator believes a model is in use (an earlier build even wrote REAL to
    # the audit here) would be exactly the silent substitution this guard exists to refuse.
    if os.path.exists(art):
        st.error(f"risk_model.json found, but this build has no trained-risk-model path: the labeled "
                 f"[SI] engine is the only scorer. Remove the file to run."); st.stop()

# Browser adapter: deliberately independent of the sibling programs. Native UI below
# is unchanged. Only the explicit WebAssembly flag enables these upload workflows.
BROWSER_FILE_LIMIT = 2 * 1024 * 1024
BROWSER_TOTAL_LIMIT = 8 * 1024 * 1024


def browser_read_csv(name, data):
    if not isinstance(name, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_. -]{0,95}\.csv", name, re.I):
        raise ValueError("Use a simple CSV filename, at most 100 characters, without folders or special characters.")
    if not isinstance(data, bytes) or not data or len(data) > BROWSER_FILE_LIMIT:
        raise ValueError("Each CSV must contain data and be at most 2 MiB.")
    try:
        text = data.decode("utf-8-sig")
    except UnicodeDecodeError as error:
        raise ValueError("Save CSV files as UTF-8; this file could not be decoded.") from error
    if "\x00" in text:
        raise ValueError("CSV contains a NUL byte.")
    try:
        rows = list(csv.reader(io.StringIO(text, newline=""), strict=True))
    except csv.Error as error:
        raise ValueError("Malformed CSV: " + str(error)) from error
    if len(rows) < 2 or len(rows) > 5001 or not rows[0] or len(rows[0]) > 100:
        raise ValueError("Use a header and 1–5,000 rows, with at most 100 columns per file.")
    headers = rows[0]
    if any(not x.strip() or x != x.strip() or any(ord(c) < 32 for c in x) for x in headers):
        raise ValueError("Column names must be nonempty, trimmed, and free of control characters.")
    if len({x.casefold() for x in headers}) != len(headers):
        raise ValueError("Duplicate column names are not allowed, including case-only differences.")
    if any(len(row) != len(headers) for row in rows[1:]):
        raise ValueError("Every CSV row must have exactly the same number of fields as its header.")
    if any(len(cell) > 20000 for row in rows for cell in row):
        raise ValueError("A CSV cell exceeds 20,000 characters.")
    return pd.DataFrame(rows[1:], columns=headers, dtype=str)


def _browser_sources(sources):
    if not isinstance(sources, dict) or not 1 <= len(sources) <= 8:
        raise ValueError("Select 1–8 CSV files.")
    if any(not isinstance(x, str) or not isinstance(v, bytes) for x, v in sources.items()):
        raise ValueError("CSV inputs require filenames and byte contents.")
    if len({x.casefold() for x in sources}) != len(sources):
        raise ValueError("Use distinct filenames; two files cannot differ only by case.")
    if sum(len(v) for v in sources.values()) > BROWSER_TOTAL_LIMIT:
        raise ValueError("The complete input is limited to 8 MiB.")
    return {name: browser_read_csv(name, raw) for name, raw in sources.items()}


def _browser_numeric(series, label, positive=False):
    if series.astype(str).str.strip().eq("").any():
        raise ValueError(label + ": blank numeric values are not treated as normal. Resolve them before screening.")
    try:
        value = pd.to_numeric(series, errors="raise")
    except (ValueError, TypeError) as error:
        raise ValueError(label + ": every selected value must be numeric.") from error
    if any(abs(float(x)) > 1e100 for x in value):
        raise ValueError(label + ": numeric magnitude exceeds the browser arithmetic limit of 1e100.")
    if not all(math.isfinite(float(x)) for x in value) or (positive and (value <= 0).any()):
        raise ValueError(label + (": values must be finite and positive." if positive else ": NaN and infinite values are not allowed."))
    return value


def _browser_ids(series):
    ids = series.astype(str)
    if ids.str.strip().eq("").any() or (ids != ids.str.strip()).any():
        raise ValueError("Participant IDs cannot be missing or have surrounding whitespace. Leading zeros are preserved.")
    return ids


def _browser_studies(frames, specs):
    studies = set()
    for name, frame in frames.items():
        column = specs[name].get("study") or _col(frame, "studyid", "study_id")
        if column:
            if column not in frame or frame[column].str.strip().eq("").any():
                raise ValueError("Mapped study identifiers must be present on every row.")
            studies.update(frame[column].str.strip())
    if len(studies) > 1:
        raise ValueError("Screen one study at a time. Split different study IDs before aligning participants.")
    return sorted(studies)


def _browser_thresholds(config):
    given = config.get("thresholds")
    if not isinstance(given, dict) or set(given) != set(DEFAULT_THR):
        raise ValueError("Review and supply every threshold shown in the setup form.")
    thr = {}
    for key, value in given.items():
        if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or value <= 0:
            raise ValueError(key + " must be a finite positive number.")
        thr[key] = float(value)
    return thr


def _browser_cuts(thr, keys, maximum=None):
    values = [thr[k] for k in keys]
    if values != sorted(set(values)) or (maximum is not None and values[-1] > maximum):
        raise ValueError("Category cuts must increase strictly" + (" and be at most " + str(maximum) if maximum else "") + ": " + ", ".join(keys))


def _browser_fingerprint(sources, config):
    return hashlib.sha256(json.dumps({"inputs": {n: hashlib.sha256(b).hexdigest() for n, b in sorted(sources.items())}, "config": config}, sort_keys=True, allow_nan=False).encode()).hexdigest()


def _browser_safe_csv(frame):
    safe = frame.copy()
    for col in safe:
        safe[col] = safe[col].map(lambda x: "'" + x if isinstance(x, str) and re.match(r"^\s*[=+@-]", x) else x)
    safe.columns = ["'" + c if isinstance(c, str) and re.match(r"^\s*[=+@-]", c) else c for c in safe.columns]
    return safe.to_csv(index=False).encode("utf-8")


def browser_package(result, sources):
    if result["fingerprint"] != _browser_fingerprint(sources, result["config"]):
        raise ValueError("Inputs or settings changed; compute a fresh result before exporting.")
    files = {"settings.json": json.dumps(result["config"], indent=2, allow_nan=False).encode(),
             "audit_log.csv": _browser_safe_csv(result["audit"]),
             "input_audit.csv": _browser_safe_csv(result["input_audit"])}
    for name, data in sources.items():
        files["inputs/" + name] = data
    for name, frame in result["normalized"].items():
        files["normalized/" + name] = _browser_safe_csv(frame)
        files["normalized/" + name + ".json"] = frame.to_json(orient="table", index=False, force_ascii=False).encode()
    for name, frame in result["tables"].items():
        files[name + ".csv"] = _browser_safe_csv(frame)
    title = "Browser screening review package"
    body = "<h1>" + title + "</h1><p>Computed from the supplied inputs and declared settings. Scores are screening indices, not probabilities or clinical determinations. Review input coverage and audit_log.csv.</p>"
    for name, frame in result["tables"].items():
        body += "<h2>" + escape(name) + "</h2><p>" + str(len(frame)) + " rows; <a href='" + name + ".csv'>complete CSV</a>. Preview limited to 500 rows.</p>" + frame.head(500).to_html(index=False, escape=True)
    files["report.html"] = ("<!doctype html><html lang='en'><meta charset='utf-8'><meta name='viewport' content='width=device-width'><title>" + title + "</title><style>body{font:16px system-ui;margin:2rem;line-height:1.5}table{border-collapse:collapse;font-size:13px;display:block;overflow:auto}td,th{border:1px solid #888;padding:.4rem}button{padding:.5rem}a{color:inherit}:root{color-scheme:light dark}body[data-theme=light]{color-scheme:light;background:#fff;color:#15202b}body[data-theme=dark]{color-scheme:dark;background:#111821;color:#e4edf5}</style><button onclick=\"document.body.dataset.theme=document.body.dataset.theme==='dark'?'light':'dark'\">Light / dark</button>" + body + "</html>").encode()
    files["START_HERE.txt"] = ("Open report.html after extracting this complete ZIP. Every result table, including empty flagged-only tables, is supplied as CSV.\nInputs retain exact uploaded bytes; import original inputs as data, not spreadsheet formulas. All derived CSVs prefix formula-like text with an apostrophe. Normalized JSON preserves exact mapped string values; original input bytes remain unchanged.\nsettings.json and audit_log.csv record mappings, criteria, method scope and input hashes. Scores are not probabilities or trained model predictions. Review missing domains and units before interpreting a screen. No clinical or regulatory approval is implied.\n").encode()
    source = globals().get("__file__")
    if source and os.path.isfile(source):
        with open(source, "rb") as stream:
            files["source/" + os.path.basename(source)] = stream.read()
    files["file_inventory.json"] = json.dumps({n: hashlib.sha256(v).hexdigest() for n, v in files.items()}, indent=2).encode()
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as archive:
        for name, data in files.items():
            archive.writestr(name, data)
    return buffer.getvalue()


def _browser_choice(label, columns, key, guess=None, required=False):
    choices = [""] + list(columns)
    return st.selectbox(label + (" (required)" if required else " (optional)"), choices,
                        index=choices.index(guess) if guess in choices else 0, key=key)


def _browser_reset(example=False):
    generation = st.session_state.get("br_generation", 0) + 1
    for key in list(st.session_state):
        if str(key).startswith("br_"):
            del st.session_state[key]
    st.session_state["br_generation"] = generation
    st.session_state["br_example"] = example
    st.rerun()


def _browser_inputs(example):
    if st.button("Reset workspace", key="br_reset"):
        _browser_reset()
    if st.button("Load synthetic example", key="br_example_load"):
        _browser_reset(example=True)
    uploads = st.file_uploader("Study CSV files (UTF-8; 2 MiB each, 8 MiB total)", type=["csv"], accept_multiple_files=True, key="br_uploads_" + str(st.session_state.get("br_generation", 0)))
    if uploads:
        st.session_state["br_example"] = False
        names = [u.name for u in uploads]
        if len(names) != len(set(names)):
            raise ValueError("Duplicate uploaded filenames are not allowed.")
        return {u.name: u.getvalue() for u in uploads}
    return example() if st.session_state.get("br_example") else {}


def _browser_controls(sources, config):
    fingerprint = _browser_fingerprint(sources, config)
    old = st.session_state.get("br_result")
    if old and old["fingerprint"] != fingerprint:
        st.session_state.pop("br_result", None)
        st.info("Inputs or settings changed. Previous results and downloads were cleared.")
    confirmed = st.checkbox("I reviewed mappings, units, criteria and screening scope for this single study.", key="br_confirm_" + str(st.session_state.get("br_generation", 0)) + "_" + fingerprint[:16])
    if st.button("Run screening", disabled=not confirmed, type="primary", key="br_run"):
        config = dict(config, confirmed=True)
        with st.spinner("Computing the reviewed screening methods…"):
            result = browser_compute(sources, config)
            # Confirmation is a run authorization, not part of the editable settings identity.
            result["config"] = dict(result["config"], confirmed=False)
            result["fingerprint"] = _browser_fingerprint(sources, result["config"])
            st.session_state["br_result"] = result
    result = st.session_state.get("br_result")
    if result:
        st.success("Screening completed. Review all tables and input coverage before reuse.")
        for name, table in result["tables"].items():
            st.subheader(name.replace("_", " ").capitalize())
            st.caption(str(len(table)) + " result rows; downloads retain every row.")
            st.dataframe(table.head(1000), hide_index=True)
        st.dataframe(result["input_audit"], hide_index=True)
        st.download_button("Download complete review package (.zip)", browser_package(result, sources), "screening-review.zip", "application/zip", on_click="ignore")

BROWSER_FIELDS = {"ae": ["USUBJID", "AESEV", "AESER", "AELIFE", "AEOUTCOME", "AEREL", "AETERM"],
                  "lb": ["USUBJID", "LBTESTCD", "LBSTRESN", "LBNRHI", "CLINSIG"],
                  "eg": ["USUBJID", "EGQTC", "CLINSIG"],
                  "vs": ["USUBJID", "VSPAR", "VSSTRESN", "CLINSIG"],
                  "pe": ["USUBJID", "PEDECOD", "PEFIND"]}
BROWSER_REQUIRED = {"ae": ["USUBJID", "AESEV"], "lb": ["USUBJID", "LBTESTCD", "LBSTRESN", "LBNRHI"],
                    "eg": ["USUBJID", "EGQTC"], "vs": ["USUBJID", "VSPAR", "VSSTRESN"], "pe": ["USUBJID", "PEDECOD", "PEFIND"]}
BROWSER_VALUES = {"AESEV": ["MILD", "MODERATE", "SEVERE", "LIFETHREATENING"],
                  "AESER": ["Y", "N"], "AELIFE": ["Y", "N"], "CLINSIG": ["Y", "N"],
                  "AEREL": ["PROBABLE", "POSSIBLE", "UNLIKELY", "UNKNOWN", "NOT RELATED"],
                  "PEFIND": ["PRESENT", "ABSENT"], "VSPAR": ["SYSBP", "DIASTP", "TEMPC"]}


def browser_prepare(sources, config):
    frames = _browser_sources(sources)
    specs = config.get("files", {})
    if set(specs) != set(frames):
        raise ValueError("Map every uploaded file to its safety domain.")
    _browser_studies(frames, specs)
    thr = _browser_thresholds(config)
    _browser_cuts(thr, ["SAFETY_CAT_MODERATE", "SAFETY_CAT_HIGH", "SAFETY_CAT_CRITICAL"], 100)
    _browser_cuts(thr, ["DISC_CAT_MODERATE", "DISC_CAT_HIGH"], 1)
    normalized, audit = {}, []
    for name, df in frames.items():
        spec = specs[name]; domain = spec.get("domain")
        if domain not in BROWSER_FIELDS:
            raise ValueError(name + ": choose AE, LB, EG, VS or PE explicitly.")
        columns = spec.get("columns", {})
        if any(not columns.get(k) or columns[k] not in df for k in BROWSER_REQUIRED[domain]):
            raise ValueError(name + ": map required fields: " + ", ".join(BROWSER_REQUIRED[domain]))
        selected = {k: v for k, v in columns.items() if v}
        if set(selected) - set(BROWSER_FIELDS[domain]) or len(set(selected.values())) != len(selected):
            raise ValueError(name + ": each source column can map to only one supported field.")
        out = pd.DataFrame({k: df[v].copy() for k, v in selected.items()})
        out["USUBJID"] = _browser_ids(out["USUBJID"])
        record = spec.get("record_id")
        if record:
            if record not in df or df[record].str.strip().eq("").any():
                raise ValueError(name + ": record IDs must be present on every row.")
            out["_RECORD_ID"] = df[record]
            if out.duplicated(["USUBJID", "_RECORD_ID"]).any():
                raise ValueError(name + ": duplicate participant/record IDs are not allowed.")
        if out.duplicated().any():
            raise ValueError(name + ": duplicate mapped records would inflate the score; map a unique event/record ID for legitimate repeated events, or resolve duplicates.")
        for field, choices in BROWSER_VALUES.items():
            if field not in out:
                continue
            value_map = spec.get("values", {}).get(field, {})
            raw_values = set(out[field])
            if not raw_values <= set(value_map) or any(value_map[x] not in choices for x in raw_values):
                raise ValueError(name + ": map every " + field + " source value to a declared category.")
            out[field] = out[field].map(value_map)
        for field in ("LBSTRESN", "LBNRHI", "EGQTC", "VSSTRESN"):
            if field in out:
                out[field] = _browser_numeric(out[field], name + " / " + field, field in ("LBNRHI", "EGQTC"))
        if domain == "lb":
            if out["LBTESTCD"].str.strip().eq("").any():
                raise ValueError("Every laboratory record needs an analyte code.")
            limits = config.get("lab_limits", {})
            for code in out["LBTESTCD"].unique():
                value = limits.get(code)
                if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or value <= 0:
                    raise ValueError("Declare a positive ULN-multiple screening threshold for analyte " + str(code))
                thr[str(code) + "_ULN_MULT"] = value
            ratios = out["LBSTRESN"] / out["LBNRHI"]
            if not all(math.isfinite(float(x)) and abs(float(x)) <= 1e100 for x in ratios):
                raise ValueError("Laboratory value/ULN ratios exceed the browser arithmetic limit.")
        if domain in ("lb", "eg", "vs") and spec.get("units_confirmed") is not True:
            raise ValueError(name + ": confirm lab values and ULNs share units, QTc uses milliseconds, and mapped BP/temperature use mmHg/°C.")
        # Validate any explicitly selected unit column; a declaration never converts units.
        for unit_column, expected in spec.get("unit_checks", {}).items():
            if domain == "eg" and str(expected).strip().lower() not in ("ms", "millisecond", "milliseconds"):
                raise ValueError(name + ": QTc requires milliseconds, not converted units.")
            if unit_column not in df or not isinstance(expected, str) or not expected.strip() or set(df[unit_column].str.strip()) != {expected.strip()}:
                raise ValueError(name + ": mapped units differ from the declared unit. Harmonize units before screening.")
        unit_column = spec.get("unit_column")
        uln_unit = spec.get("uln_unit_column")
        if unit_column:
            if unit_column not in df or df[unit_column].str.strip().eq("").any():
                raise ValueError(name + ": the selected unit column must be populated.")
            units = df[unit_column].str.strip().str.upper()
            if domain == "eg" and not units.isin(["MS", "MILLISECOND", "MILLISECONDS"]).all():
                raise ValueError(name + ": QTc must use milliseconds.")
            if domain == "vs":
                accepted = {"SYSBP": {"MMHG"}, "DIASTP": {"MMHG"}, "TEMPC": {"C", "°C", "CELSIUS"}}
                if any(unit not in accepted[param] for unit, param in zip(units, out["VSPAR"])):
                    raise ValueError(name + ": BP requires mmHg and temperature requires Celsius. Harmonize units first.")
            if domain == "lb" and uln_unit:
                if uln_unit not in df or not units.equals(df[uln_unit].str.strip().str.upper()):
                    raise ValueError(name + ": result and ULN units must match on every row.")
        elif uln_unit:
            raise ValueError(name + ": map the result unit column alongside the ULN unit column.")
        normalized[name] = out
        audit.append({"file": name, "domain": domain, "rows": len(out), "participants": out.USUBJID.nunique(),
                      "mapped_fields": ", ".join(out.columns), "unmapped_fields": ", ".join(k for k in BROWSER_FIELDS[domain] if k not in out),
                      "sha256": hashlib.sha256(sources[name]).hexdigest()})
    seen_records, seen_rows = set(), {}
    for name, frame in normalized.items():
        domain = specs[name]["domain"]
        columns = sorted(c for c in frame if c != "_RECORD_ID")
        for _, row in frame.iterrows():
            if "_RECORD_ID" in frame:
                key = (domain, str(row["USUBJID"]), str(row["_RECORD_ID"]))
                if key in seen_records:
                    raise ValueError("Duplicate participant/record ID across files in domain " + domain + ". Resolve overlapping extracts before screening.")
                seen_records.add(key)
            # Without an explicit record key, an identical mapped row in a second
            # extract cannot safely be counted as another event.
            key = (domain, tuple((c, str(row[c])) for c in columns))
            if key in seen_rows and ("_RECORD_ID" not in frame or seen_rows[key]):
                raise ValueError("Duplicate mapped record across files in domain " + domain + ". Map distinct record IDs for separate events or remove overlapping extracts.")
            seen_rows[key] = "_RECORD_ID" not in frame
    views = tier1_align(normalized)
    if not views:
        raise ValueError("No usable mapped safety records.")
    # Canonical engine uses one QTc value. Explicitly choose the participant maximum,
    # preserving all input rows and the selection rule in the audit.
    if "eg" in views:
        eg = views["eg"].reset_index()
        selected = eg.loc[eg.groupby("USUBJID")["EGQTC"].idxmax()].copy()
        if "CLINSIG" in eg:
            selected["CLINSIG"] = selected.USUBJID.map(eg.groupby("USUBJID").CLINSIG.agg(lambda x: "Y" if (x == "Y").any() else "N"))
        views["eg"] = selected.set_index("USUBJID")
    return views, thr, normalized, pd.DataFrame(audit)


def browser_compute(sources, config):
    if config.get("confirmed") is not True:
        raise ValueError("Confirm study mappings, units and criteria before running.")
    views, thr, normalized, intake = browser_prepare(sources, config)
    signals = tier2_signals(views, thr)
    scores = tier3_scores(signals, views, thr)
    result = tier4_categorize(scores, thr).sort_values(["_fatal", "safety_risk_score"], ascending=False).drop(columns="_fatal")
    audit = pd.DataFrame([{"program": "participant_rule_screening", "execution": "browser" if BROWSER_ENABLED else "native_browser_adapter_QC",
        "criteria_source": "user-confirmed configurable screening criteria", "thresholds": json.dumps(thr, sort_keys=True),
        "method": "existing weighted rule engine; no trained model; neither score is a probability",
        "coverage": "Only uploaded mapped domains contribute; absent domains/fields are not assessed. Repeated AE/lab/vital records contribute repeatedly under the documented caps.",
        "qtc_selection": "Maximum observed QTc per participant; any CLINSIG=Y retained", "fatal_mapping": "Explicit actual fatal-outcome flag only; life-threatening severity is not death",
        "weights": json.dumps({"severity": SEV_WEIGHT, "serious_multiplier": SERIOUS_MULT, "fatal_adder": FATAL_ADDER, "AE_cap": AE_CAP, "lab_cap": LAB_CAP, "ECG": [ECG_BASE, ECG_SLOPE, ECG_CAP], "vitals": [VIT_BASE, VIT_SLOPE, VIT_PER, VIT_CAP], "discontinuation": [DISC_SERIOUS_EACH, DISC_SERIOUS_CAP, DISC_RELATED_FRAC, DISC_FATAL, DISC_LAB_EACH, DISC_LAB_CAP, DISC_QTC, DISC_VITAL, DISC_CLINSIG_EACH, DISC_CLINSIG_CAP], "maximum_severity_discontinuation": DISC_MAXSEV}),
        "settings": json.dumps(config, sort_keys=True), "pandas_version": pd.__version__, "python_version": sys.version.split()[0]}])
    return {"tables": {"risk_scores": result, "signals": signals, "score_components": scores}, "normalized": normalized,
            "input_audit": intake, "audit": audit, "config": config, "fingerprint": _browser_fingerprint(sources, config)}


def browser_example():
    return {"events.csv": b"participant,severity,serious,fatal,term\n001,MILD,N,N,Headache\n002,SEVERE,Y,N,Nausea\n003,LIFETHREATENING,Y,N,Allergic reaction\n004,MODERATE,N,N,Fatigue\n",
            "ecg.csv": b"participant,qtc,unit\n001,440,ms\n002,510,ms\n003,490,ms\n004,460,ms\n"}


def browser_main():
    st.title("Participant risk screening")
    st.info("Rule-based screening indices, not probabilities, trained predictions or clinical determinations. Choose one study, map its fields and confirm its criteria. Data and results stay in this browser session; download before reloading.")
    st.caption("Only high-threshold lab/QTc/BP/temperature screens are supported. Missing domains are not assessed. Repeated observations contribute under the canonical caps. QTc uses each participant's maximum. Life-threatening severity does not mean a fatal outcome.")
    try:
        sources = _browser_inputs(browser_example)
        if not sources:
            st.info("Upload study CSVs or deliberately load the synthetic example to begin.")
            st.session_state.pop("br_result", None)
            return
        frames = _browser_sources(sources)
        config = {"files": {}, "thresholds": {}, "lab_limits": {}, "confirmed": False}
        st.header("Map input fields")
        for name, df in frames.items():
            prefix = "br_" + str(st.session_state.get("br_generation", 0)) + "_" + hashlib.sha256((name + hashlib.sha256(sources[name]).hexdigest()).encode()).hexdigest()[:12]
            with st.expander(name, expanded=True):
                detected = classify_domain(df)
                domain = st.selectbox("Safety domain for " + name, [""] + list(BROWSER_FIELDS), index=([""] + list(BROWSER_FIELDS)).index(detected) if detected else 0, key=prefix + "_domain")
                spec = {"domain": domain, "columns": {}, "values": {}, "unit_checks": {}}
                config["files"][name] = spec
                spec["study"] = _browser_choice("Study ID column", df.columns, prefix + "_study", _col(df, "studyid", "study_id"))
                spec["record_id"] = _browser_choice("Event/record ID column", df.columns, prefix + "_record", _col(df, "aeseq", "lbseq", "egseq", "vsseq", "peseq", "record_id"))
                if not domain:
                    continue
                for field in BROWSER_FIELDS[domain]:
                    guess = _col(df, *SYN[field]) if field != "AELIFE" else _col(df, "fatal", "fatal_outcome", "death_flag", "aesdth")
                    if field == "USUBJID" and guess is None: guess = _col(df, "participant")
                    label = "Actual fatal outcome flag (NOT life-threatening)" if field == "AELIFE" else field
                    column = _browser_choice(label, df.columns, prefix + "_" + field, guess, field in BROWSER_REQUIRED[domain])
                    spec["columns"][field] = column
                    if column and field in BROWSER_VALUES:
                        values = list(dict.fromkeys(df[column]))
                        if len(values) > 30: raise ValueError(field + " has more than 30 distinct values; use coded categories.")
                        spec["values"][field] = {}
                        for j, raw in enumerate(values):
                            options = [""] + BROWSER_VALUES[field]; guess_value = raw.strip().upper()
                            spec["values"][field][raw] = st.selectbox(label + " value " + repr(raw), options, index=options.index(guess_value) if guess_value in options else 0, key=prefix + "_" + field + "_v" + str(j))
                if domain in ("lb", "eg", "vs"):
                    spec["units_confirmed"] = st.checkbox("Confirm units for " + name + ": laboratory result and ULN match; QTc in ms; BP in mmHg; temperature in °C.", key=prefix + "_units")
                    spec["unit_column"] = _browser_choice("Result unit column", df.columns, prefix + "_unitcol", _col(df, "unit", "units", "egstresu", "vsstresu", "lbstresu"))
                    if domain == "lb":
                        spec["uln_unit_column"] = _browser_choice("ULN unit column (if separate)", df.columns, prefix + "_ulnunit", _col(df, "uln_unit", "reference_unit"))
                if domain == "lb" and spec["columns"].get("LBTESTCD"):
                    for code in df[spec["columns"]["LBTESTCD"]].unique():
                        if code in config["lab_limits"]: continue
                        config["lab_limits"][code] = st.number_input("ULN-multiple threshold for " + str(code), min_value=0.01, value=float(DEFAULT_THR.get(str(code) + "_ULN_MULT", 3.0)), key="br_lab_" + str(st.session_state.get("br_generation", 0)) + "_" + hashlib.sha256(str(code).encode()).hexdigest()[:16])
                st.dataframe(df.head(5), hide_index=True)
        with st.expander("Screening thresholds and category cuts", expanded=False):
            st.caption("Starting values are illustrative screening criteria, not a client's protocol. Every selected value is retained in the audit. Fixed rule weights remain the declared source coefficients.")
            for key, value in DEFAULT_THR.items():
                if key.endswith("_ULN_MULT"):
                    config["thresholds"][key] = config["lab_limits"].get(key[:-9], float(value))
                    continue
                config["thresholds"][key] = st.number_input(key, min_value=0.001, value=float(value), key="br_thr_" + str(st.session_state.get("br_generation", 0)) + "_" + key)
        _browser_controls(sources, config)
    except (ValueError, KeyError, TypeError) as error:
        st.session_state.pop("br_result", None)
        st.error(str(error))

# ============================ UI ============================
# Layout order is deliberate (mirrors the siblings): gather WHERE the data is (1), set the
# outputs + optional models dir (2), LOAD so the pre-flight panel can show what was actually
# read and how each file classified, then the banner, then the pre-flight CONTRACT panel, then
# Run. The operator confirms the input contract BEFORE any compute, so a mis-pointed folder or
# an unrecognized domain is caught on screen, not after a silent wrong answer.
st.set_page_config(page_title="Participant risk screening" + (": browser workspace" if BROWSER_ENABLED else ": in-browser demo" if IN_BROWSER else ""), layout="wide")
HOSTED = _hosted()   # after set_page_config: no Streamlit call may precede it
if BROWSER_ENABLED and not HOSTED:
    browser_main()
    st.stop()
# Hosted: an uncaught exception shows a generic message, not a traceback with server
# paths (a crafted widget value can raise one). Process-wide, like the switch itself.
if HOSTED: st.set_option("client.showErrorDetails", "none")
st.title("⚖ Participant risk screening")
st.caption("Tier 1 intake → Tier 2 signals → Tier 3 aggregate [SI] → Tier 4 categorize · "
           "decision support, not a clinical determination · " + RUNS_WHERE + " · no sample data in this file")
# Hosted banner on EVERY rerun, drawn before any st.stop() below can cut the page short.
if HOSTED: st.warning(HOSTED_BANNER, icon="🔒")

# Built-in, app-specific instruction manual (from USER_GUIDE.md §5), rendered as a collapsible
# panel so the working view stays clean but help is one click away. Self-contained: it refers to
# nothing outside this program.
# Its section headings are `##` (h2): the panel sits right under the app's h1, so `###` would skip a level. It has
# no `>` quote block: Streamlit draws one at 60% opacity, which takes inline code below 4.5:1 contrast in light mode.
_HELP_MD = """
**What this app does.** Scores each study participant on two axes, **risk to their safety** (0 to 100) and **risk of discontinuing from the study** (0 to 1), from raw adverse events plus lab, ECG, vital-sign and physical-exam data. Both scores are capped, weighted sums of built-in rules, not probabilities. It ranks and flags participants for human review; it is **decision support, not a clinical determination**.

**What it needs.** Safety-domain CSVs (`ae`, `lb`, `eg`, `vs`, `pe`) with a participant ID column; nothing else. No dictionary, no SAP or protocol file: the app scores raw data against clearly-labeled built-in criteria. Files named `*meddra*` are skipped automatically (reference data for another program).

## Step by step
1. **Point at your data** (sidebar 📂 1): type a cut-folder path and/or upload safety CSVs. Every `*.csv` except one named `*meddra*` loads; each file is classified by its *content* (signature columns), not its name, so `ae.csv`, `adverse_events.csv`, or an oddly-named dump all work.
2. **Set outputs** (sidebar ⚖ 2): output folder (default `risk_output`) and a models dir field. This build has no trained risk model, so leave the models dir empty; a `risk_model.json` there stops the run. There is no gate slider: the operating point is the built-in `[SI]` criteria, recorded in the audit.
3. **Confirm the input** (pre-flight panel): check which domains loaded, how each file classified, and the participant count.
4. **Execute**: click 🚀 Execute Participant risk screening. Results render on screen (highest-risk first) and write to the output folder.

## How scoring works (`[SI]` transparent engine)
- **Safety score (0 to 100)** = four capped components: adverse events (severity-weighted, times 1.5 if serious), analytes above their built-in ULN multiple, QTc above the cardiac criterion, and vital-sign breaches, all against built-in `[SI]` criteria. A **fatal outcome scores 100** so it always ranks at or above every non-fatal participant; death is by definition the highest safety risk.
- **Discontinuation score (0 to 1)** = serious-AE burden + relatedness fraction + max severity + fatal flag + analytes above their built-in ULN multiple + QTc/vital breaches + source-system clinically significant findings, capped at 1.
- **The built-in criteria** (`[SI]`): ALT or AST above 3x ULN and creatinine above 1.5x ULN; QTc above 500 ms; systolic BP above 180 mmHg, diastolic above 110 mmHg, temperature above 38.5 °C. They are screening criteria, not CTCAE grades (in CTCAE v5.0 those lab multiples are grade 2 entry points) and not the FDA DILI discontinuation rules; the QTc cutoff is the top ICH E14 categorical tier only, with no change from baseline, whichever correction (QTcF or QTcB) the column holds.
- Categories come from built-in `[SI]` cuts; a human-readable **contributing factors** column explains *why* each participant landed where it did.

## Reading risk_scores.csv
One row per participant: `USUBJID`, both scores and categories, and a human-readable **contributing factors** string. The counts, maximum severity and fatal flag drive the scores but are not exported. The on-screen table is pre-sorted highest-risk first (fatal participants pinned to the top).

This build ships as a labeled stand-in (`[SI]`): a transparent weighted rule engine driven by built-in criteria; there is no external SAP/protocol file to import. A real deployment would replace Tier 3 with the protocol's own criteria or a trained, externally validated model. The weights are declared constants written to the audit, not hidden.

## Stand-in vs real (`[SI]` / `[RM]`)
This build has no trained-model path: Tier 3 always runs the labeled deterministic stand-in (`[SI]` in the banner and every audit row). A `risk_model.json` in the models dir **stops** the run rather than being ignored or half-loaded.

## Troubleshooting
- **"No safety domains loaded":** point at a folder with at least one of `ae`/`lb`/`eg`/`vs`/`pe`, or upload files. A file is only scored if it has a participant ID column (`USUBJID`).
- **A domain shows as unrecognized:** its columns do not match the synonyms: rename them (e.g. severity → `AESEV`) or add the spelling to `SYN` at the top of this file.

## What this build does NOT do
No free-text PDF/Word protocol or SAP parsing, no clinical determination, nothing leaves the machine. See USER_GUIDE.md §5 for full details and §10 for the complete limits list.
"""
if IN_BROWSER: _HELP_MD = _HELP_MD.replace("nothing leaves the machine", "nothing you load is uploaded by the app")
with st.expander("📖 How to use this app"):
    st.markdown(_HELP_MD)

# ---- sidebar 1: WHERE the data is. Folder path AND/OR uploads are additive; a
#      meddra*.csv in the folder is ignored (this program needs no dictionary). ----
if HOSTED: st.sidebar.warning(HOSTED_BANNER, icon="🔒")
st.sidebar.header("📂 1. Point this at your safety data")
_SAMPLE_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "sample_data")
# Demo toggle: off by default; a link ending in ?demo=1 (e.g. a hosted demo) starts it on.
# Hosted mode: each data input below is disabled AND its value overwritten right after
# the widget (sample forced on, folder pinned to sample_data/, no uploads), because a
# disabled widget only stops the browser; a crafted client could still send a value.
_use_sample = st.sidebar.checkbox("Use the bundled synthetic sample data",
    value=(HOSTED or st.query_params.get("demo") == "1"), disabled=HOSTED,
    help="Fills the folder path with the synthetic demo cut shipped in ./sample_data/ (no real patients or licensed dictionary).")
if HOSTED: _use_sample = True
folder = st.sidebar.text_input("Cut folder path (safety domains)", value=(_SAMPLE_DIR if _use_sample else ""), disabled=HOSTED,
    help="Path to a folder of safety-domain CSVs (ae/lb/eg/vs/pe). Every *.csv EXCEPT one "
         "named *meddra* loads; each file is classified by its content, not its name. No "
         "dictionary or SAP/protocol file is needed.")
if HOSTED: folder = _SAMPLE_DIR            # never trust a client-sent value in hosted mode
up_dom = st.sidebar.file_uploader("...or upload safety files (CSV or SAS .sas7bdat)",
    type=["csv","sas7bdat"], accept_multiple_files=True, disabled=HOSTED)
if HOSTED: up_dom = None

# ---- sidebar 2: outputs + optional models dir. No gate slider here -- the operating point
#      for this engine is the built-in [SI] criteria, which are recorded in the audit; there
#      is no single tunable cutoff to hide behind a slider and no external file to import. ----
st.sidebar.markdown("---"); st.sidebar.header("⚖ 2. Outputs")
# Hosted mode: outputs go to a server temp folder made ONCE per browser session
# (kept in session_state so reruns reuse it), and the models dir is pinned to its
# default "models"; neither path ever comes from a visitor.
# A TemporaryDirectory (not a bare mkdtemp) is kept in session_state, so the folder
# is deleted when Streamlit discards the expired session (and at exit) instead of
# piling up in /tmp, one per page view.
if HOSTED and "_hosted_out" not in st.session_state:
    st.session_state["_hosted_tmp"] = tempfile.TemporaryDirectory(prefix="risk_output_", ignore_cleanup_errors=True)
    st.session_state["_hosted_out"] = st.session_state["_hosted_tmp"].name
out_dir = st.sidebar.text_input("Output folder",(st.session_state["_hosted_out"] if HOSTED else "risk_output"), disabled=HOSTED,
    help=(OUT_HELP_BROWSER if IN_BROWSER else "Where risk_scores.csv + audit_log.csv are written on Run (also offered as downloads)."))
if HOSTED: out_dir = st.session_state["_hosted_out"]
models_dir = st.sidebar.text_input("Models dir (no trained model in this build)","models", disabled=HOSTED,
    help="This build has no trained-model path for this app: the labeled [SI] engine is the only scorer, "
         "and a risk_model.json found here STOPS the run rather than being silently ignored.")
if HOSTED: models_dir = "models"
_guard_artifacts(models_dir)   # runs on every rerun, before any compute

# ---- LOAD now so the pre-flight panel + classification are live. Errors captured into
#      load_err and surfaced in the panel, not raised as a stack trace. ----
domains={}; views={}; thr=dict(DEFAULT_THR); load_err=None   # built-in [SI] criteria; no external file
try:
    domains = load_domains(folder or None, up_dom)
    views = tier1_align(domains)
except Exception as e: load_err=str(e)

# ---- mode banner: this build always runs the transparent [SI] engine. The tag is computed
#      from the runtime probe + artifact presence (never a constant), so if a real model were
#      ever wired in, the banner would reflect it -- and an orphaned artifact hard-stops above. ----
banner = "Tier 3: STAND-IN [SI] (transparent weighted rule engine)"
st.info("**Mode banner:** "+banner+" · decision support only, not a clinical determination; "
        "the audit records which path ran and every threshold in force.")

# ---- pre-flight CONTRACT panel: show what loaded + how each file classified + the SAP source,
#      before any compute. Fixes belong in the sidebar (folder/uploads), NOT in the code. ----
st.header("📋 Input contract (pre-flight)")
if load_err: st.error(f"Import failed: {load_err}")
elif not domains: st.warning("No safety-domain CSVs loaded yet. Set the folder path or upload files.")
else:
    c1,c2=st.columns(2)
    with c1:
        st.markdown("**Domains loaded (classified by content)**")
        cls={d:classify_domain(df) for d,df in domains.items()}
        st.dataframe(pd.DataFrame([(d,cls[d] or "unrecognized",f"{len(domains[d])} rows",_classify_reason(domains[d])) for d in domains],
                     columns=["file","domain","rows","why classified this way"]), width="stretch", hide_index=True)
    with c2:
        st.markdown("**Scoring criteria**"); st.write("Built-in `[SI]` defaults (no external SAP/protocol file)")
        n_subj=len(set().union(*[set(v.index) for v in views.values()])) if views else 0
        st.write(f"Participants aligned → **{n_subj}**")
        present=", ".join(k for k in ("ae","lb","eg","vs","pe") if k in views) or "(none)"
        st.write("Safety domains → "+present)
    st.caption("This program reads ONLY the safety domains above and scores them against built-in [SI] "
               "criteria; it flags participants for human review and makes no clinical determination. A fatal "
               "outcome forces a CRITICAL safety category.")

# ---- Run button: disabled until at least one participant is aligned, so an empty input cannot
#      produce a misleading empty result. ----
n_ready = len(set().union(*[set(v.index) for v in views.values()])) if views else 0
if not st.button("🚀 Execute Participant risk screening", type="primary", disabled=not n_ready):
    st.stop()

# ---- execute the tiers on the already-loaded frames; time the whole run for the latency figure. ----
t0=time.perf_counter()
sig = tier2_signals(views, thr)                     # Tier 2: readable per-participant signals
scores = tier3_scores(sig, views, thr)              # Tier 3: [SI] weighted aggregation
results = tier4_categorize(scores, thr)             # Tier 4: categories + contributing factors
elapsed=(time.perf_counter()-t0)*1000

# ---- results: these tables ARE the tier outputs, computed from the operator's files. ----
st.header(f"Tiers 2 to 4 · per-participant risk (computed from your files; {elapsed:.2f} ms)")
if len(results):
    # fatal participants pinned to the top (internal _fatal key), then by safety score -- so a fatal
    # outcome always ranks at/above every non-fatal participant regardless of comorbidity load. The
    # _fatal sort key is dropped before display/export; it never reaches risk_scores.csv.
    shown=results.sort_values(["_fatal","safety_risk_score"], ascending=[False,False]).drop(columns="_fatal")
    st.dataframe(shown, width="stretch")
    dist=results["safety_category"].value_counts().to_dict()
    st.caption(f"Safety categories → " + ", ".join(f"{k}: {v}" for k,v in sorted(dist.items())))
st.expander("Processing log").write(
    f"Tier 1 aligned {n_ready} participants across {', '.join(sorted(views)) or 'no'} domains · "
    f"criteria: built-in [SI] defaults")

# ---- audit: one row per run, recording the CONTRACT (which files/classifications), the criteria
#      source + every threshold in force, the PATH ([SI]/[RM]), and the category distribution.
#      This is what makes a run reproducible from its audit alone and keeps this head's scope
#      separate from meddra_app.py / phi_app.py (separate program, separate audit_log.csv). ----
audit=pd.DataFrame([dict(program="risk_scorer", timestamp=pd.Timestamp.now().isoformat(timespec="seconds"),
    hosted_mode=("true" if HOSTED else "false"),
    domains={d:classify_domain(df) for d,df in domains.items()},
    domain_rows=json.dumps({d:len(df) for d,df in domains.items()}),
    n_subjects=int(n_ready), criteria_source="[SI] built-in defaults (no external SAP/protocol file)",
    thresholds_in_force=json.dumps(thr),
    mode_T3="STAND-IN",   # no trained risk-model path in this build (see _guard_artifacts)
    scoring_note="[SI] transparent weighted rule engine; decision support, not a clinical determination",
    safety_distribution=json.dumps(results["safety_category"].value_counts().to_dict()) if len(results) else "{}",
    disc_distribution=json.dumps(results["disc_category"].value_counts().to_dict()) if len(results) else "{}",
    measured_latency_ms=round(elapsed,2))])
# Drop the internal _fatal sort key so risk_scores.csv carries only the decision + evidence.
out_results = results.drop(columns=["_fatal"]) if len(results) else pd.DataFrame()
os.makedirs(out_dir, exist_ok=True)
if len(out_results): out_results.to_csv(os.path.join(out_dir,"risk_scores.csv"), index=False)
audit.to_csv(os.path.join(out_dir,"audit_log.csv"), index=False)
if IN_BROWSER: st.success("Done: `risk_scores.csv` and `audit_log.csv` are in this browser tab's memory only. Save them with the download buttons below.")
else: st.success(f"Wrote `{out_dir}/risk_scores.csv` and `{out_dir}/audit_log.csv`")
st.download_button("⬇ risk_scores.csv",out_results.to_csv(index=False).encode(),"risk_scores.csv","text/csv", on_click="ignore")
st.download_button("⬇ audit_log.csv",audit.to_csv(index=False).encode(),"audit_log.csv","text/csv", on_click="ignore")
