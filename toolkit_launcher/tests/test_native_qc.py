"""Portable QC tests for missing evidence, freshness and defect classifications."""
import contextlib
import csv
import importlib.util
import io
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest

MODULE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(MODULE))
import native_harness as harness
import native_teeth as teeth


class PortableQCTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def put(self, path, text=""):
        target = self.root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text, encoding="utf-8")
        return target

    def test_equal_counts_with_different_stems_fail_parity(self):
        self.put("sas_tlf_pseudocode/design/one.sas", "num=14.1")
        self.put("r_tlf_pseudocode/design/two.R", 'num="14.1"')
        nsas, nr, mismatch, collisions, missing = harness.twin_checks(self.root)
        self.assertEqual((nsas, nr, mismatch, collisions, missing), (1, 1, 0, 0, 2))

    def test_shared_model_helpers_are_not_counted_as_tlf_twins(self):
        self.put('sas_tlf_pseudocode/design/one.sas', 'num=14.1')
        self.put('r_tlf_pseudocode/design/one.R', 'num="14.1"')
        self.put('r_tlf_pseudocode/01_analysis_models.R', 'helper <- function() 1')
        self.assertEqual(harness.twin_checks(self.root), (1, 1, 0, 0, 0))

    def test_r_verdicts_accept_the_existing_colon_format(self):
        self.assertEqual(harness.token("G3_VERDICT: PASS\n", "G3_VERDICT", "FAIL"), "PASS")
        self.assertEqual(harness.token("G9_VERDICT PASS\n", "G9_VERDICT", "FAIL"), "PASS")

    def test_missing_test_is_not_a_passing_baseline(self):
        facts = [f"gate G{i} green" for i in range(1, 11)] + ["driver 0", "generator 0"]
        with self.assertRaisesRegex(ValueError, "missing"):
            teeth.check_baseline(facts)
        facts += ["test trialmon/" + n + " PASS" for n in teeth.TRIALMON_TESTS]
        facts.append("test uat_irt/test-logic.R PASS")
        teeth.check_baseline(facts)

    def test_ledger_updates_json_markdown_and_embedded_copy(self):
        self.put("validation_harness/index.html", '<script id="ledger" type="application/json">\n{}\n</script>')
        ledger = dict(generated="test", r_version="test", green=0, manual=1, unsigned=0,
                      total=1, gates=[dict(gate="G5 Manual", guards="review", status="manual", evidence="pending", sign_off="pending")])
        with contextlib.redirect_stdout(io.StringIO()):
            harness.write_ledger(self.root, ledger)
        self.assertEqual(json.loads((self.root / "validation_harness/ledger.json").read_text(encoding="utf-8")), ledger)
        self.assertIn('"status": "manual"', (self.root / "validation_harness/index.html").read_text(encoding="utf-8"))
        self.assertIn("☐ pending", (self.root / "validation_harness/EVIDENCE_LEDGER.md").read_text(encoding="utf-8"))

    def registry(self):
        registry = self.put("validation_harness/teeth/defects.csv")
        with registry.open("w", encoding="utf-8", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=["id", "class", "file", "old_str", "new_str", "predicted_catcher", "rationale"])
            writer.writeheader()
            writer.writerow(dict(id="D00", **{"class": "control"}, file="sim_lifecycle/run_lifecycle.R", old_str="before", new_str="after", predicted_catcher="EQUIVALENT", rationale="A known control. It changes no output."))
        self.put("sim_lifecycle/run_lifecycle.R", "before")
        self.put("validation_harness/teeth/defects.sha256", harness.sha(registry))
        target = self.put("validation_harness/teeth/apply_defect.py")
        shutil.copy2(MODULE.parent / "validation_harness/teeth/apply_defect.py", target)
        return registry

    def test_portable_freshness_requires_both_adapter_hashes(self):
        registry = self.registry()
        summary_path = self.put("validation_harness/teeth/results/summary.json")
        summary = dict(registry_sha256=harness.sha(registry), gate_scripts={}, counts={}, rows=[], partial=False)
        summary_path.write_text(json.dumps(summary))
        status, evidence = harness.sensitivity(self.root)
        self.assertEqual(status, "stale")
        self.assertIn("portable runner scripts", evidence)
        for name in ("native_harness.py", "native_teeth.py", "stub_profile.R"):
            path = self.put("toolkit_launcher/" + name, "known code")
            summary["gate_scripts"]["toolkit_launcher/" + name] = harness.sha(path)
        summary_path.write_text(json.dumps(summary))
        self.assertEqual(harness.sensitivity(self.root)[0], "green")
        self.put("toolkit_launcher/native_harness.py", "changed code")
        self.assertEqual(harness.sensitivity(self.root)[0], "stale")

    def test_classifier_distinguishes_equivalent_and_caught(self):
        registry = self.registry()
        self.put("sim_lifecycle/out/adpc.csv", "ATPTN,AVAL\n0,0\n")
        for path in teeth.GATE_SCRIPTS:
            if not (self.root / path).exists():
                self.put(path, "known source")
        logs = self.root / "logs"
        for tag in ("BASE", "D00"):
            self.put(f"logs/{tag}.facts", "driver 0\ngenerator 0\ngate G1 green\ntest example PASS\n")
            self.put(f"logs/{tag}.driver.txt", "same output")
            self.put(f"logs/{tag}.trialmon.txt", "same output")
            self.put(f"logs/{tag}.out/result.csv", "a,b\n1,2\n")
        output = self.root / "results"
        output.mkdir()
        with contextlib.redirect_stdout(io.StringIO()):
            teeth.classify(self.root, logs, output, "D00", harness.sha(registry), ["D00"], "test R")
        summary = json.loads((output / "summary.json").read_text(encoding="utf-8"))
        self.assertEqual(summary["rows"][0]["class"], "EQUIVALENT")
        self.assertEqual(summary["rows"][0]["status"], "as predicted")
        self.put("logs/D00.facts", "driver 0\ngenerator 0\ngate G1 red\ntest example PASS\n")
        with contextlib.redirect_stdout(io.StringIO()):
            teeth.classify(self.root, logs, output, "D00", harness.sha(registry), ["D00"], "test R")
        summary = json.loads((output / "summary.json").read_text(encoding="utf-8"))
        self.assertEqual(summary["rows"][0]["class"], "CAUGHT")
        self.assertEqual(summary["rows"][0]["layers"], "G1")
        self.assertEqual(summary["rows"][0]["status"], "differs from prediction")


if __name__ == "__main__":
    unittest.main()
