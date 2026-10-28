"""Input contracts are executed against synthetic data with all other columns removed."""
from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from toolkit_launcher.analysis_contracts import required_columns, optional_columns

DESIGNS = ("parallel", "crossover", "single_sequence", "sad", "mad")
R_CHECK = r'''
suppressPackageStartupMessages({ library(dplyr); library(tidyr); library(tibble); library(ggplot2) })
source("r_tlf_pseudocode/00_setup_helpers.R")
source("r_tlf_pseudocode/01_analysis_models.R")
source("toolkit_launcher/tests/analysis_fixtures.R")
args <- commandArgs(trailingOnly=TRUE)
contracts <- jsonlite::fromJSON(args[1], simplifyVector=FALSE)
results <- list()
for (design in names(contracts)) {
  fixture <- analysis_fixture(design)
  options(tfl.settings=analysis_fixture_settings(design))
  for (stem in names(contracts[[design]])) {
    fields <- contracts[[design]][[stem]]
    e <- new.env(parent=globalenv())
    e$adam <- list(); e$components <- list()
    failures <- character()
    for (slot in names(fields)) {
      columns <- unlist(fields[[slot]], use.names=FALSE)
      missing <- setdiff(columns,names(fixture[[slot]]))
      if(length(missing))failures<-c(failures,paste(slot,"fixture lacks",paste(missing,collapse=",")))
      else e$adam[[slot]]<-fixture[[slot]][,columns,drop=FALSE]
    }
    e$source <- function(...)invisible(NULL)
    e$setup <- function(...)list(study="SYNTHETIC-QC",out=tempdir())
    e$print <- function(x,...) {
      if(inherits(x,"ggplot"))ggplot2::ggplot_build(x)
      else if(!is.data.frame(x))stop("Unexpected output component: ",paste(class(x),collapse=","))
      e$components[[length(e$components)+1L]]<-x
      invisible(x)
    }
    error <- if(length(failures))paste(failures,collapse="; ")else tryCatch({
      suppressWarnings(sys.source(file.path("r_tlf_pseudocode",design,paste0(stem,".R")),envir=e))
      if(!length(e$components))stop("No output components")
      NULL
    },error=function(err)conditionMessage(err))
    results[[paste(design,stem,sep="/")]]<-list(status=if(is.null(error))"pass"else"fail",error=error,components=length(e$components))
  }
}
jsonlite::write_json(results,args[2],auto_unbox=TRUE,pretty=TRUE,null="null")
failed<-names(results)[vapply(results,function(x)x$status=="fail",logical(1))]
for(name in failed)cat(name,": ",results[[name]]$error,"\n",sep="")
cat(length(results)-length(failed),"/",length(results),"restricted-input analyses passed\n")
quit(status=if(length(failed))1L else 0L)
'''


class AnalysisContractsTests(unittest.TestCase):
    def contracts(self):
        return {design: {path.stem: {slot: sorted(columns) for slot, columns in required_columns(design, path.stem).items()}
                        for path in sorted((ROOT / "r_tlf_pseudocode" / design).glob("*.R"))}
                for design in DESIGNS}

    def test_every_r_output_has_an_explicit_contract(self):
        contracts = self.contracts()
        self.assertEqual(sum(map(len, contracts.values())), 221)
        for outputs in contracts.values():
            for contract in outputs.values():
                self.assertTrue(contract)
                for columns in contract.values():
                    self.assertIn("USUBJID", columns)

    def test_dynamic_baseline_requires_only_the_selected_characteristics(self):
        result = required_columns("parallel", "t_baseline_characteristics", {"baseline_continuous": "AGE, WEIGHTBL", "baseline_categorical": "SEX"})
        self.assertEqual(result["adsl"], {"USUBJID", "SAFFL", "TRT01A", "AGE", "WEIGHTBL", "SEX"})
        self.assertNotIn("DISSEVBL", result["adsl"])
        self.assertNotIn("HEPATGR1", result["adsl"])
        result["adsl"].add("MUTATION")
        self.assertNotIn("MUTATION", required_columns("parallel", "t_baseline_characteristics")["adsl"])

    def test_optional_ada_classifications_do_not_block_unclassified_data(self):
        required = required_columns("parallel", "t_ada_summary")
        self.assertEqual(required["adis"], {"USUBJID", "ADAFL", "TRT01A"})
        self.assertIn("TEADAFL", optional_columns("parallel", "t_ada_summary")["adis"])
        self.assertIn("NABFL", optional_columns("parallel", "t_ada_summary")["adis"])

    @unittest.skipUnless(shutil.which("Rscript"), "Rscript is not installed")
    def test_all_221_execute_with_only_contract_columns(self):
        probe = subprocess.run(["Rscript", "-e", 'p<-c("jsonlite","dplyr","tidyr","tibble","ggplot2","lmerTest","emmeans","nlme","rtables");quit(status=if(all(vapply(p,requireNamespace,logical(1),quietly=TRUE)))0 else 42)'], capture_output=True, text=True, timeout=60)
        if probe.returncode == 42:
            self.skipTest("Required analysis packages are not installed; no packages downloaded")
        self.assertEqual(probe.returncode, 0, probe.stderr)
        with tempfile.TemporaryDirectory(prefix="analysis-contracts-") as directory:
            directory = Path(directory)
            contract_path = directory / "contracts.json"
            script_path = directory / "check.R"
            report_path = directory / "report.json"
            contract_path.write_text(json.dumps(self.contracts()), encoding="utf-8")
            script_path.write_text(R_CHECK, encoding="utf-8")
            result = subprocess.run(["Rscript", str(script_path), str(contract_path), str(report_path)], cwd=ROOT, capture_output=True, text=True, timeout=300)
            # Optional durable evidence outside the product source tree.
            evidence = os.environ.get("ANALYSIS_CONTRACT_REPORT")
            if evidence and report_path.exists():
                Path(evidence).write_text(report_path.read_text(encoding="utf-8"), encoding="utf-8")
            self.assertEqual(result.returncode, 0, result.stdout + "\n" + result.stderr)
            report = json.loads(report_path.read_text(encoding="utf-8"))
            self.assertEqual(len(report), 221)
            self.assertTrue(all(item["status"] == "pass" for item in report.values()))


if __name__ == "__main__":
    unittest.main(verbosity=2)
