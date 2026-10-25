#!/usr/bin/env Rscript
# Server tests for the UAT tracker, driven headless with shiny::testServer (no browser).
# Needs the app's packages: shiny, bslib, DT, ggplot2. No testthat.
# Run from the package root:  Rscript uat_irt/tests/test-server.R
# or from this folder:        Rscript test-server.R

app <- Find(function(d) file.exists(file.path(d, "app.R")), c("../shiny", "uat_irt/shiny", "shiny"))
stopifnot("found the app folder" = !is.null(app))
html <- function(x) paste(as.character(x$html), collapse = "")
has <- function(x, pattern) grepl(pattern, html(x), fixed = TRUE)

shiny::testServer(normalizePath(app), {
  # first load: every panel has content, and RAND-04 is selected so the Selected test card has
  # something to act on (the browser's table reports the same default selection once drawn)
  stopifnot(
    "KPIs"                     = identical(c(output$v_total, output$v_pass, output$v_fail, output$v_def, output$v_cov),
                                           c("29", "22", "2", "3", "97%")),
    "KPI notes"                = identical(c(output$v_total_note, output$v_pass_note, output$v_fail_note,
                                             output$v_def_note, output$v_cov_note),
                                           c("7 not passing yet", "92% of the 24 executed", "RAND-04 and SUP-03",
                                             "2 critical or major", "29 of 30 have a test")),
    "seed state is named"      = identical(output$changes, "Seed data, no changes yet"),
    "RAND-04 selected"         = rv$tests$TestID[selected()] == "RAND-04",
    "detail shows it"          = has(output$detail, "RAND-04") && has(output$detail, "Close DEF-01"),
    "gate names the blockers"  = all(vapply(c("NOT ready", "data-uat-jump=\"RAND-04\"", "data-uat-jump=\"COH-03\"",
                                              "data-uat-jump=\"SUP-03\"", "data-uat-cover=\"URS-SUP-005\""),
                                            function(p) has(output$gate, p), NA)),
    "the plot draws"           = is.list(output$plot) && nzchar(output$plot$src)
  )

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

  # marking a failing critical test as Pass (the buttons carry the test ID) lowers the count,
  # the next download carries the new status, and the change counter moves
  i <- which(rv$tests$Priority == "Critical" & rv$tests$Status != "Pass")[1]
  before <- gate()$crit_fail
  session$setInputs(test_set = list(id = rv$tests$TestID[i], status = "Pass"))
  stopifnot("one fewer critical test not passing" = gate()$crit_fail == before - 1,
            "one change since the seed" = identical(output$changes, "1 change since the seed"))
  session$setInputs(dl_tests = 2)
  back <- utils::read.csv(text = dl_payload()$content, stringsAsFactors = FALSE)
  stopifnot("download reflects the edit" = back$Status[i] == "Pass")
  session$setInputs(test_set = list(id = "NOPE-99", status = "Pass"))
  session$setInputs(test_set = list(id = "RAND-01", status = "Sideways"))
  stopifnot("unknown tests and statuses change nothing" = identical(output$changes, "1 change since the seed"))

  # closing a defect from the Selected test card, and from the defect log (typed in any case)
  session$setInputs(defect_set = list(id = "DEF-01", to = "Closed"))
  stopifnot("DEF-01 closed by its button" = rv$defects$Status[rv$defects$DefectID == "DEF-01"] == "Closed")
  r3 <- which(rv$defects$DefectID == "DEF-03")
  session$setInputs(defects_cell_edit = list(row = r3, col = 2, value = " closed "))
  stopifnot("no open critical or major defect" = gate()$open_cm == 0)
  r4 <- which(rv$defects$DefectID == "DEF-04")
  session$setInputs(defects_cell_edit = list(row = r4, col = 2, value = "maybe"))
  stopifnot("an invalid status is refused" = rv$defects$Status[r4] == "Open")
  session$setInputs(defects_cell_edit = list(row = r4, col = 4, value = "Closed"))
  stopifnot("only the Status column is edited" = rv$defects$Status[r4] == "Open")

  # the remaining blockers: COH-03 passes, and a draft test covers URS-SUP-005 -> READY
  session$setInputs(jump = "COH-03")   # selects the row in the browser; here: no error
  session$setInputs(test_set = list(id = "COH-03", status = "Pass"))
  session$setInputs(cover_gap = "URS-SUP-005")
  stopifnot(
    "draft test added"   = "SUP-05" %in% rv$tests$TestID && nrow(rv$tests) == 30,
    "requirement traced" = gate()$trace_gap == 0 && identical(output$v_cov, "100%"),
    "gate READY"         = gate()$go && has(output$gate, "READY for sign-off") && !has(output$gate, "NOT ready"),
    "download has it"    = { session$setInputs(dl_tests = 3); grepl("SUP-05", dl_payload()$content, fixed = TRUE) }
  )

  # once the table is drawn, no selection means an explained empty state (never a blank card)
  session$setInputs(tests_rows_all = seq_len(nrow(rv$tests)), tests_rows_selected = NULL)
  stopifnot("explained empty state" = has(output$detail, "No test is selected"))
  session$setInputs(tests_rows_selected = which(rv$tests$TestID == "SUP-05"))
  stopifnot("a selected row shows its detail" = has(output$detail, "SUP-05") && has(output$detail, "No defect is linked"))

  # the plot follows the dark-mode switch
  light <- output$plot$src
  session$setInputs(mode = "dark")
  stopifnot("dark plot differs" = !identical(output$plot$src, light))

  # reset restores the seed
  session$setInputs(reset = 1)
  stopifnot("reset restores the seed" = gate()$crit_fail == before && gate()$open_cm == 2 && gate()$trace_gap == 1,
            "and the change counter" = identical(output$changes, "Seed data, no changes yet"),
            "and the 29 seed tests" = nrow(rv$tests) == 29)
})

cat("UAT server: all tests passed\n")
