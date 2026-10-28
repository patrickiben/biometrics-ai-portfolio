"""Portable adapter for the repository's ten validation gates.

Uses Python's standard library and fixed R/Python argument lists. The original
Bash runner remains the reference; this adapter adds no statistical methods.
G5 stays manual, G7 stays unsigned, and a legacy seeded-defect run does not
certify the portable runner's code. Run against a private project copy.
"""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict
import csv
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def files(root: Path):
    """Do not follow symlinks outside the copied project or scan infrastructure."""
    for directory, dirs, names in os.walk(root, followlinks=False):
        dirs[:] = sorted(d for d in dirs if d not in {".git", "node_modules", "__pycache__", ".quarto"}
                         and not (Path(directory) / d).is_symlink())
        for name in sorted(names):
            path = Path(directory) / name
            if not path.is_symlink():
                yield path


def matching_files(root: Path, pattern: str, flags=0, exclude=None) -> int:
    rx = re.compile(pattern, flags)
    return sum(bool(rx.search(read(p))) for p in files(root)
               if not exclude or not exclude(p))


def matching_lines(root: Path, pattern: str, flags=0, reject=None, extensions=None) -> int:
    rx = re.compile(pattern, flags)
    total = 0
    for path in files(root):
        if extensions and path.suffix not in extensions:
            continue
        for line in read(path).splitlines():
            if rx.search(line) and not (reject and reject(path, line)):
                total += 1
    return total


def command(argv, root: Path) -> subprocess.CompletedProcess:
    return subprocess.run([str(a) for a in argv], cwd=root, text=True,
                          encoding="utf-8", errors="replace", capture_output=True,
                          shell=False)


def rscript_path() -> str:
    found = os.environ.get("TOOLKIT_RSCRIPT") or shutil.which("Rscript")
    if not found or not Path(found).is_file():
        raise ValueError("Rscript is missing. Install R or select its executable in the control panel.")
    return str(Path(found).resolve())


def token(output: str, key: str, fallback="?") -> str:
    match = re.search(r"^" + re.escape(key) + r":?\s+(.+)$", output, re.M)
    return match.group(1).strip() if match else fallback


def twin_checks(root: Path):
    sas = [p for p in (root / "sas_tlf_pseudocode").rglob("*.sas") if not p.name.startswith("00_setup")]
    r = [p for p in (root / "r_tlf_pseudocode").rglob("*.R") if not p.name.startswith("00_setup")]
    def number(path):
        m = re.search(r'num\s*=\s*"?([0-9]+(?:\.[0-9]+)+)', read(path))
        return m.group(1) if m else None
    mismatches = 0
    for source in sas:
        twin = root / "r_tlf_pseudocode" / source.relative_to(root / "sas_tlf_pseudocode").with_suffix(".R")
        if twin.exists() and number(source) != number(twin):
            mismatches += 1
    collisions = 0
    for paths in (sas, r):
        counts = Counter((p.parent.name, number(p)) for p in paths if number(p))
        collisions += sum(n > 1 for n in counts.values())
    # Equal counts alone can hide unmatched stems; the portable gate checks the
    # claim explicitly instead of allowing a missing pair to be green.
    stems_sas = {str(p.relative_to(root / "sas_tlf_pseudocode").with_suffix("")) for p in sas}
    stems_r = {str(p.relative_to(root / "r_tlf_pseudocode").with_suffix("")) for p in r}
    return len(sas), len(r), mismatches, collisions, len(stems_sas ^ stems_r)


def reporting_checks(root: Path):
    cats, figs = [], []
    for folder, ext in (("r_tlf_pseudocode", "R"), ("sas_tlf_pseudocode", "sas")):
        cats += list((root / folder).glob("*/t_ecg_qtc_categorical." + ext))
        figs += list((root / folder).glob("*/f_qtc_change." + ext))
    good = sum(all(re.search(r">\s*" + n + r"\b", read(p)) for n in ("450", "480", "500", "30", "60")) for p in cats)
    ten = sum(bool(re.search(r"yintercept\s*=\s*10\b|refline\s+10\b", read(p))) for p in figs)
    both = sum(bool(re.search(r"yintercept\s*=\s*30\b|refline\s+30\b", read(p))) and
               bool(re.search(r"yintercept\s*=\s*60\b|refline\s+60\b", read(p))) for p in figs)
    return good, len(cats), ten, both, len(figs)


def sensitivity(root: Path):
    td = root / "validation_harness/teeth"
    registry = sha(td / "defects.csv") if (td / "defects.csv").is_file() else None
    frozen = read(td / "defects.sha256").split()[0] if (td / "defects.sha256").is_file() else None
    try:
        summary = json.loads(read(td / "results/summary.json"))
    except (OSError, ValueError):
        summary = None
    why = []
    if not registry:
        why.append("no defect registry")
    elif registry != frozen:
        why.append("defects.csv no longer matches its frozen hash in defects.sha256")
    if summary is None:
        why.append("no seeded-defect run recorded")
    else:
        if summary.get("registry_sha256") != registry:
            why.append("the last run used a different registry")
        changed = [p for p, h in summary.get("gate_scripts", {}).items()
                   if not (root / p).is_file() or sha(root / p) != h]
        if changed:
            why.append("changed since the last run: " + ", ".join(changed))
        if summary.get("partial"):
            why.append("the last run covered only part of the registry")
        needed = {"toolkit_launcher/native_harness.py", "toolkit_launcher/native_teeth.py",
                  "toolkit_launcher/stub_profile.R"}
        if not needed.issubset(summary.get("gate_scripts", {})):
            why.append("the last run did not record the portable runner scripts")
    evidence = []
    if registry:
        check = command([sys.executable, td / "apply_defect.py", td / "defects.csv", "--check-all", root], root)
        if check.returncode:
            gone = [line.split(":")[0] for line in check.stdout.splitlines() if "occurs" in line or "does not exist" in line]
            why.append("the registry no longer applies to the current code (" + ", ".join(gone) + ")")
        with (td / "defects.csv").open(encoding="utf-8", newline="") as handle:
            n = len(list(csv.DictReader(handle)))
        evidence.append(f"registry of {n} defects frozen at sha256 {registry}")
    if summary:
        counts = summary.get("counts", {})
        evidence.append(f"last run {summary.get('run_date')}: " + ", ".join(f"{k} {counts.get(k, 0)}" for k in ("CAUGHT", "SURVIVED", "EQUIVALENT", "NOT APPLICABLE")))
        survivors = [f"{r['id']} ({r['defect']})" for r in summary.get("rows", []) if r.get("class") == "SURVIVED"]
        if survivors:
            evidence.append("survived (disclosed, not failures): " + "; ".join(survivors))
        evidence.append("the counts describe this hand-picked list only, not a detection rate")
    text = "; ".join(evidence)
    if why:
        text = "stale: " + "; ".join(why) + ". " + text
    return ("stale" if why else "green"), text.replace("|", "/").replace("\n", " ")


def run(root: Path) -> dict:
    root = root.resolve()
    if not (root / "validation_harness/run_harness.sh").is_file():
        raise ValueError("Choose a complete toolkit project.")
    rr = rscript_path()
    gates = []
    def add(name, guards, status, evidence):
        gates.append(dict(gate=name, guards=guards, status=status, evidence=evidence, sign_off="pending"))
        print(f"{name}: {status}", flush=True)
    def r(expr):
        return command([rr, "-e", expr], root)
    def green(condition):
        return "green" if condition else "red"
    print("Trial-Management Validation Harness (portable Python adapter)", flush=True)
    parse = r('f<-list.files(".",pattern="[.]R$",recursive=TRUE,full.names=TRUE,all.files=TRUE); f<-f[!grepl("(^|/)[.]git(/|$)",f)]; f<-unique(normalizePath(f)); b<-sum(vapply(f,function(x)inherits(try(parse(x),silent=TRUE),"try-error"),logical(1))); cat(length(f),b)')
    values = parse.stdout.strip().split()
    total, bad = values[-2:] if parse.returncode == 0 and len(values) >= 2 else ("?", "?")
    repro = r('suppressWarnings(source("sim_lifecycle/simulate_adam.R")); set.seed(2026); s<-simulate_study(sample_design("BE",N=40),seed=2026); td<-tempfile(); dir.create(td); for(nm in c("adsl","adex","adpc","adpp","adae","advs","adlb","adeg")) { d<-s[[nm]]; dbl<-vapply(d,is.double,logical(1)); d[dbl]<-lapply(d[dbl],signif,digits=12); write.csv(d,file.path(td,paste0(nm,".csv")),row.names=FALSE) }; same<-vapply(c("adsl","adex","adpc","adpp","adae","advs","adlb","adeg"),function(nm) identical(readLines(file.path(td,paste0(nm,".csv"))),readLines(file.path("sim_lifecycle/out",paste0(nm,".csv")))),logical(1)); cat(sum(same))')
    reproduced = repro.stdout.strip() if repro.returncode == 0 else "0"
    add("G1 Reproducibility & environment", "the sandbox's eight committed output files regenerate byte for byte from code and seed, and every R program parses", green(bad == "0" and reproduced == "8"), f"{total} R files parse ({bad} fail; every .R file in the repository, each counted once, hidden directories included, .git excluded); the synthetic study regenerates {reproduced} of 8 committed ADaM-shaped files byte for byte from seed 2026 (base R)")

    geo = command([sys.executable, "validation_harness/checks/g2_geo.py", "r_tlf_pseudocode", "sas_tlf_pseudocode"], root)
    values = geo.stdout.strip().split(maxsplit=2)
    gp, gt, ge = values if len(values) == 3 else ("0", "0", "the per-program check did not run")
    ndist = matching_files(root / "r_tlf_pseudocode", re.escape("n_distinct(USUBJID)")) + matching_files(root / "sas_tlf_pseudocode", r"CLASS USUBJID|distinct USUBJID")
    draft = matching_files(root / "tlf_interpret", r"hallucinat|reject.*number|number.*not (in|from)|selftest|self-test", re.I)
    add("G2 PK and count convention scans", "PK programs use log-scale geometric statistics, counts use distinct participants, and the drafter's number check has a self-test (pattern scans; they do not show where a reported number comes from)", green(geo.returncode == 0 and gp == gt and gt != "0" and ndist > 0 and draft > 0), f"per-program scans: {ge}; distinct-participant counting in {ndist} programs; drafter number-validation self-test present ({draft})")

    conf = command([rr, "validation_harness/checks/conformance.R", "sim_lifecycle/out"], root)
    verdict = token(conf.stdout, "G3_VERDICT", "FAIL")
    subj = sum(matching_lines(root / folder, r"\bsubjects?\b", re.I, reject=lambda p, line: bool(re.search("subjid|usubjid", line, re.I))) for folder in ("sas_tlf_pseudocode", "r_tlf_pseudocode"))
    def reject_pii(path, line):
        rel = path.relative_to(root).as_posix()
        return rel.startswith(("sim_lifecycle/data/", "validation_harness/")) or bool(re.search(r"noreply|example\.(com|net)|https?://|@author|Copyright \(c\)", line))
    pii = matching_lines(root, r"[0-9]{3}-[0-9]{3}-[0-9]{4}|[a-z]{2,}\.[a-z]{2,}@[a-z]+\.(com|net)", re.I, reject_pii, {".csv", ".html", ".md"})
    add("G3 Data structure & integrity", "the analysis data passes the custom structural checks (not Pinnacle 21 or CDISC CORE), is intact, and PHI-free", green(conf.returncode == 0 and verdict == "PASS" and subj == 0 and pii == 0), f"custom structural checks {verdict} (checks/conformance.R; not Pinnacle 21 or CDISC CORE); {subj} trial-sense 'subject' in programs; {pii} PHI/PII hits in deliverable data/docs (raw public-registry calibration corpus excluded)")

    nsas, nr, mismatch, collisions, missing = twin_checks(root)
    add("G4 SAS/R twin structural parity", "the SAS and R twins line up program for program (structure only)", green(nsas == nr and mismatch == 0 and collisions == 0 and missing == 0 and bad == "0"), f"{nsas} SAS / {nr} R twin programs; {mismatch} twin TLF-number mismatches; {collisions} within-design number collisions; {missing} unmatched stems; all R parse. Structural only: SAS is not executed (no license), so no outputs are compared, and the R twins were written to mirror the SAS")
    add("G5 Adversarial QC panel", "no skeptical reader can break the deliverable", "manual", "manual record, not computed here: an AI-agent review panel reported 51 P0/P1 parity findings resolved; 6 previously-pending twin pairs re-verified by the panel (5 confirmed, 1 sad/t_lab_marked_abnormal denominator gap found and fixed). Human review of these findings is not yet recorded")

    edish = sum(matching_files(root / folder, r"\bedish\b|hy'?s.?law", re.I, exclude=lambda p: bool(re.search("readme|index", str(p), re.I))) for folder in ("sas_tlf_pseudocode", "r_tlf_pseudocode"))
    cat, ncat, ten, both, nfig = reporting_checks(root)
    add("G6 Reporting conventions", "TLF numbering, scope and ICH E14 conventions hold (pattern checks, not a regulatory review)", green(collisions == 0 and edish == 0 and ncat > 0 and cat == ncat and nfig > 0 and both == nfig and ten == 0), f"{collisions} TLF-number collisions; {edish} out-of-scope eDISH/Hy's terms in programs; ICH E14 categorical thresholds (>450/480/500 ms, change >30/60 ms) in {cat}/{ncat} QTc tables; QTc change figures: {both}/{nfig} draw the 30/60 ms ICH E14 categorical reference lines and {ten} draw a +10 ms line (the convention is 30/60 ms on every figure, no +10 ms line)")

    jargon = sum(matching_lines(root / folder, r"experimental (engine|method|analytic)|research-grade (engine|model)|non-standard (analytic )?method|unvalidated (engine|model)", re.I) for folder in ("sas_tlf_pseudocode", "r_tlf_pseudocode", "sim_lifecycle"))
    gov = matching_files(root / "tlf_interpret", r"frozen|temperature 0|human[ -]gate|pinned|human approv", re.I)
    add("G7 AI-governance documentation present", "the drafter's AI-use limits (frozen model, human gate) are written down and no PHI turns up (file scans); accountability needs a named statistician's signature, not yet given", "not signed" if jargon == 0 and pii == 0 and gov > 0 else "red", f"{jargon} experimental/non-standard method labels in analysis programs; {pii} PHI hits; frozen-model + human-gate discipline documented in {gov} tlf_interpret files. Not signed: accountability requires a named human signature")

    pkg = command([sys.executable, "package_qc.py"], root)
    report = read(root / "package_qc_report.md") if (root / "package_qc_report.md").is_file() else ""
    issues = re.search(r"([0-9]+) issue", report)
    pages = re.search(r"Scanned ([0-9]+) HTML", report)
    add("G8 Package & GUI consistency", "the package is navigable, linked, and internally consistent", green(pkg.returncode == 0), f"package_qc.py: {issues.group(1) if issues else '?'} issues across {pages.group(1) if pages else '?'} HTML pages, Markdown and published document text (see package_qc_report.md for any unscanned formats)")

    recompute = command([rr, "validation_harness/checks/independent_recompute.R", "sim_lifecycle/out"], root)
    out = recompute.stdout
    checks = len(re.findall(r"^CHECK .* (?:PASS|FAIL)(?: |$)", out, re.M))
    failed = len(re.findall(r"^CHECK .* FAIL(?: |$)", out, re.M))
    add("G9 Independent recomputation", "the sandbox's NCA parameters (ADPP) and printed results (geometric means and CV%, GMR and 90% CI, AE participant counts) match a separately written recomputation from ADPC, ADEX, ADSL and ADAE (same author: a re-derivation, not double programming by a second person)", green(recompute.returncode == 0 and token(out, "G9_VERDICT", "FAIL") == "PASS"), f"{token(out, 'G9_PROFILES', '0')} profiles compared; maximum relative difference {token(out, 'G9_MAXREL', 'NA')} (tolerance 1e-6); {failed} of {checks} checks failed; engines: {token(out, 'G9_ENGINES', 'none')} (checks/independent_recompute.R; AUC(0-t) from the predose zero, BLQ as 0)")

    status, evidence = sensitivity(root)
    add("G10 Harness sensitivity", "the harness's own reach: registered programming defects are planted one at a time in a throwaway copy and compared with the unmutated copy (QC-process engineering, not a statistical method)", status, evidence)
    version = r("cat(R.version.string)").stdout.strip()
    ledger = dict(generated=datetime.now().astimezone().strftime("%Y-%m-%d %H:%M %Z"), r_version=version,
                  green=sum(g["status"] == "green" for g in gates), manual=sum(g["status"] == "manual" for g in gates),
                  unsigned=sum(g["status"] == "not signed" for g in gates), total=len(gates), gates=gates)
    write_ledger(root, ledger)
    return ledger


def write_ledger(root: Path, ledger: dict):
    target = root / "validation_harness"
    text = json.dumps(ledger, indent=1, ensure_ascii=False)
    (target / "ledger.json").write_text(text, encoding="utf-8")
    scanned = ledger["total"] - ledger["manual"] - ledger["unsigned"]
    lines = ["# Evidence Ledger: Trial-Management Validation Harness", "",
             f"_Generated {ledger['generated']} · {ledger['r_version']} · {ledger['green']} of {scanned} automated gates green, {ledger['manual']} manual record, {ledger['unsigned']} not signed · synthetic deliverables · human sign-off pending on every gate._", "",
             "| Gate | Guards (the fragile object) | Status | Evidence (automated) | Human sign-off |", "|---|---|:--:|---|---|"]
    for g in ledger["gates"]:
        values = [g["gate"], g["guards"], g["status"], g["evidence"], "☐ pending"]
        lines.append("| " + " | ".join(v.replace("|", "/").replace("\n", " ") for v in values) + " |")
    lines += ["", "> G5 is a manual record. G7 requires a named statistician's sign-off. G10 is stale when the recorded registry or runner scripts change. Most checks are structural; SAS is never executed. No gate is signed automatically.", "", "> Re-run with the toolkit control panel's **Run QC harness** action."]
    (target / "EVIDENCE_LEDGER.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    page = target / "index.html"
    if page.is_file():
        page.write_text(re.sub(r'(<script id="ledger" type="application/json">\n).*?(\n</script>)', lambda m: m.group(1) + text + m.group(2), read(page), count=1, flags=re.S), encoding="utf-8")
    print(f"Ledger written: {ledger['green']} of {scanned} automated gates green; {ledger['manual']} manual; {ledger['unsigned']} not signed", flush=True)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    args = parser.parse_args(argv)
    try:
        ledger = run(args.root)
    except (OSError, ValueError) as exc:
        print("Toolkit QC harness: " + str(exc), file=sys.stderr)
        return 2
    # The original runner emits the ledger regardless of red gates. The GUI
    # records a failed check when a gate is red while retaining the evidence.
    return int(any(g["status"] == "red" for g in ledger["gates"]))


if __name__ == "__main__":
    raise SystemExit(main())
