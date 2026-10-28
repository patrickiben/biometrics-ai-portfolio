"""Job adapter boundaries and real base-R execution, with no package downloads."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from toolkit_launcher import jobs


class JobTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="toolkit jobs spaces ")
        self.project = Path(self.tmp.name) / "private project" / "workspace"
        self.project.mkdir(parents=True)
        for relative in ["launch_app.R", "sim_lifecycle", "tlf_interpret", "toolkit_launcher/stub_profile.R",
                         "sas_r_automation/macro_library", "slm_wiki/macro_library", "r_tlf_pseudocode", "sas_tlf_pseudocode"]:
            source = jobs.SOURCE_ROOT / relative
            target = self.project / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            if source.is_dir():
                shutil.copytree(source, target)
            else:
                shutil.copy2(source, target)

    def tearDown(self):
        self.tmp.cleanup()

    def execute(self, plan):
        results = []
        for command in plan["commands"]:
            result = subprocess.run(command["argv"], cwd=command["cwd"], env=dict(os.environ, **command["env"]),
                                    text=True, capture_output=True, timeout=90)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            results.append(result)
        return results

    def test_fixed_actions_and_explicit_install_consent(self):
        for action in ["rm -rf /", "sandbox.run;echo bad", "shiny.fake.run"]:
            with self.assertRaises(jobs.JobError):
                jobs.build_plan(action, self.project)
        for action in ["shiny.trialmon.install", "study.install", "teeth.install"]:
            for options in [{}, {"allow_install": "true"}, {"allow_install": False}]:
                with self.subTest(action=action, options=options), self.assertRaises(jobs.JobError):
                    jobs.build_plan(action, self.project, options)
        with self.assertRaises(jobs.JobError):
            jobs.build_plan("sandbox.run", self.project, {"command": "echo injected"})
        with self.assertRaises(jobs.JobError):
            jobs.build_plan("sandbox.run", jobs.SOURCE_ROOT)

    @unittest.skipUnless(shutil.which("Rscript"), "Rscript not installed")
    def test_native_base_r_runs_in_path_with_spaces_and_preserves_checkout(self):
        original = (jobs.SOURCE_ROOT / "sim_lifecycle/out/adsl.csv").read_bytes()
        plan = jobs.build_plan("sandbox.run", self.project)
        self.assertEqual(plan["outputs"], ["sim_lifecycle/out"])
        result = self.execute(plan)[0]
        self.assertIn("STUB", result.stdout)
        self.assertIn("numeric-consistency: PASS", result.stdout)
        self.assertEqual((jobs.SOURCE_ROOT / "sim_lifecycle/out/adsl.csv").read_bytes(), original)
        self.assertEqual((self.project / "sim_lifecycle/out/adsl.csv").read_bytes(), original)
        self.assertTrue((self.project / "sim_lifecycle/out/results_summary.csv").is_file())
        self.assertTrue(Path(plan["commands"][0]["env"]["R_LIBS_USER"]).is_relative_to((self.project.parent / "runtime").resolve()))
        self.assertFalse((self.project / "runtime").exists())

    @unittest.skipUnless(shutil.which("Rscript"), "Rscript not installed")
    def test_number_validator_executes_in_correct_working_directory(self):
        result = self.execute(jobs.build_plan("interpretation.check", self.project))[0]
        self.assertIn("SELFTEST PASS", result.stdout)
        self.assertIn("REJECTED", result.stdout)

    @unittest.skipUnless(shutil.which("Rscript"), "Rscript not installed")
    def test_shiny_binding_and_bad_options(self):
        plan = jobs.build_plan("shiny.risk.run", self.project, {"port": 43210})
        self.assertEqual(plan["url"], "http://127.0.0.1:43210/")
        self.assertEqual(plan["commands"][0]["argv"][-4:], ["risk", "--no-browser", "--port", "43210"])
        self.assertTrue(plan["long_running"])
        for port in [0, 80, 65536, "8000", True]:
            with self.assertRaises(jobs.JobError):
                jobs.build_plan("shiny.risk.run", self.project, {"port": port})
        for cores in [0, 9, "2", True]:
            with self.assertRaises(jobs.JobError):
                jobs.build_plan("carryover.run", self.project, {"cores": cores})

    def test_configuration_exports_are_inert_and_neutral(self):
        with patch("subprocess.Popen", side_effect=AssertionError("Configuration must never execute")):
            result = jobs.configure_project("sas_monitor", self.project, {"study_id": "STUDY-42", "root": "/review folder/monitor"})
            text = (self.project / "sas_r_automation/macro_library/tm_config.sas").read_text()
            self.assertIn("%let CFG_STUDY = STUDY-42;", text)
            self.assertIn("%let CFG_SMTP = ;", text)
            self.assertIn("%let CFG_BACKUP = ;", text)
            self.assertNotIn("CP101", text)
            self.assertIn("sas_r_automation/macro_library/configured_monitor.sas", result["paths"])
            model = jobs.configure_project("interpretation", self.project, {"model": "local/example:1", "endpoint": "http://[::1]:11434"})
            self.assertIn("tlf_interpret/local_settings.R", model["paths"])
            settings = (self.project / "tlf_interpret/local_settings.R").read_text()
            self.assertIn('tlf.slm.ollama_model = "local/example:1"', settings)
            payload = json.loads((self.project / "toolkit_configuration/interpretation.json").read_text())
            self.assertEqual(payload["status"], "configuration only; not executed")

    def test_configuration_rejects_code_remote_endpoints_and_symlinks(self):
        cases = [("sas_monitor", {"root": "/tmp; %include evil"}), ("sas_monitor", {"smtp": "x\ny"}),
                 ("sas_monitor", {"alt_multiple": float("nan")}), ("sas_monitor", {"backup": "one@example.com two@example.com"}),
                 ("sas_tlf", {"meddra": "x, out=evil"}), ("localmind", {"endpoint": "https://example.com"}),
                 ("localmind", {"endpoint": "http://127.0.0.1.evil.test"}), ("localmind", {"endpoint": "http://user@127.0.0.1:11434"}),
                 ("localmind", {"endpoint": "http://127.0.0.1:11434/api/chat"}), ("localmind", {"seed": 1.5}),
                 ("localmind", {"unknown": "ignored"})]
        for module, value in cases:
            with self.subTest(module=module, value=value), self.assertRaises(jobs.JobError):
                jobs.configure_project(module, self.project, value)
        outside = Path(self.tmp.name) / "outside"
        outside.mkdir()
        (self.project / "toolkit_configuration").symlink_to(outside, target_is_directory=True)
        original = (self.project / "tlf_interpret/local_settings.R")
        self.assertFalse(original.exists())
        with self.assertRaises(jobs.JobError):
            jobs.configure_project("interpretation", self.project, {})
        self.assertFalse(original.exists(), "All output paths must be checked before any config is written")

    def test_runtime_selection_is_an_executable_path_not_a_command(self):
        settings = {"r_path": "/not/an/executable --do-something"}
        self.assertFalse(jobs.detect_runtimes(settings)["r"]["available"])
        with self.assertRaises(jobs.JobError):
            jobs.build_plan("sandbox.run", self.project, settings=settings)
        automatic = jobs.detect_runtimes({})
        blank_fields = jobs.detect_runtimes({"r_path": "", "quarto_path": ""})
        self.assertEqual(automatic["r"], blank_fields["r"])
        self.assertEqual(automatic["quarto"], blank_fields["quarto"])

    @unittest.skipUnless(shutil.which("Rscript"), "Rscript not installed")
    def test_private_library_precedes_inherited_r_libs_in_real_r(self):
        competing = Path(self.tmp.name) / "older-global-library"
        competing.mkdir()
        command = jobs.build_plan("sandbox.run", self.project)["commands"][0]
        probe = [command["argv"][0], "--vanilla", "-e", "cat(.libPaths(),sep='\\n')"]
        inherited = dict(os.environ, **command["env"])
        inherited["R_LIBS"] = str(competing)
        before = subprocess.check_output(probe, env=inherited, text=True).splitlines()
        self.assertEqual(Path(before[0]).resolve(), competing.resolve(), "Control must demonstrate R_LIBS taking precedence")
        controlled = dict(inherited, **command["env"])
        after = subprocess.check_output(probe, env=controlled, text=True).splitlines()
        paths = [Path(path).resolve() for path in after]
        self.assertEqual(paths[0], Path(command["env"]["R_LIBS_USER"]).resolve())
        self.assertNotIn(competing.resolve(), paths)
        self.assertGreater(len(paths), 1, "The standard R library remains available")

    @unittest.skipUnless(shutil.which("Rscript"), "Rscript not installed")
    def test_study_check_requires_exact_locked_r_and_package_versions(self):
        version = subprocess.check_output([shutil.which("Rscript"), "--vanilla", "-e",
            "cat(as.character(getRversion()),utils::packageDescription('stats',fields='Version'),sep='|')"], text=True).strip().split("|")
        folder = self.project / "study"
        folder.mkdir()
        lock = {"R": {"Version": version[0]}, "Packages": {"stats": {"Version": version[1]}}}
        lockfile = folder / "renv.lock"
        lockfile.write_text(json.dumps(lock))
        # The check never invokes Quarto; supply an existing executable so this
        # focused R-version test also runs on machines without Quarto installed.
        plan = jobs.build_plan("study.check", self.project, settings={"quarto_path": sys.executable})
        self.assertIn("All 1 locked package versions match", self.execute(plan)[0].stdout)
        for package, expected in [("stats", "0.0.0"), ("toolkitMissingPackage", "1.0.0")]:
            lock["Packages"] = {package: {"Version": expected}}
            lockfile.write_text(json.dumps(lock))
            command = jobs.build_plan("study.check", self.project, settings={"quarto_path": sys.executable})["commands"][0]
            result = subprocess.run(command["argv"], cwd=command["cwd"], env=dict(os.environ, **command["env"]),
                                    text=True, capture_output=True, timeout=30)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Restore pinned study packages", result.stderr)
            self.assertIn(package + ": expected " + expected, result.stderr)
        lock["R"]["Version"] = "0.0.0"
        lockfile.write_text(json.dumps(lock))
        command = jobs.build_plan("study.install", self.project, {"allow_install": True})["commands"][0]
        result = subprocess.run(command["argv"], cwd=command["cwd"], env=dict(os.environ, **command["env"]),
                                text=True, capture_output=True, timeout=30)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("requires R 0.0.0 exactly", result.stderr)
        self.assertIn("Runtime settings", result.stderr)
        self.assertEqual(list(Path(command["env"]["R_LIBS_USER"]).iterdir()), [], "Wrong R must fail before any package installation")

    @unittest.skipUnless(shutil.which("Rscript"), "Rscript not installed")
    def test_study_run_and_install_validate_the_complete_lock_in_fresh_processes(self):
        folder = self.project / "study"
        folder.mkdir()
        shutil.copy2(jobs.SOURCE_ROOT / "study/renv.lock", folder / "renv.lock")
        (folder / "run_all.R").write_text("stop('This study body must not run during plan construction')\n")
        run = jobs.build_plan("study.run", self.project, settings={"quarto_path": sys.executable})
        install = jobs.build_plan("study.install", self.project, {"allow_install": True})
        self.assertEqual(len(run["commands"]), 2)
        self.assertEqual(len(install["commands"]), 2)
        self.assertEqual(run["commands"][0]["argv"], install["commands"][1]["argv"])
        locked = json.loads((folder / "renv.lock").read_text())["Packages"]
        check = run["commands"][0]["argv"][-1]
        for name, package in locked.items():
            self.assertIn(json.dumps(name), check)
            self.assertIn(json.dumps(package["Version"]), check)
        self.assertIn("study-library", run["commands"][1]["env"]["R_LIBS_USER"])
        self.assertIn("expected_r", install["commands"][0]["argv"][-1])
        (folder / "renv.lock").write_text('{"R":{"Version":"4.6.0"},"Packages":{"bad;code":{"Version":"1.0"}}}')
        with self.assertRaises(jobs.JobError):
            jobs.build_plan("study.install", self.project, {"allow_install": True})


if __name__ == "__main__":
    unittest.main()
