"""Small Pyodide entry point for the reviewed toolkit QC workspace."""
from __future__ import annotations

import csv
import hashlib
import json
from pathlib import Path

from .browser_validation import ValidationRuntime, source_requirements, validate_source_manifest


BROWSER_RUNNERS = (
    "browser_modules/validation/browser_session.py",
    "browser_modules/workbench/runtime.mjs",
    "browser_modules/workbench/python-worker.mjs",
    "browser_modules/workbench/python-assets.lock.json",
)
_runtime = None
_inventory = None


def initialize(root, inventory, run_r_command, progress=None):
    """Accept only the publication inventory; input data/code uploads are absent."""
    global _runtime, _inventory
    if not isinstance(inventory, dict) or not inventory:
        raise ValueError("The reviewed public source inventory is missing.")
    actual = validate_source_manifest(root, list(inventory))
    if actual != inventory:
        raise ValueError("The extracted toolkit does not match its reviewed source inventory.")
    _runtime = ValidationRuntime(root, run_r_command, required_source_hashes=inventory,
                                 runner_files=BROWSER_RUNNERS, progress=progress)
    _inventory = dict(inventory)
    return information()


def information():
    if _runtime is None:
        raise ValueError("Load the reviewed validation workspace first.")
    registry = _runtime.root / "validation_harness/teeth/defects.csv"
    with registry.open(encoding="utf-8", newline="") as source:
        rows = list(csv.DictReader(source))
    digest = hashlib.sha256(registry.read_bytes()).hexdigest()
    if digest != registry.with_suffix(".sha256").read_text().split()[0]:
        raise ValueError("The defect registry does not match its frozen hash.")
    return {"ok": True, "requirements": source_requirements(), "registry": rows,
            "registry_sha256": digest, "source_files": len(_inventory),
            "scope": "Reviewed toolkit self-test; no uploaded source code or client data is executed.",
            "supports_uploads": False}


async def call(operation, payload):
    if _runtime is None:
        raise ValueError("Load the reviewed validation workspace first.")
    if not isinstance(payload, dict):
        raise ValueError("Expected validation options.")
    allowed = {"only"} if operation == "validation-teeth" else set()
    if set(payload) - allowed:
        raise ValueError("The validation workspace accepts only frozen-registry selection options.")
    if operation == "validation-init":
        return information()
    if operation not in ("validation-harness", "validation-teeth"):
        raise ValueError("Unknown validation operation.")
    try:
        if operation == "validation-harness":
            result = {"ledger": await _runtime.harness()}
        else:
            result = {"summary": await _runtime.teeth(only=payload.get("only", ""))}
        return {"ok": True, **result, "files": _runtime.export_files(), "last_log": _runtime.last_log}
    except Exception as error:
        # Failed and cancelled runs must remain inspectable without looking like
        # completed evidence. Worker termination separately resets the workspace.
        return {"ok": False, "error": str(error), "files": _runtime.export_files(),
                "last_log": _runtime.last_log}
