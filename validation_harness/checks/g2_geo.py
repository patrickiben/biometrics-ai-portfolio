#!/usr/bin/env python3
"""G2 per-program check: geometric statistics on the log scale in every PK program.

Called by validation_harness/run_harness.sh as: python3 checks/g2_geo.py <R dir> <SAS dir>
Prints: <programs passing> <programs checked> <evidence text>. A program passes when its R
code takes geometric statistics from the log scale (via pkstats(), whose own body must compute
exp(mean(log)) and the geometric CV from var(log), or an explicit log()), assigns geomean only
from a log-scale expression, and its SAS twin uses log(). Comments are ignored.
"""
import re, sys, glob, os
R, SAS = sys.argv[1], sys.argv[2]
PK = re.compile(r'^(t_pk_param_summary|t_pk_conc_summary|t_pk_param_by_period|t_accumulation|t_dose_proportionality(_ss)?|t_be_anova|f_pk_conc_mean|t_ada_impact_pk)\.R$')
def code_r(p):
    out = []
    for line in open(p, encoding='utf-8', errors='replace'):
        q = None; cut = len(line)
        for i, ch in enumerate(line):
            if q:
                if ch == q and line[i-1] != '\\': q = None
            elif ch in '"\'': q = ch
            elif ch == '#': cut = i; break
        out.append(line[:cut])
    return ''.join(out)
def code_sas(p):
    t = open(p, encoding='utf-8', errors='replace').read()
    t = re.sub(r'/\*.*?\*/', ' ', t, flags=re.S)
    return re.sub(r'(?m)^\s*\*[^;]*;', ' ', t)
helper = code_r(os.path.join(R, '00_setup_helpers.R'))
m = re.search(r'pkstats\s*<-\s*function.*?\n}\s*\n', helper, re.S)
hbody = m.group(0) if m else ''
helper_ok = bool(re.search(r'exp\(mean\(log\(', hbody)) and bool(re.search(r'sqrt\(exp\((?:stats::)?var\(log\(', hbody))
smac = code_sas(os.path.join(SAS, '00_setup_macros.sas'))
mm = re.search(r'%macro\s+pkstats\b.*?%mend\s+pkstats', smac, re.S | re.I)
sas_helper_ok = bool(mm) and re.search(r'\blog\s*\(', mm.group(0), re.I) is not None and re.search(r'\bexp\s*\(', mm.group(0), re.I) is not None
progs = sorted(p for p in glob.glob(os.path.join(R, '*', '*.R')) if PK.match(os.path.basename(p)))
bad = []
for p in progs:
    c = code_r(p)
    logvars = set(re.findall(r'([A-Za-z_.][A-Za-z0-9_.]*)\s*(?:<-|=)\s*log\(', c))
    uses_log = ('pkstats(' in c and helper_ok) or 'log(' in c
    for expr in re.findall(r'(?<![A-Za-z0-9_.])geomean\s*=(?!=)\s*([^,\n]+)', c):
        if 'log(' not in expr and not any(re.search(r'\b%s\b' % re.escape(v), expr) for v in logvars):
            uses_log = False
    sas = os.path.join(SAS, os.path.relpath(p, R))[:-2] + '.sas'
    sc = code_sas(sas) if os.path.exists(sas) else ''
    sas_ok = bool(sc) and (re.search(r'\blog\s*\(', sc, re.I) is not None or (sas_helper_ok and re.search(r'%pkstats\s*\(', sc, re.I) is not None))
    if not (uses_log and sas_ok):
        bad.append(os.path.relpath(p, R) + ('' if uses_log else ' (R)') + ('' if sas_ok else ' (SAS twin)'))
ok = len(progs) - len(bad)
ev = (f"{ok} of {len(progs)} PK programs take geometric statistics from the log scale in R (pkstats(), whose body computes exp(mean(log)) and the geometric CV from var(log), or an explicit log()), assign geomean only from log-scale expressions, and have a SAS twin that uses log() or the %pkstats macro (whose body works on the log scale)"
      + ("" if helper_ok else "; pkstats() helper does NOT compute log-scale statistics") + ("" if sas_helper_ok else "; SAS %pkstats macro does NOT compute log-scale statistics") + ("" if not bad else "; failing: " + ", ".join(bad)))
print(ok if (helper_ok and sas_helper_ok) else 0, len(progs), ev.replace('\n', ' '))
