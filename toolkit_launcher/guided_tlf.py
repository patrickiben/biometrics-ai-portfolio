"""Pure, client-neutral guided setup for the existing R/SAS TLF draft libraries.

This configures inputs and copies source programs. It deliberately does not
complete unfinished analyses, derive ADaM, or certify statistical output.
"""
from __future__ import annotations

import csv
import datetime as dt
import hashlib
import io
import json
import math
import re
from pathlib import Path

DESIGNS = {"parallel": "Parallel group", "crossover": "Crossover", "single_sequence": "Single / fixed sequence", "sad": "Single ascending dose", "mad": "Multiple ascending dose"}
COMMON = "STUDYID USUBJID TRT01A TRT01AN TRTA TRTAN TRTSEQP TRTSEQPN APERIOD APERIODC SAFFL PKFL ITTFL ANL01FL"
BDS = "PARAM PARAMCD AVAL AVALC AVALU BASE CHG PCHG AVISIT AVISITN ATPT ATPTN ADT ADY ABLFL ONTRTFL"
DOMAIN_FIELDS = {
    "adsl": COMMON + " AGE SEX RACE ETHNIC AGEGR1 HEIGHTBL WEIGHTBL BMIBL SBPBL DBPBL PULSEBL CRCLBL EGFRBL SMOKSTAT ALCOHOL RENALCAT DISSEVBL ENRLFL RANDFL COMPLFL DCSFL DCSREAS RANDDT TRTSDT TRTEDT EOSDT EOSSTT DTHDT ADAFL PDFL",
    "adae": COMMON + " TRTEMFL AESOC AEDECOD AESEVN ASEV AREL AESER AESDTH AEACN AEOUT ASTDT ASTDY AENDT AENDY ADURN AESCONG AESDISAB AESHOSP AESLIFE AESMIE",
    "adcm": COMMON + " CMCLAS CMDECOD PREFL ONTRTFL",
    "addv": COMMON + " DVCAT DVDECOD IMPDVFL ENRLFL",
    "adeg": COMMON + " " + BDS + " ANRIND EGINTP ANRLO ANRHI",
    "adex": COMMON + " " + BDS + " EXDOSE EXDOSU EXSTDTC EXENDTC EXDUR EXDOSFRQ",
    "adis": COMMON + " " + BDS + " ADAFL BASEADA TEADAFL ADAINDFL ADABSTFL ADAPERFL ADATRNFL NABFL NABRES ADATITER",
    "adlb": COMMON + " " + BDS + " A1HI A1LO ANRIND BNRIND R2ULN ATOXGRN BTOXGRN ANRLO ANRHI",
    "admh": COMMON + " MHBODSYS MHDECOD MHOCCUR",
    "adpc": COMMON + " " + BDS + " ATM",
    "adpd": COMMON + " " + BDS + " PDFL",
    "adpp": COMMON + " " + BDS + " DTYPE",
    "advs": COMMON + " " + BDS + " ANRLO ANRHI ANRIND",
}
DOMAIN_FIELDS = {k: set(v.split()) for k, v in DOMAIN_FIELDS.items()}
for _slot, _extra in {
    "adsl": "HRBL SYSBPBL DIABPBL QTCFBL CREATBL CHILDPOT BMICAT RENALGR1 HEPATGR1 CYPPHENO TRT02A DCPERIOD SITEID PKSSFL COMPDOSF COMPP1FL COMPP2FL CONFL RFSTDTC RFENDTC DCSDTC TR01SDTM TR02SDTM BSACRBL BMIGR1 RFGR1 RENALGR CUMDOSEN ISEVALFL",
    "adae": "APERIODN",
    "adis": "ADABLFL ADAEMFL ISEVALFL PARCAT1 NABRESC ADAPOSFL TRTEMFL",
    "adex": "TRTDURD NDOSES EXCMPLPC EXPLDOS EXADJ",
    "adlb": "ATOXGRH ATOXGRL ATOXGR CRIT1FL ADTC",
    "admh": "MHCAT",
    "adpc": "NRRELTM AFRLT ARRLT ARELTM ADTM",
}.items():
    DOMAIN_FIELDS[_slot].update(_extra.split())
NUMERIC = set("TRT01AN TRTAN TRTSEQPN APERIOD AGE HEIGHTBL WEIGHTBL BMIBL SBPBL DBPBL PULSEBL CRCLBL EGFRBL AESEVN ASTDY AENDY ADURN AVAL BASE CHG PCHG AVISITN ATPTN ADY A1HI A1LO R2ULN ATOXGRN BTOXGRN ANRLO ANRHI ATM EXDOSE EXDUR ADATITER".split())
NUMERIC.update("HRBL SYSBPBL DIABPBL QTCFBL CREATBL DCPERIOD APERIODN TRTDURD NDOSES EXCMPLPC EXPLDOS ATOXGRH ATOXGRL NRRELTM AFRLT ARRLT ARELTM BSACRBL CUMDOSEN".split())
DATES = set("RANDDT TRTSDT TRTEDT EOSDT DTHDT ASTDT AENDT ADT".split())
FLAGS = {"SAFFL": "safety_yes", "PKFL": "pk_yes", "ITTFL": "itt_yes", "PDFL": "pd_yes", "ADAFL": "ada_yes", "TRTEMFL": "emergent_yes"}
LIMITATIONS = [
    "Configured source drafts, not validated study analyses. Existing methods, fixed parameter lists, category definitions, and unfinished rendering sections are retained for qualified statistical review.",
    "CSV inputs must already contain the ADaM analysis variables and derivations required by the selected outputs. This setup does not derive ADaM, choose an estimand, or approve a statistical analysis plan.",
    "A successful setup check validates files, mappings, types, and selected structural requirements; it does not establish model suitability, statistical correctness, or complete report rendering.",
]


def _language(module_id):
    if module_id not in {"r_tlf", "sas_tlf"}:
        raise ValueError("Unsupported TLF module")
    return "r" if module_id == "r_tlf" else "sas"


def _library(module_id, root):
    return Path(root) / ("r_tlf_pseudocode" if _language(module_id) == "r" else "sas_tlf_pseudocode")


def _code(text, lang):
    """Remove comments without losing quoted column names or treating # as code."""
    pattern = r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|#[^\n]*' if lang == "r" else r'"(?:""|[^"])*"|\'(?:\'\'|[^\'])*\'|/\*[\s\S]*?\*/'
    return re.sub(pattern, lambda m: "" if m.group().startswith("#" if lang == "r" else "/*") else m.group(), text)


def _tokens(text, lang):
    code = _code(text, lang)
    strings = re.findall(r'"([A-Z][A-Z0-9_]*)"|\'([A-Z][A-Z0-9_]*)\'', code)
    bare = re.sub(r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'', "", code)
    return set(re.findall(r"\b[A-Z][A-Z0-9_]+\b", bare)) | {a or b for a, b in strings}


def _requirements(text, lang, design, stem):
    """Source-derived structural contract; not a general-purpose code analyzer.

    Domain vocabularies prevent derived report columns and quoted value codes
    from becoming upload requirements. Dynamic design/helper fields are explicit.
    The manifest labels this as a structural check, never execution validation.
    """
    code = _code(text, lang)
    domains = sorted(set(re.findall(r"adam[.$](ad\w+)", code, re.I)) & DOMAIN_FIELDS.keys())
    tokens = _tokens(text, lang)
    req = {slot: tokens & DOMAIN_FIELDS[slot] for slot in domains}
    for slot, fields in req.items():
        # All source domains represent participants, including denominator inputs.
        fields.add("USUBJID")
        if slot == "adsl" and stem == "l_sae_death":
            req[slot] = {"USUBJID", "DTHDT"}
            continue
        if design in {"crossover", "single_sequence"}:
            if slot == "adsl":
                if "seqvar" in code.lower() or "TRTSEQP" in tokens:
                    fields.add("TRTSEQP")
                    if lang == "sas":
                        fields.add("TRTSEQPN")
                if re.search(r"(?:bign\(adam\$adsl[^\n]*dv\$trtvar|%bign\(ds=adam\.adsl[^\n]*trtvar=&TRTVAR)", code):
                    fields.add("TRTA")
                    if lang == "sas":
                        fields.add("TRTAN")
            else:
                if "trtvar" in code.lower():
                    fields.add("TRTA")
                if "trtnvar" in code.lower():
                    fields.add("TRTAN")
                if "byperiod" in code.lower():
                    fields.update({"APERIOD", "APERIODC"})
        elif "trtvar" in code.lower():
            fields.add("TRT01A")
            if "trtnvar" in code.lower():
                fields.add("TRT01AN")
        if slot == "adsl" and ("bign(" in code or "%bign(" in code):
            for flag in re.findall(r'popfl\s*=\s*["\']?([A-Z]+FL)', code, re.I):
                fields.add(flag.upper())
        if slot == "adpp" and ("pkstats(" in code or "%pkstats(" in code):
            fields.add("AVAL")
        # A symbol in a paired domain is not an input requirement on both sides
        # of a join. These source families have explicit population ownership.
        if slot not in {"adsl", "adpc", "adpp"}:
            fields.discard("PKFL")
        if slot in {"adpc", "adpp", "adpd", "adis"}:
            fields.discard("SAFFL")
        if slot == "adsl":
            fields.discard("ANL01FL")
        if slot == "adex" and stem not in {"t_exposure", "t_dose_proportionality"}:
            fields.intersection_update({"USUBJID", "SAFFL", "TRTA", "TRTAN", "TRT01A", "TRT01AN", "APERIOD", "APERIODC"})
        if slot == "adis" and stem == "t_ada_impact_pk":
            fields.intersection_update({"USUBJID", "ADAFL", "ISEVALFL", "TEADAFL", "ADAEMFL", "ADAPOSFL", "TRTEMFL", "PARCAT1", "TRTA", "TRTAN", "TRT01A", "TRT01AN", "APERIOD", "APERIODC"})
            if lang == "r" and design == "crossover":
                fields.add("PARAMCD")
        if slot == "adpc" and "cqtc_hysteresis" in stem:
            fields.difference_update({"ANL01FL", "CHG", "BASE"})
    return {slot: sorted(fields) for slot, fields in req.items()}


def _inventory(module_id, root):
    lang = _language(module_id)
    ext = "R" if lang == "r" else "sas"
    out = {}
    for design in DESIGNS:
        out[design] = {}
        for path in sorted((_library(module_id, root) / design).glob("*." + ext)):
            text = path.read_text(encoding="utf-8")
            title = re.search(r"TITLE\s*:\s*(.*)", text)
            out[design][path.stem] = {"title": title.group(1).strip() if title else path.stem,
                "path": path, "text": text, "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                "requirements": _requirements(text, lang, design, path.stem)}
    return out


def _field(id, label, type="text", default="", **kw):
    return {"id": id, "label": label, "type": type, "default": default, **kw}


def schema(module_id, root):
    lang = _language(module_id)
    inventory = _inventory(module_id, root)
    fields = [_field("study_id", "Study identifier", required=True),
        _field("design", "Study design", "select", "parallel", required=True,
            options=[{"value": k, "label": v} for k, v in DESIGNS.items()]),
        _field("outputs", "Tables, listings, and figures", "template-select", [], required=True,
            depends_on="design", options_by_design={d: [{"value": stem, "label": stem + " — " + item["title"], "inputs": list(item["requirements"])} for stem, item in outputs.items()] for d, outputs in inventory.items()}),
        _field("meddra", "MedDRA version used for this study", description="Printed in applicable dictionary footnotes; enter the actual version or Not applicable."),
        _field("whodrug", "WHODrug release used for this study", description="Printed in applicable dictionary footnotes; enter the actual release or Not applicable.")]
    mappings = [_field(value, label + " positive value", default="Y", required=True, description="Exact source value mapped to Y; other nonblank values map to N. Blank stays missing.") for value, label in
                [("safety_yes", "Safety population"), ("pk_yes", "PK population"), ("itt_yes", "ITT population"), ("pd_yes", "PD population"), ("ada_yes", "ADA evaluable"), ("emergent_yes", "Treatment emergent")]]
    settings = [
        _field("pk_parameter", "PK concentration PARAMCD", default="CONC", description="Used by PK/PD overlay and concentration–QTc templates with an analyte selector."),
        _field("pd_parameter", "PD endpoint PARAMCD", default="PDMARK1", description="Used by source templates that select one PD biomarker."),
        _field("reference_label", "Reference treatment / period source label", default="Reference", description="BE comparisons only: mapped to Reference. For fixed sequence, this is APERIODC; otherwise TRTA."),
        _field("test_label", "Test treatment / period source label", default="Test", description="BE comparisons only: mapped to Test. The existing comparison supports exactly these two levels."),
        _field("profile_days", "Full concentration–QTc profile days", default="1, 14", description="MAD concentration–QTc templates: comma-separated integer ADY values specified in your analysis plan."),
        _field("steady_state_first_day", "First steady-state trough day", "number", 5, min=1, max=10000, description="MAD accumulation template: first ADY included in the existing trough slope model."),
        _field("cqtc_form", "Prespecified concentration–QTc model form", "select", "LINEAR", options=[{"value": "LINEAR", "label": "Linear"}, {"value": "EMAX", "label": "Emax"}], description="SAD/MAD hysteresis table only; select the form already specified in the analysis plan."),
        _field("marked_high", "Marked high laboratory threshold (× ULN)", "number", 1.5, min=0.000001, max=1000, description="Parallel R abnormal laboratory listing only; replaces its explicit source threshold."),
        _field("marked_low", "Marked low laboratory threshold (× LLN)", "number", 0.5, min=0, max=1000, description="Parallel R abnormal laboratory listing only; replaces its explicit source threshold."),
    ]
    if lang == "sas":
        settings = [f for f in settings if f["id"] not in {"marked_high", "marked_low"}]
    else:
        settings = [f for f in settings if f["id"] != "steady_state_first_day"]
    return {"title": ("R" if lang == "r" else "SAS") + " TLF guided study setup",
        "intro": "Choose draft outputs, upload prepared ADaM CSV exports, map columns, and generate a configured project. All five designs are available. Setup does not complete unfinished analyses or approve methods.",
        "steps": [{"id": "study", "title": "Study and outputs", "description": "Use your own neutral study identifier and approved design.", "fields": fields},
            {"id": "inputs", "title": "ADaM inputs and column mappings", "description": "Only domains needed by your selected outputs are required. Use ISO dates (YYYY-MM-DD), numeric analysis values, and character participant identifiers. Optional columns may be needed by another output; Validate lists the exact selected requirements.", "fields": []},
            {"id": "settings", "title": "Population values and study selectors", "description": "Controls apply only where a selected source template uses them. Existing statistical methods and other category definitions remain in the draft and are listed for review.", "fields": mappings + settings},
            {"id": "review", "title": "Review before generating", "description": "Review the mapping and method limitations. Generation creates files; it does not execute analysis.", "fields": [_field("reviewed", "I reviewed the selected draft methods and input mappings", "checkbox", False, required=True)]}],
        "inputs": [{"id": slot, "label": slot.upper() + " CSV", "description": "Prepared " + slot.upper() + " analysis records; selection determines required columns.",
            "columns": [{"id": col, "label": col, "type": "number" if col in NUMERIC else "date" if col in DATES else "text", "required": False} for col in sorted(columns)]} for slot, columns in DOMAIN_FIELDS.items()]}


def _read_rows(descriptor):
    with Path(descriptor["absolute_path"]).open(encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        if not reader.fieldnames or any(not name for name in reader.fieldnames) or len(reader.fieldnames) != len(set(reader.fieldnames)):
            raise ValueError("CSV headers must be nonempty and unique")
        records = list(reader)
        if any(None in row or any(v is None for v in row.values()) for row in records):
            raise ValueError("CSV rows must have exactly the header's number of fields")
        return reader.fieldnames, records


def validate(module_id, values, inputs, root):
    lang = _language(module_id)
    errors, warnings = [], []
    def error(field, message):
        errors.append({"field": field, "message": message})
    defaults = {f["id"]: f.get("default") for step in schema(module_id, root)["steps"] for f in step["fields"]}
    v = {key: values.get(key, default) for key, default in defaults.items()}
    for key in ["study_id", "meddra", "whodrug", "pk_parameter", "pd_parameter", "reference_label", "test_label", *FLAGS.values()]:
        value = v.get(key, "")
        if not isinstance(value, str) or len(value) > 200 or any(ord(c) < 32 for c in value):
            error(key, "Use a single line of at most 200 characters.")
            v[key] = ""
        else:
            v[key] = value.strip()
    if not v["study_id"]:
        error("study_id", "Enter a study identifier.")
    if lang == "sas":
        for key in ("study_id", "meddra", "whodrug"):
            if re.search(r'[&%\'";\r\n]', v[key]):
                error(key, "SAS report metadata cannot contain quotes, semicolons, percent signs, or ampersands.")
    for key in FLAGS.values():
        if not v[key]:
            error(key, "Enter the source value that means included / yes.")
    for key in ("pk_parameter", "pd_parameter"):
        if not re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_.-]{0,39}", v[key]):
            error(key, "Use a PARAMCD of 1–40 letters, digits, underscores, dots, or hyphens.")
    if v.get("reviewed") is not True:
        error("reviewed", "Review and acknowledge the draft methods and input mappings before generating.")
    if not isinstance(v.get("design"), str) or v["design"] not in DESIGNS:
        error("design", "Choose an available study design.")
        v["design"] = "parallel"
    available = _inventory(module_id, root)[v["design"]]
    outputs = v.get("outputs", [])
    if not isinstance(outputs, list) or not outputs or any(not isinstance(x, str) or x not in available for x in outputs):
        error("outputs", "Select at least one output from the chosen design.")
        outputs = []
    v["outputs"] = list(dict.fromkeys(outputs))
    requirements = {}
    for stem in v["outputs"]:
        for slot, cols in available[stem]["requirements"].items():
            requirements.setdefault(slot, set()).update(cols)
    for key, low, high in [("steady_state_first_day", 1, 10000), ("marked_high", 0.000001, 1000), ("marked_low", 0, 1000)]:
        if key not in v:
            continue
        try:
            if isinstance(v.get(key), bool):
                raise ValueError()
            number = float(v.get(key, 1.5 if key == "marked_high" else 0.5 if key == "marked_low" else 5))
            if not math.isfinite(number) or not low <= number <= high or (key == "steady_state_first_day" and not number.is_integer()):
                raise ValueError()
            v[key] = int(number) if key == "steady_state_first_day" else number
        except (TypeError, ValueError):
            error(key, f"Enter a valid {'integer' if key == 'steady_state_first_day' else 'number'} from {low} to {high}.")
    days = v.get("profile_days", "")
    if not isinstance(days, str) or len(days) > 500 or not re.fullmatch(r"\s*\d{1,5}(?:\s*,\s*\d{1,5})*\s*", days):
        error("profile_days", "Enter comma-separated positive integer study days.")
    else:
        profile_days = list(dict.fromkeys(int(x.strip()) for x in days.split(",")))
        if len(profile_days) > 40 or any(not 1 <= d <= 10000 for d in profile_days):
            error("profile_days", "Use 1–40 days, each between 1 and 10000.")
    if not isinstance(v.get("cqtc_form"), str) or v["cqtc_form"] not in {"LINEAR", "EMAX"}:
        error("cqtc_form", "Choose Linear or Emax.")
    if "t_be_anova" in v["outputs"] and (not v["reference_label"] or not v["test_label"] or v["reference_label"] == v["test_label"]):
        error("reference_label", "BE comparison needs two distinct nonempty source labels.")
    raw_maps = values.get("columns", {})
    if not isinstance(raw_maps, dict):
        error("columns", "Column mappings must be an object.")
        raw_maps = {}
    maps, records_by_slot = {}, {}
    for slot, required in requirements.items():
        if slot not in inputs:
            error("inputs." + slot, slot.upper() + " is required by the selected outputs.")
            continue
        try:
            headers, rows = _read_rows(inputs[slot])
        except (ValueError, OSError, csv.Error, UnicodeError) as exc:
            error("inputs." + slot, "Could not read CSV: " + str(exc))
            continue
        if not rows:
            if slot in {"adae", "adcm", "admh", "addv"}:
                warnings.append(slot.upper() + " has zero records. Review zero-event behavior in every selected draft output.")
            else:
                error("inputs." + slot, "The selected analysis / denominator domain has no records.")
        chosen = raw_maps.get(slot, {})
        if not isinstance(chosen, dict):
            error("columns." + slot, "Column mappings must be an object.")
            chosen = {}
        mapping = {}
        for col in sorted(DOMAIN_FIELDS[slot]):
            candidates = [h for h in headers if h.upper() == col]
            source = chosen.get(col, candidates[0] if len(candidates) == 1 else "")
            if source and (not isinstance(source, str) or source not in headers):
                error(f"columns.{slot}.{col}", "Choose a column from the uploaded CSV.")
            elif source:
                mapping[col] = source
            elif col in required:
                error(f"columns.{slot}.{col}", f"Map {slot.upper()}.{col}; selected output requires it.")
        maps[slot] = mapping
        records_by_slot[slot] = rows
        for col, source in mapping.items():
            vals = [row[source] for row in rows]
            if col in NUMERIC:
                bad = [x for x in vals if x.strip() and (not _is_number(x))]
                if bad:
                    error(f"columns.{slot}.{col}", f"{col} contains {len(bad)} nonnumeric/nonfinite values; correct the prepared input.")
            elif col in DATES:
                if any(x.strip() and not _is_date(x) for x in vals):
                    error(f"columns.{slot}.{col}", "Use ISO dates YYYY-MM-DD or blank values.")
            if col == "USUBJID" and any(not x.strip() for x in vals):
                error(f"columns.{slot}.{col}", "Participant identifiers cannot be blank.")
            if col == "STUDYID" and any(x != v["study_id"] for x in vals):
                error(f"columns.{slot}.{col}", "Every mapped STUDYID must exactly match the configured study identifier; mixed or blank study IDs are not accepted.")
            if lang == "sas" and any(len(x.encode("utf-8")) > 32767 for x in vals):
                error(f"columns.{slot}.{col}", "SAS character values must be at most 32767 UTF-8 bytes.")
            if col in FLAGS and vals and not any(x == v[FLAGS[col]] for x in vals):
                warnings.append(f"{slot.upper()}.{col}: no records match the configured positive value.")
        if slot == "adsl" and "USUBJID" in mapping:
            ids = [row[mapping["USUBJID"]] for row in rows]
            if len(ids) != len(set(ids)):
                error("inputs.adsl", "ADSL must contain one record per participant; duplicate USUBJID values found.")
        if "STUDYID" not in mapping:
            warnings.append(slot.upper() + ": no STUDYID column mapped. Confirm that all uploaded records belong to the configured study; identity cannot be checked from this domain.")
    v["columns"] = maps
    if "adsl" in records_by_slot and "USUBJID" in maps["adsl"]:
        subjects = {row[maps["adsl"]["USUBJID"]] for row in records_by_slot["adsl"]}
        for slot, rows in records_by_slot.items():
            if slot != "adsl" and "USUBJID" in maps[slot]:
                unknown = {row[maps[slot]["USUBJID"]] for row in rows} - subjects
                if unknown:
                    error("inputs." + slot, f"{slot.upper()} contains {len(unknown)} participant identifier(s) absent from required ADSL. Reconcile the prepared domains before generating.")
    if "t_be_anova" in v["outputs"] and "adpp" in records_by_slot:
        col = "APERIODC" if v["design"] == "single_sequence" else "TRTA"
        mapping = maps["adpp"]
        if col in mapping:
            observed = {row[mapping[col]] for row in records_by_slot["adpp"] if not mapping.get("PKFL") or row[mapping["PKFL"]] == v["pk_yes"]}
            if observed != {v["reference_label"], v["test_label"]}:
                error("reference_label", "The current BE contrast requires exactly the two specified treatment / period labels in PK-evaluable ADPP records.")
    warnings.extend(LIMITATIONS)
    if "adae" in requirements and not v["meddra"]:
        warnings.append("MedDRA version was not supplied; applicable generated footnotes will say Not specified.")
    if "adcm" in requirements and not v["whodrug"]:
        warnings.append("WHODrug release was not supplied; applicable generated footnotes will say Not specified.")
    if v["design"] == "mad" and "f_pkpd_overlay" in v["outputs"]:
        warnings.append("MAD PK/PD overlay: the source does not implement its stated steady-state day filter. Supply the intended profile data and review the draft's labeling; setup does not assert steady-state selection.")
    if lang == "r" and "t_accumulation" in v["outputs"]:
        warnings.append("R accumulation: the source trough slope uses all supplied qualifying trough days; its described prespecified plateau-window filter is not implemented. Review data selection and the statistical interpretation.")
    if lang == "r" and v["design"] == "crossover" and "t_ada_impact_pk" in v["outputs"]:
        warnings.append("R crossover ADA impact: the retained source maps a missing joined ADA status to ADA-negative. This assumption needs explicit study review before using the draft results.")
    if lang == "sas":
        warnings.append("SAS source helpers and reports contain unfinished sections. SAS software/license is needed to run the generated draft; setup does not validate a SAS execution.")
    summary = [f"{len(v['outputs'])} {DESIGNS[v['design']]} draft outputs selected.", f"{len(requirements)} required ADaM domains; mappings and types checked."]
    return {"errors": errors, "warnings": warnings, "summary": summary, "normalized": v,
            "requirements": {k: sorted(cols) for k, cols in requirements.items()}}


def _is_number(value):
    try:
        return bool(re.fullmatch(r"[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[Ee][+-]?[0-9]+)?", value.strip())) and math.isfinite(float(value))
    except (ValueError, TypeError, OverflowError):
        return False


def _is_date(value):
    try:
        return bool(re.fullmatch(r"\d{4}-\d{2}-\d{2}", value)) and bool(dt.date.fromisoformat(value))
    except ValueError:
        return False


def _canonical_rows(v, inputs):
    result = {}
    for slot, mapping in v["columns"].items():
        _, rows = _read_rows(inputs[slot])
        mapped = []
        for row in rows:
            item = {}
            for col, source in mapping.items():
                value = row[source]
                if col in FLAGS and value:
                    value = "Y" if value == v[FLAGS[col]] else "N"
                if "t_be_anova" in v["outputs"] and col == ("APERIODC" if v["design"] == "single_sequence" else "TRTA"):
                    value = {v["reference_label"]: "Reference", v["test_label"]: "Test"}.get(value, value)
                item[col] = value
            mapped.append(item)
        result[slot] = mapped
    return result


def _csv_text(columns, rows):
    out = io.StringIO(newline="")
    writer = csv.DictWriter(out, fieldnames=columns, quoting=csv.QUOTE_ALL, lineterminator="\n")
    writer.writeheader()
    writer.writerows(rows)
    return out.getvalue()


def _r_string(value):
    return json.dumps(str(value), ensure_ascii=True)


def _configure_source(text, lang, v):
    profile_days = list(dict.fromkeys(int(x.strip()) for x in v["profile_days"].split(",")))
    if lang == "r":
        text, n = re.subn(r'^source\("\.\./00_setup_helpers\.R"\)\s*$', '# Helpers and canonical data are supplied by 00_run.R.', text, flags=re.M)
        text, m = re.subn(r'^env\s*<-\s*setup\([^\n]*\)\s*$', 'env <- guided_setup()', text, flags=re.M)
        for variable, value in [("PCCD", v["pk_parameter"]), ("PC_CD", v["pk_parameter"]), ("PDCD", v["pd_parameter"]), ("PD_CD", v["pd_parameter"]), ("PARAM_CD", v["pd_parameter"]), ("FORM", v["cqtc_form"])]:
            text = re.sub(r'(?m)^(' + variable + r'\s*<-\s*)"[^"\n]*"', lambda match: match[1] + _r_string(value), text)
        text = re.sub(r'(?m)^(PROFDAYS\s*<-\s*)c\([^\n)]*\)', lambda match: match[1] + "c(" + ", ".join(map(str, profile_days)) + ")", text)
        for variable, key in [("mark_hi", "marked_high"), ("mark_lo", "marked_low")]:
            text = re.sub(r'(?m)^(' + variable + r'\s*<-\s*)[\d.]+', lambda match: match[1] + str(v[key]), text)
    else:
        text, n = re.subn(r'^%include "\.\./00_setup_macros\.sas";\s*$', '/* Helpers and canonical data are supplied by 00_run.sas. */', text, flags=re.M)
        text, m = re.subn(r'^%setup\(study=CP-101, adam=/data/adam, out=/data/tfl\);\s*$', '%guided_setup;', text, flags=re.M)
        for variable, value in [("PCPARM", v["pk_parameter"]), ("PDPARM", v["pd_parameter"]), ("FORM", v["cqtc_form"]), ("PROFDAYS", " ".join(map(str, profile_days))), ("SS_FIRSTDAY", str(v["steady_state_first_day"]))]:
            text = re.sub(r'(?im)(%let\s+' + variable + r'\s*=\s*)[^;]*;', lambda match: match[1] + value + ";", text)
        # These source templates inline the analyte selector instead of %let.
        text = re.sub(r"(PARAMCD\s*=\s*)'CONC'", lambda match: match[1] + "'" + v["pk_parameter"] + "'", text)
    if n != 1 or m != 1:
        raise ValueError("Source setup contract changed; review this template before generating.")
    return text


def build(module_id, normalized, inputs, root):
    """Return a portable bundle. Caller must first obtain an error-free validate."""
    check = validate(module_id, normalized, inputs, root)
    if check["errors"]:
        raise ValueError("TLF setup validation failed: " + "; ".join(e["message"] for e in check["errors"]))
    v = check["normalized"]
    lang = _language(module_id)
    inventory = _inventory(module_id, root)[v["design"]]
    ext = "R" if lang == "r" else "sas"
    data = _canonical_rows(v, inputs)
    files, sources, programs = {}, [], []
    for slot, rows in data.items():
        files[f"{lang}/data/{slot}.csv"] = _csv_text(list(v["columns"][slot]), rows)
    for stem in v["outputs"]:
        item = inventory[stem]
        configured = _configure_source(item["text"], lang, v)
        name = f"programs/{stem}.{ext}"
        files[f"{lang}/{name}"] = configured
        programs.append((name, configured))
        sources.append({"output": stem, "title": item["title"], "status": "configured draft; execution and methods unvalidated", "source": str(item["path"].relative_to(root)), "source_sha256": item["sha256"], "required_columns": item["requirements"], "configured_sha256": hashlib.sha256(configured.encode()).hexdigest()})
    helper_name = "00_setup_helpers.R" if lang == "r" else "00_setup_macros.sas"
    helper = (_library(module_id, root) / helper_name).read_text(encoding="utf-8")
    # The supplied setup adapter is the only entry point; remove example defaults
    # from its unused source setup signature as well to avoid stale study metadata.
    helper = helper.replace('study = "CP-101", adam = "/data/adam", out = "/data/tfl"', 'study = "", adam = "", out = ""')
    files[f"{lang}/{helper_name}"] = helper
    if lang == "r":
        files["r/00_setup.R"] = _r_setup(v)
        files["r/00_run.R"] = _r_driver(v, [name for name, _ in programs])
        files["r/study.Rproj"] = "Version: 1.0\nRestoreWorkspace: No\nSaveWorkspace: No\nAlwaysSaveHistory: No\nEncoding: UTF-8\n"
    else:
        files["sas/00_run.sas"] = _sas_driver(v, data, helper, programs)
    files["template_inventory.json"] = json.dumps({"study": v["study_id"], "design": v["design"], "outputs": sources, "limitations": LIMITATIONS, "helper_sha256": hashlib.sha256((_library(module_id, root) / helper_name).read_bytes()).hexdigest()}, indent=2) + "\n"
    files["README.txt"] = _readme(lang, v)
    return {"files": files, "summary": [f"Generated {len(programs)} configured {lang.upper()} draft programs with canonical CSV data and a fixed driver.", "Source hashes, input contracts, and explicit draft status are included in template_inventory.json."], "limitations": check["warnings"]}


def _r_setup(v):
    lines = ['# Generated setup; all values came from the guided form.', 'source(file.path(bundle_root, "00_setup_helpers.R"), local = TRUE)',
        'guided_setup <- function() setup(study = ' + _r_string(v["study_id"]) + ', adam = file.path(bundle_root, "data"), out = file.path(bundle_root, "draft_results"), meddra = ' + _r_string(v["meddra"] or "Not specified") + ', whodrug = ' + _r_string(v["whodrug"] or "Not specified") + ')', 'adam <- list()']
    for slot, mapping in v["columns"].items():
        lines.append('adam$' + slot + ' <- read.csv(file.path(bundle_root, "data", "' + slot + '.csv"), colClasses = "character", check.names = FALSE, na.strings = "", fileEncoding = "UTF-8")')
        for col in mapping:
            if col in NUMERIC:
                lines.append(f'adam${slot}${col} <- as.numeric(adam${slot}${col})')
            elif col in DATES:
                lines.append(f'adam${slot}${col} <- as.Date(adam${slot}${col}, format = "%Y-%m-%d")')
    lines.append('env <- guided_setup()')
    return "\n".join(lines) + "\n"


def _r_driver(v, names):
    return '''# Open this file in RStudio and click Source. Generated drafts require method/QC review.
local({
  candidates <- unlist(lapply(sys.frames(), function(f) if (!is.null(f$ofile)) f$ofile else NULL))
  own <- candidates[basename(candidates) == "00_run.R"]
  if (!length(own) && requireNamespace("rstudioapi", quietly = TRUE) && rstudioapi::isAvailable()) {
    own <- rstudioapi::getActiveDocumentContext()$path
  }
  if (!length(own) || !file.exists(own[length(own)])) {
    message("Select this generated 00_run.R file in the file picker.")
    own <- file.choose()
  }
  bundle_root <- dirname(normalizePath(own[length(own)], mustWork = TRUE))
  out <- file.path(bundle_root, "draft_results")
  dir.create(out, showWarnings = FALSE)
  selected <- c(''' + ", ".join(_r_string(name) for name in names) + ''')
  for (program in selected) {
    label <- tools::file_path_sans_ext(basename(program))
    unlink(file.path(out, paste0(label, c(".txt", ".pdf", ".rds"))))
  }
  write.csv(data.frame(program = basename(selected), execution = "not run", error = ""),
            file.path(out, "execution_status.csv"), row.names = FALSE)
  source(file.path(bundle_root, "00_setup.R"), local = TRUE)
  status <- list()
  for (program in selected) {
    label <- tools::file_path_sans_ext(basename(program))
    scope <- new.env(parent = environment())
    log <- file(file.path(out, paste0(label, ".txt")), open = "wt")
    grDevices::pdf(file.path(out, paste0(label, ".pdf")))
    sink(log)
    error <- tryCatch({
      sys.source(file.path(bundle_root, program), envir = scope)
      objects <- mget(intersect(c("tab", "rep", "p", "be", "disp", "ae", "pc", "rac_tab", "ss_slope"), ls(scope)), envir = scope)
      saveRDS(objects, file.path(out, paste0(label, ".rds")))
      ""
    }, error = function(e) conditionMessage(e))
    sink(); close(log); grDevices::dev.off()
    status[[length(status) + 1L]] <- data.frame(program = label,
      execution = if (nzchar(error)) "failed" else "executed draft; not validated",
      error = error, stringsAsFactors = FALSE)
  }
  write.csv(do.call(rbind, status), file.path(out, "execution_status.csv"), row.names = FALSE)
  message("Draft run finished. Review draft_results/execution_status.csv and every result before use.")
})
'''


def _sas_driver(v, data, helper, programs):
    lines = ["/* Self-contained generated DRAFT. Open in SAS Studio/Enterprise Guide and click Run.",
        "   Data are staged in WORK; no client paths, macro substitutions from uploaded cells,",
        "   or PROC IMPORT type guessing. Character data use inert hex literals.",
        "   Review the SAS log and draft results. */", helper,
        'data _null_; length staged $1024; staged=dcreate("guided_inputs", pathname("work")); run;',
        'libname adam "%sysfunc(pathname(work))/guided_inputs";', 'libname tfl "%sysfunc(pathname(work))";']
    for slot, rows in data.items():
        cols = list(v["columns"][slot])
        lines.append("data adam." + slot + ";")
        for col in cols:
            if col in NUMERIC or col in DATES:
                lines.append("length " + col + " 8;")
            else:
                length = max([1] + [len(row[col].encode("utf-8")) for row in rows])
                lines.append(f"length {col} ${length};")
        for col in cols:
            if col in DATES:
                lines.append(f"format {col} yymmdd10.;")
        for row in rows:
            for col in cols:
                value = row[col]
                if col in NUMERIC:
                    lines.append(col + "=" + (format(float(value), ".17g") if value.strip() else ".") + ";")
                elif col in DATES:
                    lines.append(col + "=" + ("input('" + value + "',yymmdd10.)" if value else ".") + ";")
                else:
                    encoded = value.encode("utf-8").hex()
                    chunks = [encoded[n:n + 240] for n in range(0, len(encoded), 240)]
                    lines.append(col + "=" + ("\n || ".join("'" + chunk + "'x" for chunk in chunks) if chunks else "''") + ";")
            lines.append("output;")
        if not rows:
            lines.append("stop;")
        lines.append("run;")
    # Hex literals make arbitrary study/dictionary text inert to SAS macro parsing.
    lines += ['libname adam clear;', 'libname adam "%sysfunc(pathname(work))/guided_inputs" access=readonly;', "data _null_;"]
    for name, value in [("STUDYID", v["study_id"]), ("MEDDRAVER", v["meddra"] or "Not specified"), ("WHODRUGVER", v["whodrug"] or "Not specified")]:
        lines.append(f"call symputx('{name}', '{value.encode('utf-8').hex()}'x, 'G');")
    lines += ["run;", "%macro guided_setup;", "options nodate nonumber validvarname=v7;", "%mend;", "ods graphics on;"]
    for name, program in programs:
        lines += ["/* ===== " + name + " — configured draft, review log ===== */", program]
    lines += ["/* WORK datasets are session-local. Save reviewed results through your SAS application's UI. */"]
    return "\n".join(lines) + "\n"


def _readme(lang, v):
    start = ("Double-click r/study.Rproj to open the generated project in RStudio. Open 00_run.R and click Source. If needed, use Tools > Install Packages to install dplyr, tidyr, stringr, purrr, tibble, rtables, ggplot2, emmeans, lme4, broom, broom.mixed, and nlme (concentration–QTc models). The generated driver reads its adjacent data/ folder and writes draft_results/ with a per-output execution_status.csv, text logs, PDF graphics, and RDS objects. An execution error is recorded as failed; an executed draft still requires review."
        if lang == "r" else "Open sas/00_run.sas in SAS Studio or Enterprise Guide and click Run. This self-contained driver includes the data, helpers, and configured source programs; it needs no file-path editing. It stages inputs/results in session-local WORK. Review the SAS log for every error/warning and save reviewed results using your SAS application's interface. SAS software and the procedures used by your selected templates must be available. Source macros and report layouts still include unfinished sections.")
    return ("GUIDED TLF SETUP — CONFIGURED DRAFTS\nStudy: " + v["study_id"] + "\nDesign: " + DESIGNS[v["design"]] + "\n\n" + start + "\n\n" + "\n".join(LIMITATIONS) + "\n\nColumns retain character identifiers; dates are ISO YYYY-MM-DD. Only configured population flags and, for BE outputs, the selected comparison labels are recoded. Other ADaM values and methods remain unchanged. Source program copies are in programs/; template_inventory.json records source hashes and structural input requirements. The generated bundle contains your mapped input records: keep it in the appropriate project storage.\n")
