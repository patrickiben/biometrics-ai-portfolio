import json
from pathlib import Path
import shutil
import time

from toolkit_launcher.runtime import ROOT


def make_source(destination):
    source = Path(destination)
    source.mkdir()
    catalog = {"schema": 1, "modules": [{"id": "risk", "title": "Risk", "inputs": [
        {"path": "risk_monitor/shiny/data/signals.csv"}], "actions": []}]}
    (source / "toolkit_launcher").mkdir()
    (source / "toolkit_launcher/catalog.json").write_text(json.dumps(catalog))
    required = ["launch_app.R", "sim_lifecycle/run_lifecycle.R", "sim_lifecycle/simulate_adam.R", "sim_lifecycle/priors.R",
                "toolkit_launcher/stub_profile.R", "risk_monitor/shiny/data/signals.csv"]
    required += [p.relative_to(ROOT).as_posix() for p in (ROOT / "tlf_interpret/R").glob("*.R")]
    required += ["tlf_interpret/selftest.R"]
    for relative in required:
        output = source / relative
        output.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / relative, output)
    inventory = required + ["toolkit_launcher/catalog.json"]
    (source / "toolkit_launcher/source_manifest.json").write_text(json.dumps({"schema": 1, "files": inventory}))
    # This local-only material must not enter a copied project or ZIP.
    (source / "private-not-in-manifest.txt").write_text("DO NOT COPY")
    return source


def wait_for_job(workspace, ident, timeout=45):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        state = workspace.job_state(ident)
        if state["status"] != "running":
            return state
        time.sleep(0.03)
    raise AssertionError("The job did not finish: " + workspace.job_state(ident).get("log", ""))
