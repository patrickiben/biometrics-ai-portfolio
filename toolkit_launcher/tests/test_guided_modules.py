"""Behavioral checks for guided monitoring, findings review and factual previews."""
import csv
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("guided_modules", ROOT / "toolkit_launcher/guided_modules.py")
guided = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guided)


class GuidedModulesTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name)
        self.inputs = {}
        self.base = dict(study_id="STUDY-NEUTRAL", review_confirmed=True)

    def tearDown(self):
        self.temp.cleanup()

    def upload(self, slot, data):
        path = self.path / (slot + ".csv")
        path.write_text(data, encoding="utf-8")
        rows = list(csv.DictReader(io.StringIO(data)))
        self.inputs[slot] = dict(path="inputs/" + path.name, absolute_path=path, rows=len(rows), columns=list(rows[0]) if rows else [], sha256=hashlib.sha256(path.read_bytes()).hexdigest(), preview=rows[:2])

    def valid(self, module, **settings):
        report = guided.validate(module, dict(self.base, **settings), self.inputs, ROOT)
        self.assertEqual(report["errors"], [], report)
        allowed = {f["id"] for s in guided.schema(module, ROOT)["steps"] for f in s["fields"]} | {"columns"}
        self.assertEqual(set(report["normalized"]) - allowed, set())
        package = guided.build(module, report["normalized"], self.inputs, ROOT)
        self.assertFalse(json.loads(package["files"]["audit.json"])["approved"])
        self.assertEqual(set(self.path.iterdir()), {v["absolute_path"] for v in self.inputs.values()})
        return report, package

    def test_schemas_are_json_serializable_and_have_review_gate(self):
        for module in guided.MODULES:
            schema = guided.schema(module, ROOT)
            json.dumps(schema)
            self.assertIn("inputs", [s["id"] for s in schema["steps"]])
            fields = [f for s in schema["steps"] for f in s["fields"]]
            self.assertIn("review_confirmed", [f["id"] for f in fields])
            self.assertTrue(schema["inputs"])
            self.assertTrue(guided.validate(module, {}, {}, ROOT)["errors"])

    def test_monitor_selects_only_requested_check_and_maps_flags(self):
        self.upload("queries", "IsOpen,Age\nYES,31\nNO,5\n")
        report, package = self.valid("sas_monitor", checks=["queries"], yes_value="YES", no_value="NO", query_days=21, columns={"queries": {"OPEN_FL": "IsOpen", "QUERY_AGE_DAYS": "Age"}})
        self.assertEqual(package["files"]["inputs/queries.csv"], "OPEN_FL,QUERY_AGE_DAYS\nY,31.0\nN,5.0\n")
        driver = package["files"]["run_monitor.sas"]
        self.assertIn("age_amb=21", driver)
        self.assertNotIn("%include", driver)
        self.assertNotIn("infile", driver)
        self.assertIn("%macro tm_chk_queries", driver)
        self.assertIn("pathname(work)", driver)
        self.assertIn('"aged >&age_amb.d"', driver)
        self.assertNotIn("tm_chk_ae", driver)
        for prohibited in ("tm_email", "tm_digest", "tm_alert", "smtp", "CP-101", "approved=1"):
            self.assertNotIn(prohibited, driver)
        self.assertIn("%macro tm_chk_queries", package["files"]["monitor_checks.sas"])
        self.assertIn("Native SAS exports are unexecuted references", " ".join(package["limitations"]))
        self.assertIn("Run the mapped checks with R", " ".join(package["limitations"]))

    def test_monitor_embeds_text_as_hex_and_dates_as_sas_days(self):
        self.upload("visits", 'USUBJID,VISIT,ACTDT,PLANDT,WINDOW_DAYS\n"P1; %put &secret;",Week 1,,2026-01-01,3\n')
        _, package = self.valid("sas_monitor", checks=["visits"])
        driver = package["files"]["run_monitor.sas"]
        self.assertNotIn("&secret", driver)
        self.assertIn("'" + "P1; %put &secret;".encode().hex() + "'x", driver)
        self.assertIn("ACTDT=.;", driver)
        self.assertIn("PLANDT=24107;", driver)

    def test_every_monitor_check_accepts_explicit_valid_feed(self):
        feeds = {
            "liver": "USUBJID,alt_x,ast_x,tbl_x,alp_x\nP1,3,2,3,1\n",
            "qtcf": "USUBJID,QTCF,DQTCF\nP1,490,40\n",
            "ae": "USUBJID,COHORT,AESER,AETOXGR,TRTEMFL\nP1,Dose 1,Y,3,Y\n",
            "dlt": "USUBJID,COHORT,DLT_EVAL,DLTFL\nP1,Dose 1,Y,Y\n",
            "enrollment": "N_ENROLLED,N_PLANNED_TO_DATE\n4,10\n",
            "queries": "OPEN_FL,QUERY_AGE_DAYS\nY,31\n",
            "visits": "USUBJID,VISIT,ACTDT,PLANDT,WINDOW_DAYS\nP1,Week 1,,2026-01-01,3\n",
            "clinical": "USUBJID,TRT01P\nP1,Arm A\n",
            "randomization": "USUBJID,IXRS_TRT\nP1,Arm A\n"}
        for slot, csvdata in feeds.items():
            self.upload(slot, csvdata)
        _, package = self.valid("sas_monitor", checks=list(guided.CHECKS))
        self.assertEqual(len([f for f in package["files"] if f.startswith("inputs/")]), 9)
        for check in guided.CHECKS:
            self.assertIn("result_" + check, package["files"]["run_monitor.sas"])

    def test_monitor_rejects_missing_bad_flags_and_duplicate_keys(self):
        report = guided.validate("sas_monitor", dict(self.base, checks=["dlt"]), {}, ROOT)
        self.assertTrue(report["errors"])
        self.upload("dlt", "USUBJID,COHORT,DLT_EVAL,DLTFL\nP1,A,Y,Y\nP1,A,Y,N\n")
        report = guided.validate("sas_monitor", dict(self.base, checks=["dlt"]), self.inputs, ROOT)
        self.assertTrue(any("Duplicate" in e["message"] for e in report["errors"]))
        self.upload("queries", "OPEN_FL,QUERY_AGE_DAYS\nmaybe,NaN\n")
        report = guided.validate("sas_monitor", dict(self.base, checks=["queries"]), self.inputs, ROOT)
        self.assertTrue(any("yes or no" in e["message"] for e in report["errors"]))
        self.assertTrue(any("finite" in e["message"] for e in report["errors"]))
        self.upload("enrollment", "N_ENROLLED,N_PLANNED_TO_DATE\n1,0\n")
        self.assertTrue(guided.validate("sas_monitor", dict(self.base, checks=["enrollment"]), self.inputs, ROOT)["errors"])

    def test_dlt_rejects_zero_evaluable_cohort_and_flags_pending_dlt(self):
        self.upload("dlt", "USUBJID,COHORT,DLT_EVAL,DLTFL\nP1,A,N,N\n")
        report = guided.validate("sas_monitor", dict(self.base, checks=["dlt"]), self.inputs, ROOT)
        self.assertTrue(any("no completed evaluable" in e["message"] for e in report["errors"]))
        self.upload("dlt", "USUBJID,COHORT,DLT_EVAL,DLTFL\nP1,A,N,Y\nP2,A,Y,N\n")
        report, _ = self.valid("sas_monitor", checks=["dlt"])
        self.assertTrue(any("pending flags" in w for w in report["warnings"]))

    def test_monitor_threshold_order_and_dates(self):
        self.upload("qtcf", "USUBJID,QTCF,DQTCF\nP1,490,40\n")
        report = guided.validate("sas_monitor", dict(self.base, checks=["qtcf"], qtcf_red=400), self.inputs, ROOT)
        self.assertTrue(any(e["field"] == "qtcf_red" for e in report["errors"]))
        self.upload("visits", "USUBJID,VISIT,ACTDT,PLANDT,WINDOW_DAYS\nP1,Week 1,,2026-02-30,3\n")
        self.assertTrue(guided.validate("sas_monitor", dict(self.base, checks=["visits"]), self.inputs, ROOT)["errors"])

    def test_localmind_preserves_finding_text_as_data_and_never_approves(self):
        self.upload("findings", 'id,rule_id,text\nF1,R1,"<script>alert(1)</script>; %put &secret; café"\n')
        _, package = self.valid("localmind", model_name="example:latest", columns={"findings": {"finding_id": "id", "rule": "rule_id", "findtext": "text"}})
        rows = list(csv.DictReader(io.StringIO(package["files"]["review.csv"])))
        self.assertEqual(rows[0]["approved"], "FALSE")
        self.assertEqual(rows[0]["owner"], "")
        self.assertIn("café", rows[0]["findtext"])
        self.assertNotIn("&secret", package["files"]["open_review.sas"])
        self.assertIn("worklist$approved <- FALSE", package["files"]["run_local_model.R"])
        self.assertNotIn("SD0064", package["files"]["R/slm_companion.R"])
        self.assertNotIn("approved=1", "\n".join(str(v) for v in package["files"].values()))
        self.assertEqual(json.loads(package["files"]["audit.json"])["execution"], "not_run")

    def test_localmind_manual_review_needs_no_model_and_formula_cells_are_inert(self):
        self.upload("findings", 'finding_id,rule,findtext\nF1,R1,"=HYPERLINK(""https://example.invalid"", ""click"")"\n')
        _, package = self.valid("localmind")
        row = next(csv.DictReader(io.StringIO(package["files"]["review.csv"])))
        self.assertTrue(row["findtext"].startswith("'=HYPERLINK"))
        canonical = next(csv.DictReader(io.StringIO(package["files"]["inputs/findings.csv"])))
        self.assertTrue(canonical["findtext"].startswith("=HYPERLINK"))
        self.assertIn("!isTRUE(cfg$enable_model)", package["files"]["run_local_model.R"])
        self.assertTrue(guided.validate("localmind", dict(self.base, enable_model=True), self.inputs, ROOT)["errors"])

    def test_localmind_rejects_external_urls_invalid_labels_and_duplicate_ids(self):
        self.upload("findings", "finding_id,rule,findtext\nF1,R1,Finding\n")
        for endpoint in ("https://localhost:11434", "http://localhost.example:11434", "http://127.0.0.1:11434@evil.com", "http://localhost:11434/api", "http://127.0.0.1:99999", "http://localhost:11434?target=evil"):
            with self.subTest(endpoint=endpoint):
                report = guided.validate("localmind", dict(self.base, model_name="example:latest", model_endpoint=endpoint), self.inputs, ROOT)
                self.assertTrue(any(e["field"] == "model_endpoint" for e in report["errors"]))
        report = guided.validate("localmind", dict(self.base, model_name="example:latest", owner_labels="DATA\nDATA"), self.inputs, ROOT)
        self.assertTrue(any(e["field"] == "owner_labels" for e in report["errors"]))
        self.upload("findings", "finding_id,rule,findtext\nF1,R1,Finding\nF1,R2,Other\n")
        self.assertTrue(guided.validate("localmind", dict(self.base, model_name="example:latest"), self.inputs, ROOT)["errors"])

    def ae(self):
        self.upload("ae_summary", "category,n,pct\nAny TEAE,10,50\nRelated TEAE,4,20\nSevere TEAE,2,10\nSAE,1,5\nTEAE leading to discontinuation,1,5\nDeath,0,0\n")
        return dict(summary_type="ae", arm="Active", population_n=20, aggregate_confirmed=True)

    def test_ae_generates_actual_facts_preview_and_no_fictional_data(self):
        report, package = self.valid("interpretation", **self.ae())
        facts = json.loads(package["files"]["facts.json"])
        self.assertEqual(facts["n_any_teae"], 10)
        self.assertEqual(facts["N"], 20)
        self.assertIn("10 participants (50%)", report["preview"]["text"])
        self.assertEqual(report["normalized"]["draft_text"], "")
        self.assertEqual(json.loads(package["files"]["audit.json"])["status"], "FLAGGED")
        self.assertIn("inputs/result.csv", package["files"]["verify_preview.R"])
        self.assertNotIn("data.frame(category", package["files"]["interpret_tlf.qmd"])
        self.assertIn('data-theme="dark"', package["files"]["interpretation.html"])
        self.assertIn("bp-theme", package["files"]["interpretation.html"])
        self.assertIn((ROOT / "assets/theme/tokens.css").read_text(encoding="utf-8"), package["files"]["interpretation.html"])
        self.assertIn("light: flatly", package["files"]["interpret_tlf.qmd"])

    def test_ae_category_mapping_and_renamed_columns(self):
        settings = self.ae()
        self.upload("ae_summary", "Label,Count,Percent\nAny,10,50\nRelated,4,20\nSevere,2,10\nSerious,1,5\nStop,1,5\nDied,0,0\n")
        settings.update({f"ae_category_{i}": label for i, label in enumerate(["Any", "Related", "Severe", "Serious", "Stop", "Died"])})
        settings["columns"] = {"ae_summary": {"category": "Label", "n": "Count", "pct": "Percent"}}
        _, package = self.valid("interpretation", **settings)
        self.assertIn("TEAE leading to discontinuation,1,5.0", package["files"]["inputs/result.csv"])

    def test_ae_invalid_denominator_duplicate_category_and_new_number(self):
        settings = self.ae()
        settings["population_n"] = 10
        self.assertTrue(guided.validate("interpretation", dict(self.base, **settings), self.inputs, ROOT)["errors"])
        settings["population_n"] = 20
        settings["draft_text"] = "There were 999 participants."
        report = guided.validate("interpretation", dict(self.base, **settings), self.inputs, ROOT)
        self.assertTrue(any(e["field"] == "draft_text" for e in report["errors"]))
        settings["draft_text"] = ""
        original = self.inputs["ae_summary"]["absolute_path"].read_text(encoding="utf-8")
        self.upload("ae_summary", original + "Any TEAE,10,50\n")
        self.assertTrue(guided.validate("interpretation", dict(self.base, **settings), self.inputs, ROOT)["errors"])

    def test_edited_prose_passes_or_is_flagged_but_never_approved(self):
        settings = self.ae()
        report, package = self.valid("interpretation", **settings, draft_text="There were 10 participants with any TEAE.")
        self.assertEqual(json.loads(package["files"]["audit.json"])["status"], "DRAFT_OK")
        _, package = self.valid("interpretation", **settings, draft_text="The treatment was safe in 20 participants.")
        self.assertEqual(json.loads(package["files"]["audit.json"])["status"], "FLAGGED")

    def test_pk_selects_exact_row_and_rounds_existing_extractor_facts(self):
        self.upload("pk_summary", "trt,param,n,geomean,geocv,median\nTest,CMAX,20,12.345,23.45,11.111\nReference,CMAX,20,99,33,88\n")
        report, package = self.valid("interpretation", summary_type="pk", treatment="Test", parameter="CMAX", aggregate_confirmed=True)
        facts = json.loads(package["files"]["facts.json"])
        self.assertEqual(facts, dict(parameter="CMAX", treatment="Test", n=20, geomean=12.35, geocv=23.4, median=11.11))
        self.assertNotIn("Reference", package["files"]["inputs/result.csv"])
        self.assertIn("12.35", report["preview"]["text"])
        self.assertTrue(guided.validate("interpretation", dict(self.base, summary_type="pk", treatment="Absent", parameter="CMAX", aggregate_confirmed=True), self.inputs, ROOT)["errors"])

    def test_report_escapes_user_html(self):
        settings = self.ae()
        settings["arm"] = "<img src=x onerror=alert('x')>"
        _, package = self.valid("interpretation", **settings)
        self.assertNotIn("<img", package["files"]["interpretation.html"])
        self.assertIn("&lt;img", package["files"]["interpretation.html"])

    def test_guard_matches_existing_numeric_and_claim_semantics(self):
        facts = {"arm": "Dose 5", "n": 20, "geomean": 12.345, "pct": 50}
        self.assertTrue(guided._guard("Dose 5: 20 participants; mean 12.3 and 50%.", facts)["all_ok"])
        self.assertFalse(guided._guard("There were 99 participants.", facts)["numbers"]["ok"])
        self.assertFalse(guided._guard("A favourable safety profile was seen in 20 participants.", facts)["claims"]["ok"])
        self.assertFalse(guided._guard("20 participants", facts)["template"]["ok"])

    def test_multiline_csv_text_is_rejected_before_sas_generation(self):
        self.upload("findings", 'finding_id,rule,findtext\nF1,R1,"First line\nSecond line"\n')
        self.assertTrue(guided.validate("localmind", self.base, self.inputs, ROOT)["errors"])

    def test_input_change_after_validation_is_rechecked(self):
        settings = self.ae()
        report = guided.validate("interpretation", dict(self.base, **settings), self.inputs, ROOT)
        self.inputs["ae_summary"]["absolute_path"].write_text("category,n,pct\nAny TEAE,999,100\n")
        with self.assertRaises(ValueError):
            guided.build("interpretation", report["normalized"], self.inputs, ROOT)

    def require_jsonlite(self):
        result = subprocess.run(["Rscript", "-e", "quit(status=if(requireNamespace('jsonlite', quietly=TRUE)) 0 else 1)"], capture_output=True, timeout=30)
        if result.returncode:
            self.skipTest("Optional R preview check needs jsonlite; no packages downloaded")

    @unittest.skipUnless(shutil.which("Rscript"), "R is not installed")
    def test_pk_preview_agrees_with_r_and_preserves_numeric_looking_labels(self):
        self.require_jsonlite()
        self.upload("pk_summary", "trt,param,n,geomean,geocv,median\n001,NA,20,12345,23.45,0.0012345\n")
        _, package = self.valid("interpretation", summary_type="pk", treatment="001", parameter="NA", aggregate_confirmed=True)
        output = self.path / "pk_built"
        output.mkdir()
        for name, text in package["files"].items():
            p = output / name
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(text, encoding="utf-8")
        run = subprocess.run(["Rscript", "verify_preview.R"], cwd=output, text=True, capture_output=True)
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        actual = json.loads((output / "r_verified_preview.json").read_text(encoding="utf-8"))
        expected = json.loads(package["files"]["facts.json"])
        self.assertEqual(actual["facts"], expected)
        self.assertEqual(actual["facts"]["treatment"], "001")
        self.assertEqual(actual["facts"]["parameter"], "NA")

    @unittest.skipUnless(shutil.which("Rscript"), "R is not installed")
    def test_generated_r_parses_and_preview_matches_original_r_extractors(self):
        self.require_jsonlite()
        settings = self.ae()
        _, package = self.valid("interpretation", **settings)
        output = self.path / "built"
        output.mkdir()
        for name, text in package["files"].items():
            p = output / name
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(text, encoding="utf-8")
        run = subprocess.run(["Rscript", "verify_preview.R"], cwd=output, text=True, capture_output=True)
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        actual = json.loads((output / "r_verified_preview.json").read_text(encoding="utf-8"))
        expected = json.loads(package["files"]["audit.json"])
        self.assertEqual(actual["facts"], expected["facts"])
        self.assertEqual(actual["status"], expected["status"])
        self.assertTrue(actual["validation"]["all_ok"])
        # Parse optional inference code only: never run a model or make network calls.
        self.upload("findings", "finding_id,rule,findtext\nF1,R1,Finding\n")
        report = guided.validate("localmind", dict(self.base, model_name="example:latest"), self.inputs, ROOT)
        local = guided.build("localmind", report["normalized"], self.inputs, ROOT)
        (output / "run_local_model.R").write_text(local["files"]["run_local_model.R"], encoding="utf-8")
        run = subprocess.run(["Rscript", "-e", "invisible(parse(file='run_local_model.R'))"], cwd=output, text=True, capture_output=True)
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)


if __name__ == "__main__":
    unittest.main()
