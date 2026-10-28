"""Generate and execute every R-backed template through both point-and-click entry points."""
from __future__ import annotations

import csv
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from toolkit_launcher import guided_tlf as tlf

DESIGNS = ("parallel", "crossover", "single_sequence", "sad", "mad")
PACKAGES = ("jsonlite", "dplyr", "tidyr", "stringr", "purrr", "tibble", "rtables", "ggplot2", "emmeans", "lme4", "lmerTest", "nlme", "broom", "broom.mixed", "ggrepel")


class GeneratedAnalysisTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not shutil.which("Rscript"):
            raise unittest.SkipTest("Rscript is not installed")
        expression = "p<-c(" + ",".join(json.dumps(x) for x in PACKAGES) + ");quit(status=if(all(vapply(p,requireNamespace,logical(1),quietly=TRUE)))0 else 42)"
        probe = subprocess.run(["Rscript", "-e", expression], capture_output=True, text=True, timeout=60)
        if probe.returncode == 42:
            raise unittest.SkipTest("Analysis dependencies are not installed; no packages downloaded")
        if probe.returncode:
            raise AssertionError(probe.stderr)
        cls.temp = tempfile.TemporaryDirectory(prefix="generated analysis QC ")
        cls.addClassCleanup(cls.temp.cleanup)
        cls.folder = Path(cls.temp.name)
        script = cls.folder / "fixtures.R"
        script.write_text(r'''
source("toolkit_launcher/tests/analysis_fixtures.R")
root <- commandArgs(trailingOnly=TRUE)[1]
for(design in c("parallel","crossover","single_sequence","sad","mad")) {
 d<-analysis_fixture(design); path<-file.path(root,design);dir.create(path,recursive=TRUE)
 for(slot in names(d))write.csv(d[[slot]],file.path(path,paste0(slot,".csv")),row.names=FALSE,na="",fileEncoding="UTF-8")
}
''', encoding="utf-8")
        result = subprocess.run(["Rscript", str(script), str(cls.folder / "fixtures")], cwd=ROOT, capture_output=True, text=True, timeout=60)
        if result.returncode:
            raise AssertionError(result.stdout + result.stderr)
        cls.evidence = []

    def values(self, design, outputs):
        return {"study_id": "SYNTHETIC-QC", "design": design, "outputs": outputs, "reviewed": True,
                "meddra": "Synthetic coding labels", "whodrug": "Synthetic coding labels",
                "dose_map": "Placebo=0\nDose 10=10\nDose 20=20\nDose 40=40" if design in {"sad", "mad"} else "Placebo=0\nReference=10\nTest=10",
                "dose_unit": "mg", "placebo_label": "Placebo", "profile_days": "1, 14" if design == "mad" else "1",
                "analysis_day": 14 if design == "mad" else 1, "accumulation_auc_comparable": True}

    def inputs(self, design):
        return {path.stem: {"absolute_path": path, "path": f"private/{design}/{path.name}"} for path in (self.folder / "fixtures" / design).glob("*.csv")}

    def build(self, module, design, outputs, name):
        values = self.values(design, outputs)
        report = tlf.validate(module, values, self.inputs(design), ROOT)
        self.assertEqual(report["errors"], [], f"{module}/{design}: {report['errors']}")
        generated = tlf.build(module, report["normalized"], self.inputs(design), ROOT)
        bundle = self.folder / name
        bundle.mkdir()
        for filename, content in generated["files"].items():
            target = bundle / filename
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(content, encoding="utf-8")
        self.assertTrue((bundle / "r/01_analysis_models.R").is_file())
        self.assertTrue((bundle / "sas/00_run.sas").is_file())
        inventory = json.loads((bundle / "template_inventory.json").read_text(encoding="utf-8"))
        self.assertEqual(inventory["engine"], "r")
        self.assertFalse(inventory["approved"])
        self.assertTrue(all("unexecuted" in item["sas_reference"]["status"] for item in inventory["outputs"]))
        return bundle

    def hashes(self, folder):
        return {path.relative_to(folder).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest() for path in folder.rglob("*") if path.is_file()}

    def run_bundle(self, bundle, module, name, should_pass=True):
        run = self.folder / name
        run.mkdir()
        plan = {"schema": 1, "module_id": module, "build_root": str(bundle), "run_root": str(run),
                "source_root": str(bundle), "build_id": bundle.name, "run_id": name,
                "bundle_sha256": "integration-fixture", "engine_sha256": "integration-fixture", "approved": False}
        path = run / "plan.json"
        path.write_text(json.dumps(plan), encoding="utf-8")
        before = self.hashes(bundle)
        result = subprocess.run(["Rscript", "--vanilla", str(bundle / "toolkit_launcher/analysis_runner.R"), str(path)], cwd=self.folder, capture_output=True, text=True, timeout=300)
        diagnostics = (run / "qc.json").read_text(encoding="utf-8") if (run / "qc.json").exists() else result.stderr
        self.assertEqual(result.returncode, 0 if should_pass else 1, diagnostics + "\n" + result.stdout + result.stderr)
        self.assertEqual(self.hashes(bundle), before, "Analysis must not mutate the generated input revision")
        for filename in ("analysis_report.html", "qc.json", "output_manifest.json", "execution_status.csv", "software_versions.csv"):
            self.assertGreater((run / filename).stat().st_size, 0)
        qc = json.loads((run / "qc.json").read_text(encoding="utf-8"))
        manifest = json.loads((run / "output_manifest.json").read_text(encoding="utf-8"))
        self.assertEqual(qc["passed"], should_pass)
        self.assertFalse(qc["approved"])
        self.assertFalse(manifest["approved"])
        self.assertIn("theme-toggle", (run / "analysis_report.html").read_text(encoding="utf-8"))
        for output in manifest["outputs"]:
            self.assertEqual(output["status"], "completed" if should_pass else "failed")
            self.assertTrue(output["files"])
            for filename in output["files"]:
                artifact = run / filename
                self.assertTrue(artifact.resolve().is_relative_to(run.resolve()))
                self.assertTrue(artifact.is_file(), filename)
                if artifact.name != "program.log":
                    self.assertGreater(artifact.stat().st_size, 0, filename)
            page = (run / "outputs" / output["id"] / "index.html").read_text(encoding="utf-8")
            self.assertIn("theme-toggle", page)
        self.evidence.append({"module": module, "bundle": bundle.name, "run": run.name, "outputs": len(manifest["outputs"]), "passed": should_pass})
        evidence = os.environ.get("ANALYSIS_GENERATED_REPORT")
        if evidence:
            Path(evidence).write_text(json.dumps(self.evidence, indent=2), encoding="utf-8")
        return run, manifest

    def test_all_221_outputs_execute_from_each_entry_point(self):
        total = 0
        for module in ("r_tlf", "sas_tlf"):
            for design in DESIGNS:
                with self.subTest(module=module, design=design):
                    selected = sorted(path.stem for path in (ROOT / "r_tlf_pseudocode" / design).glob("*.R"))
                    bundle = self.build(module, design, selected, f"bundle-{module}-{design}")
                    run, manifest = self.run_bundle(bundle, module, f"run-{module}-{design}")
                    self.assertEqual({item["id"] for item in manifest["outputs"]}, set(selected))
                    # The PD listing must preserve every participant/time record,
                    # including rows beyond the overview's 100-row display limit.
                    expected_rows = 24 * 5 * (4 if design == "mad" else 2 if design in {"crossover", "single_sequence"} else 1)
                    csv_path = run / "outputs/l_pd/component-01.csv"
                    with csv_path.open(newline="", encoding="utf-8") as handle:
                        records = list(csv.DictReader(handle))
                    self.assertEqual(len(records), expected_rows)
                    complete = (run / "outputs/l_pd/component-01-page-001.html").read_text(encoding="utf-8")
                    self.assertEqual(complete.count("<tr>"), expected_rows + 1)
                    self.assertIn("P024", complete)
                    total += len(selected)
        self.assertEqual(total, 442)

    def test_repeated_runs_are_separate_and_invalid_analysis_has_no_partial_output(self):
        bundle = self.build("r_tlf", "parallel", ["t_pk_param_summary"], "bundle-repeat")
        first, _ = self.run_bundle(bundle, "r_tlf", "run-repeat-one")
        before = self.hashes(first)
        second, _ = self.run_bundle(bundle, "r_tlf", "run-repeat-two")
        self.assertNotEqual(first, second)
        self.assertEqual(self.hashes(first), before, "A new run must leave prior results untouched")
        # A malformed duplicate analysis row is rejected by the actual numerical
        # source, and the renderer must remove partial numerical artifacts.
        bad_bundle = self.folder / "bundle-duplicate"
        shutil.copytree(bundle, bad_bundle)
        path = bad_bundle / "r/data/adpp.csv"
        with path.open(newline="", encoding="utf-8") as handle:
            reader = csv.DictReader(handle); columns = reader.fieldnames; rows = list(reader)
        rows.append(dict(rows[0]))
        with path.open("w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(handle, fieldnames=columns); writer.writeheader(); writer.writerows(rows)
        failed, _ = self.run_bundle(bad_bundle, "r_tlf", "run-duplicate", should_pass=False)
        out = failed / "outputs/t_pk_param_summary"
        self.assertFalse(list(out.glob("*.csv")))
        self.assertFalse(list(out.glob("*.rds")))
        self.assertIn("multiple analysis records", (out / "error.txt").read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
