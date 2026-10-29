"""Client-neutral vaccine study setup and immutable R/SAS analysis packages."""
from __future__ import annotations

import csv
from pathlib import Path
import re
from urllib.parse import urljoin, urlsplit

from .guided_modules import _error, _field, _step, _text, _number, _json, _csv, _sas_data

OUTPUTS = {
    "immunogenicity": ("Geometric titer / concentration summaries", ["participants", "titers"]),
    "fold_rise": ("Paired geometric mean fold rises", ["participants", "titers"]),
    "response": ("Study-defined response rates", ["participants", "titers"]),
    "titer_plot": ("Descriptive response over visits", ["participants", "titers"]),
    "reactogenicity": ("Solicited reactions by dose and symptom", ["participants", "doses", "diary"]),
    "diary_profile": ("Diary completeness and daily profiles", ["participants", "doses", "diary"]),
}
IMMUNO = {"immunogenicity", "fold_rise", "response", "titer_plot"}
REACT = {"reactogenicity", "diary_profile"}
# Required indicates a nonblank value; optional numeric columns may contain blanks.
FEEDS = {
    "participants": [("USUBJID", "text", True), ("ARM", "text", True), ("IMMFL", "flag", True), ("SAFEFL", "flag", True)],
    "titers": [("USUBJID", "text", True), ("ASSAY", "text", True), ("ANTIGEN", "text", True), ("UNIT", "text", True),
               ("VISIT", "text", True), ("AVAL", "number", False), ("QUALIFIER", "qualifier", True),
               ("LLOQ", "number", False), ("ULOQ", "number", False)],
    "doses": [("USUBJID", "text", True), ("DOSE", "text", True)],
    "diary": [("USUBJID", "text", True), ("DOSE", "text", True), ("DAY", "integer", True),
              ("SYMPTOM", "text", True), ("GRADE", "integer", False)],
}
LABELS = {"participants": "Participant populations and treatment arms", "titers": "Assay results by analysis visit",
          "doses": "Actual administered-dose roster", "diary": "Daily solicited-reaction assessments"}


def _options(items):
    return [{"value": value, "label": label} for value, label in items]


def schema(module_id, root):
    if module_id != "vaccine":
        raise ValueError("Unsupported vaccine module")
    inputs = []
    descriptions = {
        "participants": "One row per participant. IMMFL and SAFEFL identify your prespecified immunogenicity and safety populations; neither is inferred from assay or diary availability.",
        "titers": "One selected result per participant, assay, antigen and analysis visit. Map your prespecified visit labels. This module does not assign raw sample dates to visits. Limits may be blank when not applicable.",
        "doses": "One row per actual administered participant/dose. Include recipients with no diary records so missing diaries remain visible.",
        "diary": "One row per participant, dose, day and symptom. Grade 0 explicitly means assessed with no reaction. Blank grades and absent rows remain missing; a header-only diary is allowed.",
    }
    for slot, columns in FEEDS.items():
        inputs.append({"id": slot, "label": LABELS[slot], "description": descriptions[slot],
                       "template_path": f"vaccine/examples/{slot}_template.csv", "example_path": f"vaccine/examples/{slot}.csv",
                       "columns": [{"id": name, "label": name, "type": "number" if kind in {"number", "integer"} else "text", "required": required or name == "GRADE"}
                                   for name, kind, required in columns]})
    return {"title": "Vaccine immunogenicity and reactogenicity", "intro": "Configure descriptive vaccine analyses with your study definitions. R runs locally; SAS reference exports accompany each revision. Examples are synthetic and no client is preselected.",
            "inputs": inputs, "steps": [
        _step("study", "Study and outputs", [
            _field("study_id", "Study identifier", required=True), _field("study_title", "Study / project title"),
            _field("outputs", "Outputs to include", "multiselect", [], options=[{"value": key, "label": label, "inputs": slots} for key, (label, slots) in OUTPUTS.items()]),
            _field("confidence", "Confidence level", "number", .95, min=.5, max=.999, step=.001),
            _field("yes_value", "Population flag: included value", default="Y"),
            _field("no_value", "Population flag: excluded value", default="N")]),
        _step("inputs", "Upload and map inputs", description="Use the blank templates or synthetic examples, or map your own CSV headers. Review the suggested mappings. Only inputs for selected outputs are required."),
        _step("assay", "Assay and analysis visits", [
            _field("assay", "Assay value to analyze"), _field("antigen", "Antigen value to analyze"), _field("unit", "Reported assay unit"),
            _field("baseline_visit", "Baseline analysis-visit label"),
            _field("followup_visits", "Follow-up visit labels, in order (one per line)", "textarea"),
            _field("visits_confirmed", "These visit labels and population flags were assigned according to the study plan", "checkbox", False),
            _field("blq_policy", "Below-LLOQ analysis rule", "select", "exclude", options=_options([
                ("exclude", "Exclude from numerical analyses"), ("half_lloq", "Substitute LLOQ / 2"), ("lloq", "Substitute LLOQ")])),
            _field("alq_policy", "Above-ULOQ analysis rule", "select", "exclude", options=_options([
                ("exclude", "Exclude from numerical analyses"), ("uloq", "Substitute ULOQ")])),
            *[_field("qualifier_" + name.lower(), "Source qualifier meaning " + name, default=name) for name in ("EXACT", "BLQ", "ALQ", "MISSING")],
        ], "Needed for immunogenicity outputs. Select one assay, antigen and unit per revision. Substitution is an explicit study assumption and can affect summaries and response classification; no limit rule is universally correct."),
        _step("response", "Response definition", [
            _field("response_rule", "Study-defined response rule", "select", "threshold", options=_options([
                ("threshold", "Post-baseline value at or above a threshold"),
                ("fold_rise", "Paired fold rise at or above a multiplier"),
                ("conditional", "Baseline-dependent threshold / fold-rise rule")])),
            _field("response_threshold", "Post-baseline response threshold (assay units)", "number", "", min=.000000001, step="any"),
            _field("fold_threshold", "Required fold-rise multiplier", "number", "", min=1.000000001, step="any"),
            _field("baseline_threshold", "Baseline split threshold (assay units)", "number", "", min=.000000001, step="any"),
        ], "Only needed for response-rate outputs. Comparisons are inclusive (≥). Conditional rule: baseline below the split uses the post-baseline threshold; baseline at or above the split uses paired fold rise. These are response definitions, not protection thresholds. All intervals are pointwise and descriptive; no multiplicity adjustment or between-arm hypothesis test is performed."),
        _step("diary", "Solicited reactions and diary window", [
            _field("dose_labels", "Administered dose labels (one per line)", "textarea"),
            _field("symptoms", "Prespecified solicited symptom labels (one per line)", "textarea"),
            _field("day_start", "First diary day, inclusive", "number", 0, min=-1, max=60, step=1),
            _field("day_end", "Last diary day, inclusive", "number", 6, min=-1, max=60, step=1),
            _field("max_grade", "Highest protocol-assigned grade", "number", 4, min=1, max=5, step=1),
            _field("react_denominator", "Reaction incidence denominator", "select", "complete", options=_options([
                ("complete", "Complete window for the symptom"), ("observed", "At least one assessed day (observed reactions)")])),
            _field("diary_confirmed", "I confirmed administered doses, day numbering, symptoms and protocol-assigned grades", "checkbox", False),
        ], "Needed for solicited-reaction outputs. Complete-window incidence excludes partial diaries from that symptom's denominator; their observed reactions remain in the listings. Observed-reaction incidence uses available assessments and may miss reactions on unobserved days. Both policies show dose recipients, incomplete and missing diaries. Grading criteria are supplied by the study; no age-specific thresholds are inferred."),
        _step("review", "Review configuration", [_field("review_confirmed", "I reviewed the settings and their study-specific interpretation", "checkbox", False)]),
    ]}


def _lines(value, field, errors):
    if not isinstance(value, str):
        _error(errors, field, "Enter one label per line.")
        return []
    lines = [s.strip() for s in value.splitlines() if s.strip()]
    if not lines or len(lines) > 50 or len(set(lines)) != len(lines) or any(len(s) > 200 or any(ord(c) < 32 for c in s) for s in lines):
        _error(errors, field, "Use 1–50 distinct, single-line labels of at most 200 characters.")
    return lines


def _read(slot, values, inputs, errors):
    meta = inputs.get(slot, {})
    if not meta.get("absolute_path"):
        _error(errors, "inputs." + slot, "Upload the required CSV input.")
        return []
    try:
        with Path(meta["absolute_path"]).open(encoding="utf-8-sig", newline="") as stream:
            reader = csv.DictReader(stream)
            headers = reader.fieldnames or []
            mapping = values.get("columns", {}).get(slot, {})
            selected = {}
            for name, typ, required in FEEDS[slot]:
                source = mapping.get(name, name if name in headers else "")
                if source and source not in headers:
                    _error(errors, f"columns.{slot}.{name}", "Select an existing source column.")
                elif source:
                    selected[name] = source
                elif required or name == "GRADE":
                    _error(errors, f"columns.{slot}.{name}", "Map this required column.")
            # The two population flags may deliberately use the same source flag.
            reverse = {}
            for key, source in selected.items():
                reverse.setdefault(source, set()).add(key)
            if any(len(keys) > 1 and keys != {"IMMFL", "SAFEFL"} for keys in reverse.values()):
                _error(errors, "columns." + slot, "Use distinct source columns, except when both population flags intentionally share one flag.")
            rows = []
            for line, row in enumerate(reader, 2):
                if line > 100001 or None in row or any(v is None for v in row.values()):
                    raise ValueError("Use at most 100,000 complete CSV records.")
                out = {}
                for name, typ, required in FEEDS[slot]:
                    raw = row.get(selected.get(name), "").strip()
                    field = f"inputs.{slot}.{name}"
                    if not raw:
                        if required:
                            _error(errors, field, f"Row {line}: a value is required.")
                        out[name] = ""
                    elif typ in {"number", "integer"}:
                        out[name] = _number(raw, field, errors, integer=typ == "integer")
                    elif typ == "flag":
                        flags = {values["yes_value"]: "Y", values["no_value"]: "N"}
                        if raw not in flags:
                            _error(errors, field, f"Row {line}: use the configured included or excluded flag.")
                        out[name] = flags.get(raw, "")
                    elif typ == "qualifier":
                        qualifiers = {values["qualifier_" + q.lower()]: q for q in ("EXACT", "BLQ", "ALQ", "MISSING")}
                        if raw not in qualifiers:
                            _error(errors, field, f"Row {line}: use a configured assay qualifier.")
                        out[name] = qualifiers.get(raw, "")
                    else:
                        out[name] = _text(raw, field, errors)
                        if any(ord(c) < 32 for c in raw):
                            _error(errors, field, f"Row {line}: use single-line text without control characters.")
                rows.append(out)
            if not rows and slot not in {"titers", "diary"}:
                _error(errors, "inputs." + slot, "This roster must contain at least one record.")
            return rows
    except (OSError, UnicodeError, csv.Error, ValueError, TypeError) as error:
        _error(errors, "inputs." + slot, "Cannot read CSV: " + str(error))
        return []


def _unique(rows, keys, slot, errors):
    seen = set()
    for row in rows:
        key = tuple(row[k] for k in keys)
        if key in seen:
            _error(errors, "inputs." + slot, "Duplicate " + " + ".join(keys) + ". Resolve the analysis record before continuing.")
            break
        seen.add(key)


def validate(module_id, values, inputs, root):
    spec = schema(module_id, root)
    errors, warnings, summary = [], [], []
    n = {f["id"]: values.get(f["id"], f.get("default", "")) for step in spec["steps"] for f in step["fields"]}
    n["columns"] = values.get("columns", {})
    n["study_id"] = _text(n["study_id"], "study_id", errors, max_length=100)
    n["study_title"] = _text(n["study_title"], "study_title", errors, required=False)
    selected = n["outputs"]
    if not isinstance(selected, list) or not selected or any(not isinstance(k, str) or k not in OUTPUTS for k in selected) or len(set(selected)) != len(selected):
        _error(errors, "outputs", "Select at least one supported output, without duplicates.")
        selected = []
    n["outputs"] = selected
    n["confidence"] = _number(n["confidence"], "confidence", errors, .5, .999)
    for key in ("yes_value", "no_value"):
        n[key] = _text(n[key], key, errors)
    if n["yes_value"] == n["no_value"]:
        _error(errors, "yes_value", "Included and excluded population values must differ.")
    if n["review_confirmed"] is not True:
        _error(errors, "review_confirmed", "Review the settings and confirm the study-specific choices.")
    immune, react = bool(set(selected) & IMMUNO), bool(set(selected) & REACT)
    cfg = dict(n)
    if immune:
        for key in ("assay", "antigen", "unit", "baseline_visit"):
            n[key] = _text(n[key], key, errors)
        visits = _lines(n["followup_visits"], "followup_visits", errors)
        if n["baseline_visit"] in visits:
            _error(errors, "followup_visits", "Baseline must be distinct from follow-up visits.")
        if n["visits_confirmed"] is not True:
            _error(errors, "visits_confirmed", "Confirm the prespecified visit assignment and populations.")
        for key, permitted in (("blq_policy", {"exclude", "half_lloq", "lloq"}), ("alq_policy", {"exclude", "uloq"})):
            if n[key] not in permitted:
                _error(errors, key, "Choose a listed assay-limit rule.")
        qualifier_fields = ["qualifier_" + q.lower() for q in ("EXACT", "BLQ", "ALQ", "MISSING")]
        for key in qualifier_fields:
            n[key] = _text(n[key], key, errors)
        if len({n[key] for key in qualifier_fields}) != 4:
            _error(errors, "qualifier_exact", "Each assay qualifier must have a distinct source value.")
        cfg["followup_visits"] = visits
        if "response" in selected:
            rule = n["response_rule"]
            if rule not in {"threshold", "fold_rise", "conditional"}:
                _error(errors, "response_rule", "Choose a listed response rule.")
            required = (["response_threshold"] if rule == "threshold" else ["fold_threshold"] if rule == "fold_rise" else ["response_threshold", "fold_threshold", "baseline_threshold"])
            for key in required:
                n[key] = _number(n[key], key, errors, 0, 1e100)
                if n[key] <= (1 if key == "fold_threshold" else 0):
                    _error(errors, key, "Enter a value greater than " + ("1." if key == "fold_threshold" else "0."))
    if react:
        for key in ("dose_labels", "symptoms"):
            cfg[key] = _lines(n[key], key, errors)
        for key, lo, hi in (("day_start", -1, 60), ("day_end", -1, 60), ("max_grade", 1, 5)):
            n[key] = _number(n[key], key, errors, lo, hi, integer=True)
        if n["day_end"] < n["day_start"]:
            _error(errors, "day_end", "Last diary day must be at or after the first day.")
        if n["react_denominator"] not in {"complete", "observed"}:
            _error(errors, "react_denominator", "Choose a listed denominator policy.")
        if n["diary_confirmed"] is not True:
            _error(errors, "diary_confirmed", "Confirm administered doses, day numbering, symptoms and grades.")
    needed = {slot for key in selected for slot in OUTPUTS[key][1]}
    data = {slot: _read(slot, n, inputs, errors) for slot in needed}
    participants = data.get("participants", [])
    _unique(participants, ["USUBJID"], "participants", errors)
    if len({row["ARM"] for row in participants}) > 50:
        _error(errors, "inputs.participants.ARM", "This revision supports up to 50 distinct arm labels. Check the ARM mapping.")
    ids = {row["USUBJID"] for row in participants}
    for slot, rows in data.items():
        if any(row["USUBJID"] not in ids for row in rows):
            _error(errors, "inputs." + slot, "Every participant must exist in the population roster.")
    if immune:
        visits = [n["baseline_visit"], *cfg["followup_visits"]]
        rows = [row for row in data.get("titers", []) if row["ASSAY"] == n["assay"] and row["ANTIGEN"] == n["antigen"] and row["VISIT"] in visits]
        _unique(rows, ["USUBJID", "VISIT"], "titers", errors)
        if not any(row["IMMFL"] == "Y" for row in participants):
            _error(errors, "inputs.participants", "No participants are included in the immunogenicity population.")
        expected = sum(row["IMMFL"] == "Y" for row in participants) * len(visits)
        if expected > 1000000:
            _error(errors, "followup_visits", "This expected participant/visit grid exceeds 1,000,000 observations. Select fewer follow-up visits per revision while retaining the full eligible population.")
        for row in rows:
            if row["UNIT"] != n["unit"]:
                _error(errors, "inputs.titers.UNIT", "Selected assay/antigen/visit records must all use the configured unit; convert units before analysis.")
                break
        for row in data.get("titers", []):
            value, lo, hi, qualifier = (row[k] for k in ("AVAL", "LLOQ", "ULOQ", "QUALIFIER"))
            if any(x != "" and x <= 0 for x in (value, lo, hi)) or lo != "" and hi != "" and lo >= hi:
                _error(errors, "inputs.titers", "Assay values and limits must be positive, with LLOQ < ULOQ when both limits are supplied.")
            if qualifier == "EXACT" and (value == "" or lo != "" and value < lo or hi != "" and value > hi):
                _error(errors, "inputs.titers.AVAL", "EXACT requires a positive value inside its supplied quantification limits.")
            if qualifier == "BLQ" and lo == "" or qualifier == "ALQ" and hi == "":
                _error(errors, "inputs.titers", "BLQ requires LLOQ and ALQ requires ULOQ, even when excluded.")
            if qualifier in {"BLQ", "ALQ", "MISSING"} and value != "":
                _error(errors, "inputs.titers.AVAL", "Leave AVAL blank for BLQ, ALQ and MISSING; the chosen limit rule derives the analysis value.")
        summary += [f"Assay: {n['assay']} · antigen: {n['antigen']} · unit: {n['unit']}", f"Visits: {' → '.join(visits)}; {len(rows)} selected assay records.", f"BLQ rule: {n['blq_policy']}; ALQ rule: {n['alq_policy']}."]
        warnings.append("Geometric summaries and paired fold rises use natural logs and pointwise t intervals; a single evaluable participant has no interval. Response intervals are exact Clopper–Pearson. No between-arm tests, multiplicity adjustment or protective threshold is supplied.")
    if react:
        doses, diary = data.get("doses", []), data.get("diary", [])
        _unique(doses, ["USUBJID", "DOSE"], "doses", errors)
        _unique(diary, ["USUBJID", "DOSE", "DAY", "SYMPTOM"], "diary", errors)
        roster = {(row["USUBJID"], row["DOSE"]) for row in doses}
        if any((row["USUBJID"], row["DOSE"]) not in roster for row in diary):
            _error(errors, "inputs.diary", "Every diary participant/dose must exist in the actual administered-dose roster.")
        if any(row["GRADE"] != "" and not 0 <= row["GRADE"] <= n["max_grade"] for row in diary):
            _error(errors, "inputs.diary.GRADE", "Grades must be integers from 0 through the configured maximum, or blank for missing.")
        safety = {row["USUBJID"] for row in participants if row["SAFEFL"] == "Y"}
        if not any(row["USUBJID"] in safety and row["DOSE"] in cfg["dose_labels"] for row in doses):
            _error(errors, "inputs.doses", "No safety-population recipients have a selected administered dose.")
        expected = sum(row["USUBJID"] in safety and row["DOSE"] in cfg["dose_labels"] for row in doses) * len(cfg["symptoms"]) * max(0, n["day_end"] - n["day_start"] + 1)
        if expected > 1000000:
            _error(errors, "symptoms", "This expected diary grid exceeds 1,000,000 assessments. Select fewer doses or symptoms per revision while retaining the prespecified window and population.")
        summary += [f"Diary window: day {n['day_start']} through {n['day_end']}, inclusive; {expected} expected assessments.", f"Reaction denominator: {n['react_denominator']}; protocol grades 0–{n['max_grade']}."]
        warnings.append("Missing diary rows and blank grades are not grade 0. Complete-window analyses exclude partial diaries from that symptom's incidence denominator; available-diary analyses describe observed reactions and can miss reactions on unobserved days. Review both population and completeness counts.")
    summary.insert(0, f"Study {n['study_id']}: {len(selected)} selected outputs; {len(participants)} participants in the supplied roster.")
    warnings.append("Descriptive analyses only. Methods and data require study-specific scientific review. SAS exports are unexecuted reference programs; completion never grants study approval.")
    cfg = {**n, **{key: cfg[key] for key in ("followup_visits", "dose_labels", "symptoms") if isinstance(cfg.get(key), list)}}
    return {"errors": errors, "warnings": warnings, "summary": summary, "normalized": n, "config": cfg, "data": data}


def build(module_id, normalized, inputs, root):
    report = validate(module_id, normalized, inputs, root)
    if report["errors"]:
        raise ValueError("Invalid vaccine setup: " + "; ".join(item["message"] for item in report["errors"]))
    cfg, data = report["config"], report["data"]
    files = {"study_setup.json": _json(cfg), "R/vaccine_analysis.R": (Path(root) / "vaccine/analysis.R").read_text(encoding="utf-8")}
    sas = ["/* Generated vaccine analysis reference. Native SAS has NOT been executed or reconciled. */\noptions validvarname=v7;\n"]
    for slot, columns in FEEDS.items():
        rows = data.get(slot, [])
        files[f"inputs/{slot}.csv"] = _csv(rows, [c[0] for c in columns])
        sas.append(_sas_data(slot, rows, [(name, "number" if typ in {"number", "integer"} else "text", required) for name, typ, required in columns]))
    numeric = {"confidence", "response_threshold", "fold_threshold", "baseline_threshold", "day_start", "day_end", "max_grade"}
    config_keys = [key for key in cfg if key != "columns" and not isinstance(cfg[key], (dict, list, bool))]
    sas.append(_sas_data("vax_config", [{key: cfg[key] for key in config_keys}], [(key, "number" if key in numeric else "text", False) for key in config_keys]))
    for name, field, key in (("vax_visits", "VISIT", "followup_visits"), ("vax_doses", "DOSE", "dose_labels"), ("vax_symptoms", "SYMPTOM", "symptoms"), ("vax_outputs", "ID", "outputs")):
        labels = cfg.get(key, [])
        labels = labels if isinstance(labels, list) else []
        if name == "vax_visits" and set(cfg["outputs"]) & IMMUNO:
            labels = [cfg["baseline_visit"], *labels]
        sas.append(_sas_data(name, [{field: label, "ORDER": i} for i, label in enumerate(labels)], [(field, "text", True), ("ORDER", "number", True)]))
    sas.append((Path(root) / "vaccine/reference.sas").read_text(encoding="utf-8"))
    files["vaccine_analysis.sas"] = "\n".join(sas)
    files["START_HERE.txt"] = "Return to this revision in the toolkit and click Check, Install packages if needed, then Run analysis. Each attempt has a separate report and results ZIP. R analyses execute locally with the configured data. The SAS file embeds canonical inputs and settings using inert literals and is an unexecuted reference export. No scientific approval is issued. Keep the input manifest, source fingerprints, settings and results together.\n"
    files["METHODS.txt"] = "\n".join(report["summary"] + report["warnings"]) + "\n"
    for name in ("REFERENCES.md", "README.md"):
        path = Path(root) / "vaccine" / name
        if path.is_file():
            # A generated revision contains code/data, not the public website's
            # page and asset tree. Its reading links must still resolve after ZIP extraction.
            content = path.read_text(encoding="utf-8")
            def public_link(match):
                target = match.group(1)
                return "](" + (target if urlsplit(target).scheme or target.startswith("#") else urljoin("https://patrickiben.github.io/biometrics-ai-portfolio/vaccine/", target)) + ")"
            files[name] = re.sub(r"\]\(([^)]+)\)", public_link, content)
    return {"files": files, "summary": ["R analysis package and configured native SAS reference export prepared."], "limitations": report["warnings"]}
