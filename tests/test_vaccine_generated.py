"""Real-R vaccine execution from guided CSV mappings and immutable revisions.

Synthetic input data only. The tests do not install packages or contact services.
"""
from __future__ import annotations

import base64
import csv
import hashlib
import io
import json
import math
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from toolkit_launcher import analysis_jobs, guided_setup, runtime

EXAMPLES = ROOT / "vaccine/examples"
OUTPUTS = {"immunogenicity", "fold_rise", "response", "titer_plot", "reactogenicity", "diary_profile"}


class VaccineExampleTests(unittest.TestCase):
    def test_templates_match_examples_and_examples_exercise_missingness(self):
        for slot in ("participants", "titers", "doses", "diary"):
            with (EXAMPLES / (slot + ".csv")).open(newline="", encoding="utf-8") as handle:
                reader = csv.DictReader(handle)
                headers, records = reader.fieldnames, list(reader)
            with (EXAMPLES / (slot + "_template.csv")).open(newline="", encoding="utf-8") as handle:
                template = csv.DictReader(handle)
                self.assertEqual(template.fieldnames, headers)
                self.assertEqual(list(template), [])
            self.assertTrue(records)
        titers = list(csv.DictReader((EXAMPLES / "titers.csv").read_text().splitlines()))
        self.assertEqual({r["QUALIFIER"] for r in titers}, {"EXACT", "BLQ", "ALQ", "MISSING"})
        diary = list(csv.DictReader((EXAMPLES / "diary.csv").read_text().splitlines()))
        self.assertTrue(any(r["GRADE"] == "" for r in diary))
        self.assertTrue(any(r["GRADE"] == "0" for r in diary))
        self.assertTrue(any(r["GRADE"] == "3" for r in diary))

    def test_example_profile_is_explicit_and_has_no_data_or_approval(self):
        profile = json.loads((EXAMPLES / "example_profile.json").read_text(encoding="utf-8"))
        self.assertEqual(set(profile), {"schema", "module_id", "values"})
        self.assertEqual((profile["schema"], profile["module_id"]), (1, "vaccine"))
        for key, value in json.loads((EXAMPLES / "example_settings.json").read_text(encoding="utf-8")).items():
            self.assertEqual(profile["values"][key], value)
        for key in ("visits_confirmed", "diary_confirmed", "review_confirmed"):
            self.assertFalse(profile["values"][key])
        self.assertNotIn("inputs", profile["values"])


class VaccineGeneratedTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.rscript = shutil.which("Rscript")
        if not cls.rscript:
            raise unittest.SkipTest("Rscript is not installed")
        result = subprocess.run([cls.rscript, "--vanilla", "-e", "quit(status=if(all(vapply(c('jsonlite','ggplot2'),requireNamespace,logical(1),quietly=TRUE)))0 else 42)"], capture_output=True, text=True, timeout=45)
        if result.returncode == 42:
            raise unittest.SkipTest("Vaccine R dependencies are not installed; no package downloads are attempted")
        if result.returncode:
            raise AssertionError(result.stdout + result.stderr)

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="vaccine generated QC ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "private project"
        self.root.mkdir()
        (self.root / "launch_app.R").write_text("# private synthetic test project\n")
        shutil.copytree(ROOT / "vaccine", self.root / "vaccine")
        self.values = json.loads((EXAMPLES / "example_settings.json").read_text(encoding="utf-8"))
        spec = guided_setup.schema(self.root, "vaccine")
        for field in guided_setup.fields(spec).values():
            if field["type"] == "checkbox":
                self.values[field["id"]] = True
        self.values["columns"] = {}
        for slot in spec["inputs"]:
            with (EXAMPLES / (slot["id"] + ".csv")).open(newline="", encoding="utf-8") as handle:
                reader = csv.DictReader(handle)
                headers, rows = reader.fieldnames, list(reader)
            # Exercise the mapping layer rather than relying on canonical headers.
            stream = io.StringIO(newline="")
            writer = csv.writer(stream)
            writer.writerow(["source_" + name for name in headers])
            writer.writerows([[row[name] for name in headers] for row in rows])
            content = stream.getvalue().encode("utf-8")
            guided_setup.upload(self.root, "vaccine", slot["id"], slot["id"] + ".csv", base64.b64encode(content).decode("ascii"))
            self.values["columns"][slot["id"]] = {name: "source_" + name for name in headers}

    @staticmethod
    def hashes(folder):
        return {p.relative_to(folder).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in folder.rglob("*") if p.is_file()}

    def build(self):
        invalid = guided_setup.act(self.root, "vaccine", "generate", self.values)
        self.assertTrue(invalid["report"]["errors"], "Generating without current preview must fail")
        preview = guided_setup.act(self.root, "vaccine", "validate", self.values)
        self.assertEqual(preview["report"]["errors"], [], preview["report"])
        result = guided_setup.act(self.root, "vaccine", "generate", self.values)
        self.assertEqual(result["report"]["errors"], [], result["report"])
        build = result["build"]
        self.assertEqual(build["engine"], "r")
        self.assertRegex(build["build_id"], r"^setup-[a-f0-9]{24}$")
        _, bundle = analysis_jobs.resolve_build(self.root, "vaccine", build["build_id"])
        with zipfile.ZipFile(self.root / build["zip_path"]) as archive:
            self.assertIn("analysis_bundle.json", archive.namelist())
            self.assertTrue(any(name.endswith(".sas") for name in archive.namelist()))
        return build, bundle

    def execute(self, build, should_pass=True):
        plan, _ = analysis_jobs.prepare_run(self.root, "vaccine", build["build_id"])
        folder = Path(plan["run_root"])
        result = analysis_jobs.execute(folder / "plan.json", self.rscript)
        diagnostics = (folder / "qc.json").read_text(encoding="utf-8") if (folder / "qc.json").exists() else str(result)
        self.assertEqual(result, 0 if should_pass else 1, diagnostics)
        for name in analysis_jobs.RESULTS:
            self.assertTrue((folder / name).is_file(), name)
        qc = json.loads((folder / "qc.json").read_text(encoding="utf-8"))
        manifest = json.loads((folder / "output_manifest.json").read_text(encoding="utf-8"))
        self.assertEqual(qc["passed"], should_pass)
        self.assertFalse(qc["approved"])
        self.assertFalse(manifest["approved"])
        self.assertEqual(manifest["status"], "succeeded" if should_pass else "failed")
        self.assertEqual(manifest["build_id"], build["build_id"])
        self.assertEqual(manifest["run_id"], plan["run_id"])
        if not should_pass:
            self.assertTrue(qc["errors"], "Failure must explain why execution failed")
            with (folder / "execution_status.csv").open(newline="", encoding="utf-8") as handle:
                statuses = list(csv.DictReader(handle))
            self.assertTrue(statuses)
            self.assertTrue(all(item["status"] == "failed" for item in statuses))
        with zipfile.ZipFile(folder / "results.zip") as archive:
            self.assertIn("qc.json", archive.namelist())
            self.assertIn("analysis_report.html", archive.namelist())
            self.assertNotIn("plan.json", archive.namelist())
            self.assertNotIn(str(self.root), archive.read("analysis_report.html").decode("utf-8"))
        if should_pass:
            self.assertEqual({item["id"] for item in manifest["outputs"]}, OUTPUTS)
            for item in manifest["outputs"]:
                self.assertEqual(item["status"], "completed")
                self.assertTrue(item["files"])
                for filename in item["files"]:
                    target = (folder / filename).resolve()
                    self.assertTrue(target.is_relative_to(folder.resolve()))
                    self.assertTrue(target.is_file(), filename)
            self.assertTrue(list((folder / "outputs/titer_plot").glob("*.png")))
            self.assertTrue(list((folder / "outputs/diary_profile").glob("*.png")))
        return folder, manifest

    def row(self, folder, output, **selectors):
        with (folder / "outputs" / output / "component-01.csv").open(newline="", encoding="utf-8") as handle:
            matches = [row for row in csv.DictReader(handle) if all(row[key] == value for key, value in selectors.items())]
        self.assertEqual(len(matches), 1, (output, selectors, matches))
        return matches[0]

    def test_mapped_generation_real_r_known_answers_and_immutable_reruns(self):
        # A finite whole-number day outside the selected window is excluded.
        # It must not overflow the R adapter's former 32-bit integer parser.
        diary_path = self.root / "template_inputs/vaccine/diary.csv"
        with diary_path.open(newline="", encoding="utf-8") as handle:
            reader = csv.DictReader(handle)
            headers, rows = reader.fieldnames, list(reader)
        extra = dict(rows[0], source_DAY="2147483648")
        stream = io.StringIO(newline="")
        writer = csv.DictWriter(stream, fieldnames=headers)
        writer.writeheader()
        writer.writerows([*rows, extra])
        guided_setup.upload(self.root, "vaccine", "diary", "diary-outside-window.csv", base64.b64encode(stream.getvalue().encode()).decode("ascii"))
        build, bundle = self.build()
        frozen = self.hashes(bundle)
        first, _ = self.execute(build)
        self.assertEqual(self.hashes(bundle), frozen)
        gmt = self.row(first, "immunogenicity", ARM="Vaccine", VISIT="Baseline")
        self.assertEqual(int(gmt["n_population"]), 5)
        self.assertEqual(int(gmt["n_evaluable"]), 4)
        self.assertAlmostEqual(float(gmt["geometric_mean"]), math.exp(sum(map(math.log, [10, 20, 2.5, 40])) / 4), places=10)
        gmfr = self.row(first, "fold_rise", ARM="Vaccine", VISIT="Day 28")
        self.assertEqual(int(gmfr["n_paired"]), 4)
        self.assertEqual(int(gmfr["n_unpaired"]), 1)
        self.assertAlmostEqual(float(gmfr["geometric_mean_fold_rise"]), math.exp(sum(map(math.log, [4, 4, 10, 4])) / 4), places=10)
        response = self.row(first, "response", ARM="Vaccine", VISIT="Day 28")
        self.assertEqual(int(response["n_evaluable"]), 4)
        self.assertEqual(int(response["n_responders"]), 3)
        self.assertEqual(float(response["percent"]), 75)
        safety = self.row(first, "reactogenicity", ARM="Comparator", DOSE="Dose 1", SYMPTOM="Fatigue")
        self.assertEqual([int(safety[key]) for key in ("n_dosed", "n_complete", "n_partial", "n_unassessed", "n_denominator", "n_reaction")], [5, 3, 1, 1, 3, 0])
        self.assertGreater(float(safety["upper_percent"]), 0, "Zero events must retain interval uncertainty")
        first_hashes = self.hashes(first)
        # Uploading a newer source must not change the pinned analysis revision.
        guided_setup.upload(self.root, "vaccine", "titers", "new-titers.csv", base64.b64encode((EXAMPLES / "titers.csv").read_bytes()).decode("ascii"))
        second, _ = self.execute(build)
        self.assertNotEqual(first, second)
        self.assertEqual(self.hashes(first), first_hashes)
        self.assertEqual(self.hashes(bundle), frozen)
        self.assertEqual((first / "outputs/immunogenicity/component-01.csv").read_bytes(), (second / "outputs/immunogenicity/component-01.csv").read_bytes())

    def test_untrusted_bundle_changes_are_refused_and_engine_failure_has_diagnostics(self):
        build, bundle = self.build()
        participant_path = next(p for p in bundle.rglob("*.csv") if p.name == "participants.csv")
        original = participant_path.read_bytes()
        participant_path.write_bytes(original + original.splitlines(keepends=True)[1])
        with self.assertRaises(runtime.InputError):
            analysis_jobs.resolve_build(self.root, "vaccine", build["build_id"])
        # Repin a negative fixture to simulate a generator regression. This tests
        # the numerical engine's validation independently of integrity rejection.
        manifest_path = bundle / "analysis_bundle.json"
        inventory = json.loads(manifest_path.read_text(encoding="utf-8"))
        inventory["files"][participant_path.relative_to(bundle).as_posix()] = hashlib.sha256(participant_path.read_bytes()).hexdigest()
        manifest_path.write_text(json.dumps(inventory), encoding="utf-8")
        build["bundle_sha256"] = hashlib.sha256(manifest_path.read_bytes()).hexdigest()
        history = self.root / "toolkit_configuration/vaccine.builds.json"
        history.write_text(json.dumps([build]), encoding="utf-8")
        failed, manifest = self.execute(build, should_pass=False)
        self.assertTrue((failed / "execution_error.json").is_file())
        self.assertTrue(all(item["status"] == "failed" for item in manifest["outputs"]))
        self.assertFalse(list((failed / "outputs").rglob("component-*.csv")), "Failed run must not expose partial numerical success")


if __name__ == "__main__":
    unittest.main()
