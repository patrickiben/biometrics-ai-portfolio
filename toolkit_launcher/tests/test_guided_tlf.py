"""Focused QC for guided TLF configuration, data fidelity, and draft honesty."""
import csv
import io
import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from toolkit_launcher import guided_tlf as tlf

ROOT = Path(__file__).resolve().parents[2]


class GuidedTLFTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.folder = Path(self.temp.name)

    def inputs(self, rows):
        inputs = {}
        for slot, records in rows.items():
            path = self.folder / (slot + ".csv")
            columns = list(records[0])
            with path.open("w", newline="", encoding="utf-8") as out:
                writer = csv.DictWriter(out, fieldnames=columns)
                writer.writeheader()
                writer.writerows(records)
            inputs[slot] = {"absolute_path": path, "path": "private/" + path.name, "columns": columns, "rows": len(records)}
        return inputs

    def base(self, **kw):
        return {"study_id": "NEUTRAL-007", "design": "parallel", "outputs": ["t_pk_param_summary"], "reviewed": True, **kw}

    def pk_input(self):
        return self.inputs({"adpp": [{"participant": "0007", "arm": "Treatment A", "included": "Included", "parameter": "CMAX", "parameter_label": "Maximum concentration", "value": "12.5"}]})

    def pk_values(self, **kw):
        return self.base(pk_yes="Included", columns={"adpp": {"USUBJID": "participant", "TRT01A": "arm", "PKFL": "included", "PARAMCD": "parameter", "PARAM": "parameter_label", "AVAL": "value"}}, **kw)

    def test_mapping_preserves_ids_and_supplies_loader_and_driver(self):
        inputs = self.pk_input()
        result = tlf.validate("r_tlf", self.pk_values(), inputs, ROOT)
        self.assertEqual(result["errors"], [])
        output = tlf.build("r_tlf", result["normalized"], inputs, ROOT)
        row = next(csv.DictReader(io.StringIO(output["files"]["r/data/adpp.csv"])))
        self.assertEqual(row["USUBJID"], "0007")
        self.assertEqual(row["PKFL"], "Y")
        self.assertEqual(row["AVAL"], "12.5")
        self.assertIn('colClasses = "character"', output["files"]["r/00_setup.R"])
        self.assertIn('as.numeric(adam$adpp$AVAL)', output["files"]["r/00_setup.R"])
        self.assertNotIn('as.numeric(adam$adpp$USUBJID)', output["files"]["r/00_setup.R"])
        self.assertIn("execution_status.csv", output["files"]["r/00_run.R"])
        self.assertIn("configured draft", output["files"]["template_inventory.json"])
        self.assertIn('env <- guided_setup()', output["files"]["r/programs/t_pk_param_summary.R"])
        self.assertEqual(set(result["normalized"]) - {f["id"] for s in tlf.schema("r_tlf", ROOT)["steps"] for f in s["fields"]}, {"columns"})

    def test_required_columns_numeric_values_and_consent_fail_closed(self):
        inputs = self.pk_input()
        values = self.pk_values()
        values["columns"]["adpp"]["AVAL"] = ""
        values["reviewed"] = False
        result = tlf.validate("r_tlf", values, inputs, ROOT)
        self.assertIn("columns.adpp.AVAL", [e["field"] for e in result["errors"]])
        self.assertIn("reviewed", [e["field"] for e in result["errors"]])
        with self.assertRaises(ValueError):
            tlf.build("r_tlf", values, inputs, ROOT)
        bad = self.inputs({"adpp": [{"USUBJID": "001", "TRT01A": "A", "PKFL": "Y", "PARAM": "CMAX", "PARAMCD": "CMAX", "AVAL": "NaN"}]})
        self.assertTrue(any(e["field"] == "columns.adpp.AVAL" for e in tlf.validate("r_tlf", self.base(), bad, ROOT)["errors"]))

    def test_crossover_denominator_uses_exposure_and_exact_be_levels(self):
        inventory = tlf._inventory("r_tlf", ROOT)
        self.assertIn("adex", inventory["crossover"]["t_ae_overview"]["requirements"])
        self.assertNotIn("adsl", inventory["crossover"]["t_ae_overview"]["requirements"])
        rows = [{"USUBJID": "001", "PKFL": "Y", "PARAMCD": "CMAX", "AVAL": "12", "TRTA": arm, "TRTSEQP": "RT", "APERIOD": str(n)} for n, arm in enumerate(["Comparator", "Investigational", "Other"], 1)]
        inputs = self.inputs({"adpp": rows})
        v = self.base(design="crossover", outputs=["t_be_anova"], reference_label="Comparator", test_label="Investigational")
        result = tlf.validate("r_tlf", v, inputs, ROOT)
        self.assertIn("reference_label", [e["field"] for e in result["errors"]])
        inputs = self.inputs({"adpp": rows[:2]})
        result = tlf.validate("r_tlf", v, inputs, ROOT)
        self.assertEqual(result["errors"], [])
        output = tlf.build("r_tlf", result["normalized"], inputs, ROOT)
        rows = list(csv.DictReader(io.StringIO(output["files"]["r/data/adpp.csv"])))
        self.assertEqual([row["TRTA"] for row in rows], ["Reference", "Test"])

    def test_paired_domains_do_not_inherit_the_other_domains_flags_or_measures(self):
        inventory = tlf._inventory("r_tlf", ROOT)
        impact = inventory["parallel"]["t_ada_impact_pk"]["requirements"]
        self.assertIn("PKFL", impact["adpp"])
        self.assertNotIn("PKFL", impact["adis"])
        self.assertNotIn("PARAMCD", impact["adis"])
        period = inventory["crossover"]["t_pk_param_by_period"]["requirements"]
        self.assertIn("SAFFL", period["adex"])
        for field in ("AVAL", "PARAMCD", "PKFL"):
            self.assertNotIn(field, period["adex"])
        cqtc = inventory["sad"]["f_cqtc_hysteresis"]["requirements"]
        for field in ("SAFFL", "ANL01FL", "CHG"):
            self.assertNotIn(field, cqtc["adpc"])
        self.assertNotIn("PKFL", cqtc["adeg"])
        sas = tlf._inventory("sas_tlf", ROOT)["crossover"]["t_pk_param_by_period"]["requirements"]
        self.assertIn("TRTA", sas["adsl"])
        self.assertNotIn("TRTSEQP", sas["adsl"])

    def test_sas_driver_is_self_contained_and_metadata_cannot_inject_code(self):
        inputs = self.inputs({"adpp": [{"USUBJID": "0001", "TRT01A": "A", "TRT01AN": "1", "PKFL": "Y", "PARAMCD": "CMAX", "PARAM": "Cmax", "AVAL": "10"}], "adsl": [{"USUBJID": "0001", "TRT01A": "A", "TRT01AN": "1", "PKFL": "Y"}]})
        result = tlf.validate("sas_tlf", self.base(), inputs, ROOT)
        self.assertEqual(result["errors"], [])
        output = tlf.build("sas_tlf", result["normalized"], inputs, ROOT)
        driver = output["files"]["sas/00_run.sas"]
        self.assertNotIn("datalines4;", driver)
        self.assertNotIn('proc import', tlf._code(driver, "sas").lower())
        self.assertIn('/guided_inputs" access=readonly', driver)
        self.assertNotIn('%include "../', driver)
        self.assertIn("length USUBJID $4;", driver)
        self.assertIn("'30303031'x", driver)
        self.assertNotIn("/data/adam", driver)
        attack = self.base(study_id='x"; %put INJECTION;')
        self.assertIn("study_id", [e["field"] for e in tlf.validate("sas_tlf", attack, inputs, ROOT)["errors"]])

    def test_study_and_cross_domain_participant_mismatches_block_generation(self):
        rows = {"adpp": [{"STUDYID": "OTHER-STUDY", "USUBJID": "002", "TRT01A": "A", "TRT01AN": "1", "PKFL": "Y", "PARAMCD": "CMAX", "PARAM": "Cmax", "AVAL": "10"}], "adsl": [{"STUDYID": "NEUTRAL-007", "USUBJID": "001", "TRT01A": "A", "TRT01AN": "1", "PKFL": "Y"}]}
        inputs = self.inputs(rows)
        result = tlf.validate("sas_tlf", self.base(), inputs, ROOT)
        fields = [e["field"] for e in result["errors"]]
        self.assertIn("columns.adpp.STUDYID", fields)
        self.assertIn("inputs.adpp", fields)
        rows["adpp"][0].update(STUDYID="NEUTRAL-007", USUBJID="001")
        result = tlf.validate("sas_tlf", self.base(), self.inputs(rows), ROOT)
        self.assertEqual(result["errors"], [])

    def test_sas_character_payloads_cannot_become_source_or_raw_data_terminators(self):
        payload = ';;;;\n%put INJECTED;\n" &macro café'
        inputs = self.inputs({"adpp": [{"USUBJID": "001", "TRT01A": payload, "TRT01AN": "1", "PKFL": "Y", "PARAMCD": "CMAX", "PARAM": payload * 20, "AVAL": "10"}], "adsl": [{"USUBJID": "001", "TRT01A": payload, "TRT01AN": "1", "PKFL": "Y"}]})
        output = tlf.build("sas_tlf", self.base(), inputs, ROOT)
        driver = output["files"]["sas/00_run.sas"]
        self.assertNotIn("%put INJECTED", driver)
        self.assertNotIn("datalines", tlf._code(driver, "sas").lower())
        self.assertIn("'" + payload.encode("utf-8").hex() + "'x", driver)
        self.assertIn("\n || '", driver, "Long character data are split into bounded hex tokens")

    def test_header_only_event_domain_is_allowed_but_empty_denominator_is_not(self):
        inputs = self.inputs({"adsl": [{"USUBJID": "001", "SAFFL": "Y", "TRT01A": "A"}]})
        path = self.folder / "adae.csv"
        path.write_text("USUBJID,SAFFL,TRT01A,TRTEMFL,AESOC,AEDECOD\n", encoding="utf-8")
        inputs["adae"] = {"absolute_path": path}
        values = self.base(outputs=["t_ae_by_soc_pt"])
        report = tlf.validate("r_tlf", values, inputs, ROOT)
        self.assertEqual(report["errors"], [])
        self.assertTrue(any("zero records" in item for item in report["warnings"]))
        tlf.build("r_tlf", report["normalized"], inputs, ROOT)
        inputs["adsl"]["absolute_path"].write_text("USUBJID,SAFFL,TRT01A\n", encoding="utf-8")
        self.assertTrue(any(e["field"] == "inputs.adsl" for e in tlf.validate("r_tlf", values, inputs, ROOT)["errors"]))

    @unittest.skipUnless(shutil.which("Rscript"), "Rscript is not installed")
    def test_generated_r_driver_executes_mapped_pk_data_and_records_failure(self):
        probe = subprocess.run(["Rscript", "-e", 'p<-c("dplyr","tidyr","stringr","purrr","tibble","rtables","ggplot2","emmeans","lme4","broom","broom.mixed");quit(status=if(all(vapply(p,requireNamespace,logical(1),quietly=TRUE)))0 else 42)'], capture_output=True, text=True, timeout=60)
        if probe.returncode == 42:
            self.skipTest("TLF R packages are not installed; no packages downloaded")
        self.assertEqual(probe.returncode, 0, probe.stderr)
        data = [{"participant": id, "arm": "Treatment A", "included": "Included", "parameter": param, "parameter_label": param, "value": value}
                for id in ("0007", "0008") for param, value in (("CMAX", "12.5"), ("TMAX", "2"))]
        inputs = self.inputs({"adpp": data})
        output = tlf.build("r_tlf", self.pk_values(), inputs, ROOT)
        for name, content in output["files"].items():
            target = self.folder / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(content, encoding="utf-8")
        driver = self.folder / "r/00_run.R"
        run = subprocess.run(["Rscript", "-e", "source(" + json.dumps(str(driver)) + ")"], capture_output=True, text=True, timeout=60)
        self.assertEqual(run.returncode, 0, run.stderr)
        with (self.folder / "r/draft_results/execution_status.csv").open(encoding="utf-8", newline="") as file:
            status = next(csv.DictReader(file))
        self.assertEqual(status["execution"], "executed draft; not validated")
        self.assertEqual(status["error"], "")
        verify = 'bundle_root<-' + json.dumps(str(driver.parent)) + ';source(file.path(bundle_root,"00_setup.R"));stopifnot(identical(adam$adpp$USUBJID,c("0007","0007","0008","0008")),all(adam$adpp$PKFL=="Y"));x<-readRDS(file.path(bundle_root,"draft_results/t_pk_param_summary.rds"));stopifnot(is.data.frame(x$tab),any(grepl("12.5",as.character(x$tab[["Treatment A"]]))))'
        verified = subprocess.run(["Rscript", "-e", verify], capture_output=True, text=True, timeout=60)
        self.assertEqual(verified.returncode, 0, verified.stderr)
        # Exercise the driver's honest failure status without changing library sources.
        (driver.parent / "programs/t_pk_param_summary.R").write_text('stop("intentional test failure")\n', encoding="utf-8")
        failed = subprocess.run(["Rscript", "-e", "source(" + json.dumps(str(driver)) + ")"], capture_output=True, text=True, timeout=60)
        self.assertEqual(failed.returncode, 0, failed.stderr)
        with (self.folder / "r/draft_results/execution_status.csv").open(encoding="utf-8", newline="") as file:
            status = next(csv.DictReader(file))
        self.assertEqual(status["execution"], "failed")
        self.assertEqual(status["error"], "intentional test failure")
        self.assertFalse((self.folder / "r/draft_results/t_pk_param_summary.rds").exists(), "A failed rerun must not leave a stale successful analysis object")

    def test_every_template_configures_without_mutating_sources_and_r_parses(self):
        parse_paths = []
        for module in ("r_tlf", "sas_tlf"):
            inventory = tlf._inventory(module, ROOT)
            self.assertEqual(sum(map(len, inventory.values())), 221)
            options = tlf.schema(module, ROOT)["steps"][0]["fields"][2]["options_by_design"]
            for design, selected in inventory.items():
                req = {}
                for stem, item in selected.items():
                    for slot, columns in item["requirements"].items():
                        req.setdefault(slot, set()).update(columns)
                    self.assertTrue(next(x for x in options[design] if x["value"] == stem)["inputs"])
                data = {}
                for slot, columns in req.items():
                    data[slot] = []
                    for n in range(2):
                        row = {col: "1" if col in tlf.NUMERIC else "2026-01-01" if col in tlf.DATES else "NEUTRAL-007" if col == "STUDYID" else "Y" for col in columns}
                        row["USUBJID"] = "000" + str(n)
                        for col in ("TRTA", "APERIODC"):
                            if col in row:
                                row[col] = ["Reference", "Test"][n]
                        data[slot].append(row)
                inputs = self.inputs(data)
                v = self.base(design=design, outputs=list(selected))
                result = tlf.validate(module, v, inputs, ROOT)
                self.assertEqual(result["errors"], [], (module, design, result["errors"]))
                output = tlf.build(module, result["normalized"], inputs, ROOT)
                manifest = json.loads(output["files"]["template_inventory.json"])
                self.assertEqual(len(manifest["outputs"]), len(selected))
                for name, text in output["files"].items():
                    if "/programs/" in name:
                        self.assertNotIn("/data/adam", text)
                        self.assertNotIn('"CP-101"', text)
                    if name.endswith(".R"):
                        target = self.folder / module / design / name
                        target.parent.mkdir(parents=True, exist_ok=True)
                        target.write_text(text, encoding="utf-8")
                        parse_paths.append(target)
                for item in selected.values():
                    self.assertEqual(item["text"], item["path"].read_text(encoding="utf-8"))
        if shutil.which("Rscript"):
            script = self.folder / "parse.R"
            script.write_text('args <- commandArgs(trailingOnly=TRUE)\nstopifnot(length(args) == 1L)\npaths <- readLines(args[[1]], encoding="UTF-8", warn=FALSE)\nfor (p in paths) parse(file=p, encoding="UTF-8")\n', encoding="utf-8")
            # Keep the process command short enough for Windows even when every
            # generated program and its parent folders have long absolute paths.
            path_list = self.folder / "parse_paths.txt"
            path_list.write_text("\n".join(path.as_posix() for path in parse_paths) + "\n", encoding="utf-8")
            result = subprocess.run(["Rscript", str(script), str(path_list)], capture_output=True, text=True, timeout=90)
            self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
