#!/usr/bin/env Rscript
################################################################################
# study/run_all.R: regenerate every output of the flagship worked example, in order.
# SYNTHETIC DATA ONLY. Not a validated system and not a regulatory deliverable.
#
#   Rscript study/run_all.R            (from the repository root, or from study/)
#
# Packages: pinned in study/renv.lock. If study/renv/library exists (after
# renv::restore(project = "study")), it is loaded; otherwise the current library paths
# are used. Quarto renders the results report: set QUARTO to its path if it is not on PATH.
# The stages share one R session; each script lists the objects and files it reads.
################################################################################
args <- commandArgs(trailingOnly = FALSE)
me <- sub("^--file=", "", args[grep("^--file=", args)])
study_dir <- if (length(me)) dirname(normalizePath(me)) else normalizePath("study")
setwd(dirname(study_dir))                                     # repository root
if (dir.exists(file.path(study_dir, "renv", "library")) && requireNamespace("renv", quietly = TRUE))
  renv::load(study_dir, quiet = TRUE)

stage <- function(path) {
  cat(sprintf("\n>> %s\n", path))
  sys.source(path, envir = globalenv(), keep.source = FALSE)
}

source("study/R/common.R")
stage("study/01_design/design.R")             # 1 sample size, randomization, protocol excerpt
stage("study/02_sap/sap.R")                   # 2 SAP excerpt, shells, analysis_parameters.json
stage("study/03_adam/01_sdtm.R")              # 3 SDTM-like inputs
stage("study/03_adam/02_adsl.R")              #   ADSL (core)
stage("study/03_adam/03_adpc.R")              #   ADPC
stage("study/03_adam/04_adae.R")              #   ADAE
stage("study/04_analysis/01_nca.R")           # 4 NCA (PKNCA) -> PP
stage("study/03_adam/05_adpp.R")              # 3 ADPP, exclusion rules, ADSL population flags
stage("study/03_adam/spec/build_spec.R")      #   specification (xlsx + json)
stage("study/03_adam/06_checks_xpt.R")        #   metacore/metatools checks, xportr XPT, Dataset-JSON
stage("study/04_analysis/02_be.R")            # 4 bioequivalence analysis
stage("study/04_analysis/03_tlf.R")           #   tables (RTF, HTML) and figures

## 4 Quarto results report: objects handed over through a temporary RDS (not committed)
obj <- file.path(tempdir(), "study_objects.rds")
saveRDS(list(be_results = be_results, be_supplementary = be_supplementary, be_pass = be_pass, adsl = adsl,
             exclusions = exclusions, pk_checks = pk_checks, TLF = TLF, blq_effect = blq_effect, first_point = first_point,
             scenarios = jsonlite::read_json(sp("03_adam", "sdtm", "scenarios.json")),
             design = jsonlite::read_json(sp("01_design", "design_parameters.json"))$planning,
             sap = jsonlite::read_json(sp("02_sap", "analysis_parameters.json")),
             versions = c(PKNCA = pkg_version("PKNCA"))), obj)
quarto <- Sys.getenv("QUARTO", unset = Sys.which("quarto"))
if (!nzchar(quarto)) stop("Quarto not found: set QUARTO to the quarto executable")
Sys.setenv(R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep), QUARTO_R = R.home("bin"))
cat("\n>> quarto render study/04_analysis/report/report.qmd\n")
rc <- system2(quarto, c("render", "study/04_analysis/report/report.qmd", "-P", paste0("objects:", obj), "--quiet"))
if (rc != 0) stop("Quarto render failed")

stage("study/05_qc/qc.R")                     # 5 QC ledger
stage("study/06_csr/csr.R")                   # 6 CSR section 11 text + number check
stage("study/R/pages.R")                      #   stage index pages and study/index.html

## a manifest of what produced the outputs (versions only, so reruns stay byte-identical)
write_json_det(list(
  study = STUDY$studyid, synthetic = TRUE, seed = STUDY$seed,
  r_version = paste(R.version$major, R.version$minor, sep = "."),
  packages = as.list(VERS),
  stages = c("01_design/design.R", "02_sap/sap.R", "03_adam/01_sdtm.R", "03_adam/02_adsl.R", "03_adam/03_adpc.R",
             "03_adam/04_adae.R", "04_analysis/01_nca.R", "03_adam/05_adpp.R", "03_adam/spec/build_spec.R",
             "03_adam/06_checks_xpt.R", "04_analysis/02_be.R", "04_analysis/03_tlf.R", "04_analysis/report/report.qmd",
             "05_qc/qc.R", "06_csr/csr.R", "R/pages.R"),
  results = list(be_shown = be_pass, n_be_set = sum(adsl$BEFL == "Y"),
                 qc_pass = sum(qc_ledger$status == "pass"), qc_checks = nrow(qc_ledger))),
  sp("run_manifest.json"))
cat(sprintf("\nDone: bioequivalence %s; QC %d of %d pass; outputs under study/\n",
            if (be_pass) "shown" else "not shown", sum(qc_ledger$status == "pass"), nrow(qc_ledger)))
