#!/usr/bin/env Rscript
# Run the TRIALMON tests: rule boundaries, the shipped synthetic study, and the Shiny server
# through shiny::testServer. Needs testthat (>= 3.0) plus the app's packages (shiny, bslib, DT,
# ggplot2). To use a private library, set TRIALMON_RLIB to its path.
# Run from anywhere:  Rscript sasr_monitoring_wiki/trialmon_tests/run-tests.R
lib <- Sys.getenv("TRIALMON_RLIB")
if (nzchar(lib)) .libPaths(c(lib, .libPaths()))
arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
here <- if (length(arg)) dirname(normalizePath(sub("^--file=", "", arg))) else "."
res <- testthat::test_dir(file.path(here, "testthat"), reporter = "summary", stop_on_failure = TRUE)
df <- as.data.frame(res)
cat(sprintf("TRIALMON tests: %d expectations in %d tests, %d failed, %d skipped\n",
            sum(df$nb), nrow(df), sum(df$failed), sum(df$skipped)))
