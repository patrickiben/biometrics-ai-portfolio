#!/usr/bin/env Rscript
# Server tests for the UAT tracker, driven headless with shiny::testServer (no browser).
# Needs the app's packages: shiny, bslib, DT, ggplot2. No testthat.
# Run from the package root:  Rscript uat_irt/tests/test-server.R
# or from this folder:        Rscript test-server.R

app <- Find(function(d) file.exists(file.path(d, "app.R")), c("../shiny", "uat_irt/shiny", "shiny"))
stopifnot("found the app folder" = !is.null(app))

shiny::testServer(normalizePath(app), {
  # the download is built in the browser from a CSV string sent by R (works under Shinylive)
  stopifnot("no download before the click" = is.null(dl_payload()))
  session$setInputs(dl_tests = 1)
  p <- dl_payload()
  back <- utils::read.csv(text = p$content, stringsAsFactors = FALSE, check.names = FALSE)
  stopifnot(
    "file name says synthetic" = identical(p$filename, "SYNTHETIC_uat_test_results.csv"),
    "CSV MIME type"            = identical(p$type, "text/csv"),
    "same columns as the data" = identical(names(back), names(rv$tests)),
    "same rows as the data"    = identical(back$TestID, rv$tests$TestID),
    "same statuses"            = identical(back$Status, rv$tests$Status)
  )

  # marking the selected critical failing test as Pass lowers the critical count,
  # and the next download carries the new status
  i <- which(rv$tests$Priority == "Critical" & rv$tests$Status != "Pass")[1]
  before <- gate()$crit_fail
  session$setInputs(tests_rows_selected = i, set_status = "Pass")
  stopifnot("one fewer critical test not passing" = gate()$crit_fail == before - 1)
  session$setInputs(dl_tests = 2)
  back <- utils::read.csv(text = dl_payload()$content, stringsAsFactors = FALSE)
  stopifnot("download reflects the edit" = back$Status[i] == "Pass")

  # closing every open critical or major defect clears that criterion
  for (r in which(rv$defects$Status == "Open" & rv$defects$Severity %in% c("Critical", "Major")))
    session$setInputs(defects_cell_edit = list(row = r, col = 2, value = "Closed"))
  stopifnot("no open critical or major defect" = gate()$open_cm == 0)

  # reset restores the seed
  session$setInputs(reset = 1)
  stopifnot("reset restores the seed" = gate()$crit_fail == before && gate()$open_cm == 2)
})

cat("UAT server: all tests passed\n")
