"""Study-neutral setup, adversarial inputs and safe native exports for vaccines."""
import copy
import csv
import io
import json
from pathlib import Path
import tempfile
import unittest

from toolkit_launcher import guided_setup as setup, guided_vaccine as vaccine

ROOT = Path(__file__).resolve().parents[2]


class VaccineSetupTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name)
        self.values = json.loads((ROOT / "vaccine/examples/example_settings.json").read_text())
        self.values.update(review_confirmed=True, visits_confirmed=True, diary_confirmed=True)
        self.inputs = {}
        for slot in vaccine.FEEDS:
            self.write(slot, (ROOT / f"vaccine/examples/{slot}.csv").read_text())

    def write(self, slot, text):
        path = self.path / (slot + ".csv")
        path.write_bytes(text.encode("utf-8"))
        self.inputs[slot] = setup.csv_metadata(path, f"inputs/{slot}.csv")

    def edit(self, slot, fn):
        rows = list(csv.DictReader(io.StringIO((self.path / (slot + ".csv")).read_text())))
        columns = list(rows[0])
        fn(rows)
        out = io.StringIO(newline="")
        writer = csv.DictWriter(out, fieldnames=columns, lineterminator="\n")
        writer.writeheader(); writer.writerows(rows)
        self.write(slot, out.getvalue())

    def report(self, **changes):
        return vaccine.validate("vaccine", {**self.values, **changes}, self.inputs, ROOT)

    def test_defaults_have_no_study_or_protective_definition_and_require_review(self):
        schema = vaccine.schema("vaccine", ROOT)
        fields = setup.fields(schema)
        for key in ("study_id", "assay", "antigen", "unit", "baseline_visit", "response_threshold", "fold_threshold", "baseline_threshold"):
            self.assertEqual(fields[key]["default"], "", key)
        self.assertTrue(vaccine.validate("vaccine", {}, {}, ROOT)["errors"])
        for key in ("review_confirmed", "visits_confirmed", "diary_confirmed"):
            self.assertTrue(self.report(**{key: False})["errors"], key)
        self.assertEqual(self.report()["errors"], [])

    def test_output_scopes_require_only_their_inputs(self):
        for output, (_, slots) in vaccine.OUTPUTS.items():
            inputs = {key: self.inputs[key] for key in slots}
            report = vaccine.validate("vaccine", {**self.values, "outputs": [output]}, inputs, ROOT)
            self.assertEqual(report["errors"], [], output)
            self.assertEqual(set(report["data"]), set(slots))
        self.inputs.pop("titers")
        self.assertTrue(self.report(outputs=["response"])["errors"])
        self.assertFalse(self.report(outputs=["reactogenicity"])["errors"])

    def test_list_boundaries_labels_and_unknown_methods(self):
        for changes in ({"outputs": []}, {"outputs": ["unknown"]}, {"followup_visits": "Day 28\nDay 28"},
                        {"followup_visits": "Baseline"}, {"confidence": 1}, {"day_start": 7, "day_end": 6},
                        {"day_start": 0.5}, {"max_grade": 6}, {"blq_policy": "automatic"},
                        {"alq_policy": "automatic"}, {"react_denominator": "all"}, {"response_rule": "protective"},
                        {"response_threshold": 0}, {"fold_threshold": 1}, {"baseline_threshold": -1}):
            with self.subTest(changes=changes):
                self.assertTrue(self.report(**changes)["errors"])

    def test_custom_header_flag_and_qualifier_mappings(self):
        text = (self.path / "participants.csv").read_text().replace("USUBJID", "Person").replace(",Y", ",Included").replace(",N", ",Excluded")
        self.write("participants", text)
        self.write("titers", (self.path / "titers.csv").read_text().replace(",EXACT,", ",Measured,").replace(",BLQ,", ",Low,").replace(",ALQ,", ",High,").replace(",MISSING,", ",Unavailable,"))
        report = self.report(yes_value="Included", no_value="Excluded", columns={"participants": {"USUBJID": "Person"}},
                             qualifier_exact="Measured", qualifier_blq="Low", qualifier_alq="High", qualifier_missing="Unavailable")
        self.assertFalse(report["errors"], report["errors"])
        self.assertEqual(set(r["IMMFL"] for r in report["data"]["participants"]), {"Y", "N"})
        self.assertEqual(set(r["QUALIFIER"] for r in report["data"]["titers"]), {"EXACT", "BLQ", "ALQ", "MISSING"})
        self.assertTrue(self.report(yes_value="Y", no_value="Y")["errors"])
        self.assertTrue(self.report(qualifier_exact="BLQ")["errors"])

    def test_each_analytic_key_rejects_duplicates(self):
        original = {k: (self.path / (k + ".csv")).read_text() for k in self.inputs}
        for slot in vaccine.FEEDS:
            with self.subTest(slot=slot):
                self.edit(slot, lambda rows: rows.append(copy.deepcopy(rows[0])))
                self.assertTrue(any("Duplicate" in e["message"] for e in self.report()["errors"]))
                self.write(slot, original[slot])

    def test_unknown_participants_and_unadministered_diary_doses_fail(self):
        self.edit("titers", lambda rows: rows[0].update(USUBJID="NOT-IN-ROSTER"))
        self.assertTrue(any("roster" in e["message"] for e in self.report()["errors"]))
        self.edit("diary", lambda rows: rows[0].update(DOSE="Never administered"))
        self.assertTrue(any("administered-dose roster" in e["message"] for e in self.report()["errors"]))

    def test_units_and_censoring_are_not_silently_combined(self):
        original = (self.path / "titers.csv").read_text()
        for change in ({"UNIT": "different unit"}, {"AVAL": "0"}, {"AVAL": "NaN"}, {"AVAL": "Inf"},
                       {"LLOQ": "900", "ULOQ": "10"}, {"AVAL": "", "QUALIFIER": "EXACT"},
                       {"QUALIFIER": "BLQ", "LLOQ": ""}, {"QUALIFIER": "ALQ", "ULOQ": ""},
                       {"QUALIFIER": "MISSING", "AVAL": "100"}):
            with self.subTest(change=change):
                self.edit("titers", lambda rows: rows[0].update(change))
                self.assertTrue(self.report()["errors"])
                self.write("titers", original)

    def test_header_only_assays_and_diaries_preserve_missing_population(self):
        for slot in ("titers", "diary"):
            self.write(slot, ",".join(c[0] for c in vaccine.FEEDS[slot]) + "\n")
        report = self.report()
        self.assertFalse(report["errors"], report["errors"])
        self.assertEqual(report["data"]["titers"], [])
        self.assertEqual(report["data"]["diary"], [])
        self.assertEqual(len(report["data"]["participants"]), 12)

    def test_grade_semantics_and_fractional_days_are_validated(self):
        original = (self.path / "diary.csv").read_text()
        for change in ({"GRADE": "-1"}, {"GRADE": "4"}, {"GRADE": "1.5"}, {"DAY": "1.1"}):
            with self.subTest(change=change):
                self.edit("diary", lambda rows: rows[0].update(change))
                self.assertTrue(self.report()["errors"])
                self.write("diary", original)
        self.edit("diary", lambda rows: rows[0].update(GRADE=""))
        self.assertFalse(self.report()["errors"])

    def test_nullable_grade_requires_a_source_column_mapping(self):
        report = self.report(columns={"diary": {"GRADE": ""}})
        self.assertTrue(any(e["field"] == "columns.diary.GRADE" for e in report["errors"]))
        schema = vaccine.schema("vaccine", ROOT)
        grade = next(c for slot in schema["inputs"] if slot["id"] == "diary" for c in slot["columns"] if c["id"] == "GRADE")
        self.assertTrue(grade["required"])
        # The column is mandatory; genuinely unobserved values remain allowed.
        self.edit("diary", lambda rows: [row.update(GRADE="") for row in rows])
        self.assertFalse(self.report()["errors"])

    def test_large_expected_visit_grid_is_rejected_before_r_execution(self):
        self.write("participants", "USUBJID,ARM,IMMFL,SAFEFL\n" + "".join(f"P{i},Arm A,Y,Y\n" for i in range(20000)))
        self.write("titers", ",".join(c[0] for c in vaccine.FEEDS["titers"]) + "\n")
        report = self.report(outputs=["immunogenicity"], followup_visits="\n".join(f"Visit {i}" for i in range(50)))
        self.assertTrue(any(e["field"] == "followup_visits" and "1,000,000" in e["message"] for e in report["errors"]))

    def test_arm_mapping_capacity_is_explicit(self):
        self.write("participants", "USUBJID,ARM,IMMFL,SAFEFL\n" + "".join(f"P{i},Arm {i},Y,Y\n" for i in range(51)))
        self.write("titers", ",".join(c[0] for c in vaccine.FEEDS["titers"]) + "\n")
        report = self.report(outputs=["immunogenicity"])
        self.assertTrue(any(e["field"] == "inputs.participants.ARM" and "50" in e["message"] for e in report["errors"]))

    def test_all_response_rules_and_missingness_policies_can_be_selected(self):
        for rule in ("threshold", "fold_rise", "conditional"):
            for denominator in ("complete", "observed"):
                for blq in ("exclude", "half_lloq", "lloq"):
                    for alq in ("exclude", "uloq"):
                        report = self.report(response_rule=rule, react_denominator=denominator, blq_policy=blq, alq_policy=alq)
                        self.assertFalse(report["errors"], report["errors"])

    def test_export_keeps_text_inert_and_scope_complete(self):
        malicious = "STUDY'; %put &secret; <script> café"
        report = self.report(study_id=malicious)
        self.assertFalse(report["errors"])
        built = vaccine.build("vaccine", report["normalized"], self.inputs, ROOT)["files"]
        sas = built["vaccine_analysis.sas"]
        self.assertNotIn(malicious, sas)
        self.assertIn("'" + malicious.encode().hex() + "'x", sas)
        self.assertIn("NOT been executed", sas)
        config = json.loads(built["study_setup.json"])
        self.assertEqual(config["study_id"], malicious)
        self.assertEqual(config["followup_visits"], ["Day 28", "Day 56"])
        self.assertEqual(set(config["outputs"]), set(vaccine.OUTPUTS))
        self.assertEqual(set(k for k in built if k.startswith("inputs/")), {f"inputs/{s}.csv" for s in vaccine.FEEDS})
        self.assertEqual(built["R/vaccine_analysis.R"], (ROOT / "vaccine/analysis.R").read_text())
        self.assertNotIn("](index.html)", built["README.md"])
        self.assertIn("](https://patrickiben.github.io/biometrics-ai-portfolio/vaccine/index.html)", built["README.md"])
        self.assertIn("](https://patrickiben.github.io/biometrics-ai-portfolio/TOOLKIT_SETUP.html)", built["README.md"])

    def test_profile_remains_form_roundtrippable_without_data(self):
        report = self.report()
        normalized = setup.clean_values(vaccine.schema("vaccine", ROOT), report["normalized"])
        self.assertEqual(normalized, report["normalized"])
        self.assertIsInstance(normalized["followup_visits"], str)
        self.assertNotIn("data", normalized)
        self.assertNotIn("participants", normalized)


if __name__ == "__main__":
    unittest.main()
