"""Exercise the R launcher as a real subprocess; no packages are downloaded."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
RSCRIPT = shutil.which("Rscript")


@unittest.skipUnless(RSCRIPT, "Rscript is not installed")
class LauncherTests(unittest.TestCase):
    def run_launcher(self, *arguments, cwd=None, env=None):
        return subprocess.run([RSCRIPT, str(ROOT / "launch_app.R"), *arguments], cwd=cwd,
                              env=env, text=True, capture_output=True, timeout=60)

    def test_list_works_outside_repository(self):
        with tempfile.TemporaryDirectory(prefix="toolkit launch cwd ") as directory:
            result = self.run_launcher("--list", cwd=directory)
        self.assertEqual(result.returncode, 0, result.stderr)
        for name in ("trialmon", "lifecycle", "uat", "risk", "hours"):
            self.assertIn(name, result.stdout)

    def test_unknown_app_and_invalid_port_fail_before_start(self):
        for arguments in [("unknown-app",), ("trialmon", "--port", "0"), ("trialmon", "--port", "65536")]:
            with self.subTest(arguments=arguments):
                result = self.run_launcher(*arguments)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Toolkit launcher:", result.stderr)
                self.assertNotIn("Listening on", result.stdout + result.stderr)

    def test_check_reports_paths_without_launch_or_creating_library(self):
        with tempfile.TemporaryDirectory(prefix="toolkit check cwd ") as directory:
            library = Path(directory) / "not-created-library"
            env = dict(os.environ, BIOMETRICS_R_LIB=str(library))
            result = self.run_launcher("--check", "trialmon", cwd=directory, env=env)
            self.assertFalse(library.exists(), "A read-only check must not create a library")
        self.assertIn(str(ROOT), result.stdout)
        self.assertIn("shiny", result.stdout)
        self.assertIn("bslib", result.stdout)
        self.assertIn(str(library), result.stdout)
        self.assertNotIn("Listening on", result.stdout + result.stderr)
        if result.returncode:
            self.assertIn("dependencies", result.stderr)
        else:
            self.assertIn("Ready: trialmon", result.stdout)


if __name__ == "__main__":
    unittest.main()
