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
    def test_shared_analysis_sources_preserve_bytes_and_enforce_public_boundaries(self):
        helper = ROOT / ".github/pages/stage_app.R"
        code = "source(" + json.dumps(str(helper)) + ")\n" + r'''
dir.create("public"); dir.create("stage")
writeLines("canonical analysis source", "public/analysis.R")
writeLines("private contents", "private.env")
writeLines("app", "stage/app.R")
writeLines("", ".nojekyll")
stopifnot(identical(public_source_path(".nojekyll"), normalizePath(".nojekyll", winslash="/")))
files <- "public/analysis.R"
entry <- function(from="public/analysis.R", to="vaccine/analysis.R") list(from=from,to=to)
bad <- function(entries) {
  before <- list.files("stage",recursive=TRUE,all.files=TRUE)
  failure <- tryCatch({stage_app_shared(list(extra_files=entries),files,"stage");FALSE},error=function(e)TRUE)
  stopifnot(failure,identical(before,list.files("stage",recursive=TRUE,all.files=TRUE)))
}
bad(list(entry(from="private.env")))
bad(list(entry(to="../escape.R")))
bad(list(entry(to="/absolute.R")))
bad(list(entry(to="folder/../escape.R")))
bad(list(entry(to="app.R")))
bad(list(entry(to="portfolio_app.R")))
bad(list(entry(),entry()))
bad(list(entry(),entry(to="../../escape.R")))
bad(list(list(from="public/analysis.R")))
stage_app_shared(list(extra_files=list(entry())),files,"stage")
stopifnot(identical(readBin("public/analysis.R","raw",1000),readBin("stage/vaccine/analysis.R","raw",1000)))
stopifnot(identical(stage_app_shared(list(),files,"stage"),character()))
if (.Platform$OS.type != "windows") {
  outside <- tempfile("outside-checkout-"); dir.create(outside)
  writeLines("PRIVATE OUTSIDE CHECKOUT",file.path(outside,"analysis.R"))
  stopifnot(file.symlink(outside,"linked"))
  files <- c(files,"linked/analysis.R")
  bad(list(entry(from="linked/analysis.R",to="outside.R")))
  stopifnot(inherits(try(public_source_path("linked/analysis.R"),silent=TRUE),"try-error"))
  unlink("linked"); unlink(outside,recursive=TRUE)
  stopifnot(file.symlink(normalizePath("public"),"linked"))
  bad(list(entry(from="linked/analysis.R",to="inside-link.R")))
  unlink("linked")
}
cat("Shared source bytes preserved; private, traversal and overwrite cases rejected.\n")
'''
        with tempfile.TemporaryDirectory(prefix="app shared sources ") as directory:
            script = Path(directory) / "check.R"
            script.write_text(code, encoding="utf-8")
            result = subprocess.run(["Rscript", str(script)], cwd=directory, text=True,
                                    capture_output=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)

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
                 "demo/shiny/LAUNCHER.LOG", ".biostat-toolkit/projects/private.csv",
                 ".launcher-session.json", ".toolkit.lock", "launcher-settings.json",
                 "project.json", "toolkit_configuration/sas_monitor.json", "input-backups/private.csv", "template_inputs/r_tlf/adsl.csv", "template_outputs/r_tlf/private.zip", "template_runs/r_tlf/results.zip"]
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
