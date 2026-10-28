"""Private, versioned template setup. Generating a package never executes it."""
from __future__ import annotations

import base64
import binascii
import csv
import hashlib
import html
import io
import json
import math
from pathlib import Path
import re
import secrets
import shutil
import tempfile
import zipfile

from .runtime import InputError, MAX_FILE, ROOT, atomic_json, safe_path, timestamp

MODULES = {"r_tlf", "sas_tlf", "sas_monitor", "localmind", "interpretation"}
MAX_ROWS = 100000
SOURCE_DIRS = {"r_tlf": "r_tlf_pseudocode", "sas_tlf": "sas_tlf_pseudocode",
               "sas_monitor": "sas_r_automation/macro_library", "localmind": "slm_wiki/macro_library",
               "interpretation": "tlf_interpret"}


def provider(module_id):
    if not isinstance(module_id, str) or module_id not in MODULES:
        raise InputError("Choose a supported template module.")
    if module_id in {"r_tlf", "sas_tlf"}:
        from . import guided_tlf
        return guided_tlf
    from . import guided_modules
    return guided_modules


def schema(root, module_id):
    selected = provider(module_id)
    directory = safe_path(root, SOURCE_DIRS[module_id], exists=False)
    # Providers read source templates for inventory and generated copies. Check
    # their whole directory before those reads, including linked subdirectories.
    for path in directory.rglob("*"):
        if path.is_symlink():
            raise InputError("Template sources must be regular files inside this project.")
    return selected.schema(module_id, root)


def fields(spec):
    return {f["id"]: f for step in spec["steps"] for f in step.get("fields", [])}


def private_dir(root, relative):
    path = safe_path(root, relative, exists=False)
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    return path


def bounded_json(root, relative, default):
    path = safe_path(root, relative, exists=False)
    if not path.exists():
        return default
    if not path.is_file() or path.stat().st_size > 1024 * 1024:
        raise InputError("This saved setup record is unavailable.")
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (ValueError, UnicodeError):
        raise InputError("This saved setup record cannot be read.") from None


def clean_values(spec, values):
    """Validate the shape of draft values, without requiring a complete study."""
    defined = fields(spec)
    if not isinstance(values, dict) or set(values) - set(defined) - {"columns"}:
        raise InputError("The setup contains an unknown field.")
    result = {key: field.get("default", [] if field["type"] in {"multiselect", "template-select"} else False if field["type"] == "checkbox" else "")
              for key, field in defined.items()}
    for key, value in values.items():
        if key == "columns":
            continue
        kind = defined[key]["type"]
        if kind == "checkbox":
            valid = type(value) is bool
        elif kind == "number":
            valid = value == "" or type(value) in {int, float} and math.isfinite(value)
        elif kind in {"multiselect", "template-select"}:
            valid = isinstance(value, list) and len(value) <= 500 and all(isinstance(v, str) and len(v) <= 200 for v in value)
            if valid:
                value = list(dict.fromkeys(value))
        else:
            valid = isinstance(value, str) and len(value) <= (20000 if kind == "textarea" else 2000)
        if not valid or isinstance(value, str) and any(ord(c) < 32 and c not in "\n\t\r" for c in value):
            raise InputError("Check the value for " + defined[key]["label"] + ".")
        result[key] = value
    maps = values.get("columns", {})
    slots = {item["id"]: item for item in spec.get("inputs", [])}
    if not isinstance(maps, dict) or set(maps) - set(slots):
        raise InputError("Choose a listed input dataset for column mapping.")
    result["columns"] = {}
    for slot, mapping in maps.items():
        targets = {col["id"] for col in slots[slot].get("columns", [])}
        if not isinstance(mapping, dict) or set(mapping) - targets or any(not isinstance(v, str) or len(v) > 200 for v in mapping.values()):
            raise InputError("Choose the listed target columns for " + slots[slot]["label"] + ".")
        result["columns"][slot] = dict(mapping)
    if len(json.dumps(result).encode()) > 256000:
        raise InputError("This setup profile is too large.")
    return result


def csv_metadata(path, relative, filename=None):
    if not path.is_file() or path.stat().st_size > MAX_FILE:
        raise InputError("Choose a CSV file smaller than 16 MB.")
    content = path.read_bytes()
    if len(content) > MAX_FILE:
        raise InputError("Choose a CSV file smaller than 16 MB.")
    try:
        text = content.decode("utf-8-sig")
        if not text or "\x00" in text:
            raise ValueError()
        reader = csv.reader(io.StringIO(text), strict=True)
        columns = next(reader)
        if (not columns or len(columns) > 256 or len(columns) != len(set(columns))
                or any(not c.strip() or c != c.strip() or len(c) > 200 or any(ord(v) < 32 for v in c)
                       or c.lower() in {"__proto__", "constructor", "prototype"} for c in columns)):
            raise ValueError()
        preview, count = [], 0
        for row in reader:
            if len(row) != len(columns) or any(len(cell) > 65536 for cell in row):
                raise ValueError()
            count += 1
            if count > MAX_ROWS:
                raise InputError("Choose a CSV with at most 100,000 rows.")
            if len(preview) < 3:
                preview.append(dict(zip(columns, row)))
    except (UnicodeError, csv.Error, StopIteration, ValueError) as error:
        if isinstance(error, InputError):
            raise
        raise InputError("Use a UTF-8 CSV with unique, nonblank headers and the same number of cells in every row.") from None
    return {"path": relative, "absolute_path": path, "filename": filename or path.name,
            "columns": columns, "rows": count, "size": len(content), "sha256": hashlib.sha256(content).hexdigest(), "preview": preview}


def input_records(root, module_id, spec):
    records = {}
    for slot in spec.get("inputs", []):
        relative = f"template_inputs/{module_id}/{slot['id']}.csv"
        path = safe_path(root, relative, exists=False)
        if path.exists():
            record = bounded_json(root, f"template_inputs/{module_id}/{slot['id']}.json", {})
            records[slot["id"]] = csv_metadata(path, relative, record.get("filename"))
    return records


def public_inputs(records):
    return {slot: {key: value for key, value in record.items() if key != "absolute_path"} for slot, record in records.items()}


def profile_path(module_id):
    return f"toolkit_configuration/{module_id}.guided.json"


def state(root, module_id):
    spec = schema(root, module_id)
    saved = bounded_json(root, profile_path(module_id), {})
    values = clean_values(spec, saved.get("values", {}))
    records = input_records(root, module_id, spec)
    build_list = bounded_json(root, f"toolkit_configuration/{module_id}.builds.json", [])
    if not isinstance(build_list, list):
        raise InputError("The generated-package history cannot be read.")
    return {"schema": spec, "values": values, "inputs": public_inputs(records), "builds": build_list[:30],
            "profile_path": profile_path(module_id) if saved else None}


def upload(root, module_id, slot_id, filename, encoded):
    spec = schema(root, module_id)
    slots = {slot["id"] for slot in spec.get("inputs", [])}
    if not isinstance(slot_id, str) or slot_id not in slots or not isinstance(filename, str) or not filename.lower().endswith(".csv"):
        raise InputError("Choose a CSV for one of this module's listed inputs.")
    if not isinstance(encoded, str) or len(encoded) > MAX_FILE * 1.4:
        raise InputError("Choose a CSV file smaller than 16 MB.")
    try:
        content = base64.b64decode(encoded, validate=True)
    except (binascii.Error, ValueError):
        raise InputError("The CSV upload could not be read.") from None
    directory = private_dir(root, f"template_inputs/{module_id}")
    target = safe_path(root, f"template_inputs/{module_id}/{slot_id}.csv", exists=False)
    handle, pending = tempfile.mkstemp(prefix=".input-", dir=directory)
    import os
    try:
        with os.fdopen(handle, "wb") as stream:
            stream.write(content)
        metadata = csv_metadata(Path(pending), target.relative_to(root).as_posix(), Path(filename.replace("\\", "/")).name[:200])
        total = sum(p.stat().st_size for p in directory.glob("*.csv") if p != target and not p.is_symlink())
        if total + len(content) > 64 * 1024 * 1024:
            raise InputError("Keep this module's uploaded inputs below 64 MB in total.")
        if target.exists():
            backup = root.parent / "input-backups"
            if backup.is_symlink():
                raise InputError("Input backups must use a regular private folder.")
            backup.mkdir(mode=0o700, exist_ok=True)
            shutil.copyfile(target, backup / f"guided-{module_id}-{slot_id}-{secrets.token_hex(8)}.csv")
        Path(pending).replace(target)
        atomic_json(directory / (slot_id + ".json"), {"filename": metadata["filename"], "uploaded_at": timestamp()})
        preview = safe_path(root, f"toolkit_configuration/{module_id}.preview.json", exists=False)
        preview.unlink(missing_ok=True)
    finally:
        Path(pending).unlink(missing_ok=True)
    records = input_records(root, module_id, spec)
    return {"input": public_inputs({slot_id: records[slot_id]})[slot_id], "inputs": public_inputs(records)}


def source_hashes(root, module_id):
    directory = safe_path(root, SOURCE_DIRS[module_id], exists=False)
    result = {}
    for path in sorted(directory.rglob("*")):
        if path.suffix.lower() in {".r", ".sas", ".qmd"}:
            relative = path.relative_to(root).as_posix()
            checked = safe_path(root, relative)
            result[relative] = hashlib.sha256(checked.read_bytes()).hexdigest()
    return result


def digest(values, inputs, sources):
    data = {"values": values, "inputs": {slot: item["sha256"] for slot, item in inputs.items()}, "sources": sources}
    return hashlib.sha256(json.dumps(data, sort_keys=True, ensure_ascii=False, allow_nan=False).encode()).hexdigest()


def readiness_html(module_id, values, report, inputs, sources, limitations):
    esc = lambda value: html.escape(str(value), quote=True)
    theme = (ROOT / "assets/theme/tokens.css").read_text(encoding="utf-8")
    summaries = "".join("<li>" + esc(s) + "</li>" for s in report.get("summary", []))
    warnings = "".join("<li>" + esc(s) + "</li>" for s in report.get("warnings", []) + limitations)
    rows = "".join(f"<tr><th>{esc(slot)}</th><td>{esc(item['filename'])}</td><td>{item['rows']}</td><td><code>{esc(item['sha256'])}</code></td></tr>" for slot, item in inputs.items())
    settings = esc(json.dumps(values, indent=2, ensure_ascii=False))
    return f'''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Study setup review</title><style>{theme}
body{{margin:0;background:var(--bg);color:var(--text);font:16px/1.6 system-ui,sans-serif}}main{{max-width:1050px;margin:auto;padding:28px}}button{{padding:10px;background:var(--surface);color:var(--text);border:1px solid var(--line);border-radius:6px}}.table{{overflow:auto}}table{{border-collapse:collapse;width:100%}}th,td{{border:1px solid var(--line);padding:8px;text-align:left}}code,pre{{overflow-wrap:anywhere;white-space:pre-wrap}}.note{{padding:16px;border:1px solid var(--line);background:var(--surface)}}h1{{line-height:1.15}}</style>
<main><button class="theme-toggle" type="button">Light / dark</button><p>TRIAL BIOSTATISTICS TOOLKIT · PRIVATE PROJECT</p><h1>Study setup review</h1><p>{esc(module_id)} · {esc(values.get('study_id', 'Study project'))}</p><p class="note">Configuration generated. No analysis program, model, email service or external system was executed. Configuration completeness is separate from statistical validation and study approval.</p><h2>Prepared setup</h2><ul>{summaries}</ul><h2>Review before use</h2><ul>{warnings}</ul><h2>Input provenance</h2><div class="table"><table><tr><th>Input</th><th>File</th><th>Rows</th><th>SHA-256</th></tr>{rows}</table></div><h2>Saved choices</h2><pre>{settings}</pre><p>Full source fingerprints and the reusable setup profile accompany this report.</p></main>
<script>(()=>{{let t;try{{t=localStorage.getItem('bp-theme')}}catch(e){{}}document.documentElement.dataset.theme=t||'light';document.querySelector('button').onclick=()=>{{const n=document.documentElement.dataset.theme==='dark'?'light':'dark';document.documentElement.dataset.theme=n;try{{localStorage.setItem('bp-theme',n)}}catch(e){{}}}}}})();</script></html>'''


def act(root, module_id, action, values):
    if not isinstance(action, str) or action not in {"save", "validate", "generate"}:
        raise InputError("Choose Save, Preview or Generate in the guided setup.")
    spec = schema(root, module_id)
    values = clean_values(spec, values)
    directory = private_dir(root, "toolkit_configuration")
    profile = {"schema": 1, "module_id": module_id, "values": values}
    if action == "save":
        atomic_json(directory / (module_id + ".guided.json"), profile)
        return {"values": values, "profile_path": profile_path(module_id), "report": {"errors": [], "warnings": [], "summary": ["Setup draft saved. Preview it before generating a package."]}}
    inputs = input_records(root, module_id, spec)
    report = provider(module_id).validate(module_id, values, inputs, root)
    values = clean_values(spec, report.get("normalized", values))
    report = {**{key: report.get(key, []) for key in ("errors", "warnings", "summary")}, **({"preview": report["preview"]} if "preview" in report else {})}
    if report["errors"]:
        return {"values": values, "report": report}
    sources = source_hashes(root, module_id)
    current = digest(values, inputs, sources)
    if action == "validate":
        atomic_json(directory / (module_id + ".preview.json"), {"digest": current})
        return {"values": values, "report": report}
    previous = bounded_json(root, f"toolkit_configuration/{module_id}.preview.json", {})
    if previous.get("digest") != current:
        report["errors"] = [{"field": "preview", "message": "Preview the current settings and inputs before generating this package."}]
        return {"values": values, "report": report}
    try:
        generated = provider(module_id).build(module_id, values, inputs, root)
    except ValueError as error:
        raise InputError(str(error)) from None
    files = generated["files"]
    if not isinstance(files, dict) or not files or len(files) > 1200:
        raise InputError("The generated package is incomplete or too large.")
    limitations = generated.get("limitations", [])
    report["summary"] = list(dict.fromkeys(report["summary"] + generated.get("summary", [])))
    profile["values"] = values
    files = dict(files)
    files["setup_profile.json"] = json.dumps(profile, indent=2, ensure_ascii=False) + "\n"
    files["input_manifest.json"] = json.dumps({slot: {key: value for key, value in record.items() if key not in {"absolute_path", "preview"}} for slot, record in inputs.items()}, indent=2, ensure_ascii=False) + "\n"
    files["source_fingerprints.json"] = json.dumps(sources, indent=2) + "\n"
    files["SETUP_REPORT.html"] = readiness_html(module_id, values, report, inputs, sources, limitations)
    parent = private_dir(root, f"template_outputs/{module_id}")
    revision = "setup-" + secrets.token_hex(12)
    stage = Path(tempfile.mkdtemp(prefix=".stage-", dir=parent))
    final = parent / revision
    try:
        total = 0
        for relative, content in files.items():
            if not isinstance(relative, str) or not isinstance(content, (str, bytes)):
                raise InputError("The generated package contains an invalid file.")
            target = safe_path(stage, relative, exists=False)
            if target.suffix.lower() not in {".csv", ".json", ".html", ".r", ".sas", ".qmd", ".txt", ".md", ".yml", ".yaml", ".css", ".rproj"}:
                raise InputError("The generated package contains an unsupported file type.")
            data = content.encode("utf-8") if isinstance(content, str) else content
            total += len(data)
            if total > 128 * 1024 * 1024:
                raise InputError("The generated package exceeds 128 MB. Select fewer outputs or smaller inputs.")
            target.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
            with target.open("xb") as stream:
                stream.write(data)
            target.chmod(0o600)
        with zipfile.ZipFile(stage / "study-setup.zip", "w", zipfile.ZIP_DEFLATED) as archive:
            for path in sorted(stage.rglob("*")):
                if path.is_file() and path.name != "study-setup.zip":
                    archive.write(path, path.relative_to(stage).as_posix())
        stage.replace(final)
        prefix = final.relative_to(root).as_posix()
        build = {"status": "configured", "created_at": timestamp(), "module_id": module_id,
                 "paths": [prefix + "/" + name for name in files], "zip_path": prefix + "/study-setup.zip",
                 "report_path": prefix + "/SETUP_REPORT.html", "profile_path": prefix + "/setup_profile.json", "digest": current}
        history_path = f"toolkit_configuration/{module_id}.builds.json"
        history = bounded_json(root, history_path, [])
        if not isinstance(history, list):
            raise InputError("The package history cannot be read.")
        atomic_json(root / history_path, [build, *history][:30])
        atomic_json(directory / (module_id + ".guided.json"), profile)
        return {"values": values, "report": report, "build": build, "profile_path": profile_path(module_id)}
    finally:
        if stage.exists():
            shutil.rmtree(stage)


def import_profile(root, module_id, profile):
    if not isinstance(profile, dict) or set(profile) != {"schema", "module_id", "values"} or profile.get("schema") != 1 or profile.get("module_id") != module_id:
        raise InputError("Choose a setup profile exported for this module.")
    return act(root, module_id, "save", profile["values"])
