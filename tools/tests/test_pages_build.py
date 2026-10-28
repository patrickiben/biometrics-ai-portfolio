"""Exercise the Pages build's actual R privacy filter on synthetic path names."""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


@unittest.skipUnless(shutil.which("Rscript"), "Rscript is not installed")
class PagesBuildTests(unittest.TestCase):
    def test_runtime_files_are_excluded_from_static_and_app_file_sets(self):
        source = (ROOT / ".github/pages/build_site.R").read_text()
        statements = [line for line in source.splitlines()
                      if line.startswith("private_runtime <-") or line == "files <- files[!private_runtime]"]
        self.assertEqual(len(statements), 3)
        files = ["index.html", ".env", ".env.local", "config/shared.env",
                 "config/shared.env.local", "config/shared.env.example", ".env.example",
                 "demo/shiny/app.R", "demo/shiny/local.env", "demo/shiny/STATE.SQLITE3-WAL",
                 "demo/shiny/state.db-shm", "demo/shiny/state.sqlite-journal",
                 "demo/shiny/preview.eml", "demo/shiny/data/demo.csv",
                 "config.json", "demo/shiny/config.json", "demo/shiny/CONFIG.JSON",
                 ".open-study-tracker/anything.txt", "demo/shiny/.open-study-tracker/secrets.txt",
                 "mail-preview/index.html", "demo/shiny/mail-preview/notice.txt",
                 "demo/shiny/.desktop-state.json", ".desktop.lock", "launcher.log",
                 "demo/shiny/LAUNCHER.LOG"]
        code = "files <- c(" + ",".join(map(json.dumps, files)) + ")\n" + "\n".join(statements)
        # Reuse the app staging selection from the build, with the filtered list.
        selection = next(line.strip() for line in source.splitlines() if line.strip().startswith("src <- files[startsWith"))
        code += "\nwriteLines(files)\na <- list(source='demo/shiny')\n" + selection
        code += "\nstopifnot(identical(src, c('demo/shiny/app.R','demo/shiny/data/demo.csv')))\n"
        with tempfile.TemporaryDirectory(prefix="publication filter ") as directory:
            script = Path(directory) / "check.R"
            script.write_text(code)
            result = subprocess.run(["Rscript", str(script)], text=True, capture_output=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), ["index.html", "config/shared.env.example", ".env.example",
                                                     "demo/shiny/app.R", "demo/shiny/data/demo.csv"])


if __name__ == "__main__":
    unittest.main()
