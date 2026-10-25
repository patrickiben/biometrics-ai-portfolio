#!/usr/bin/env Rscript
# Server tests for the UAT tracker, driven headless with shiny::testServer (no browser).
# Needs the app's packages: shiny, bslib, DT, ggplot2. No testthat.
# Run from the package root:  Rscript uat_irt/tests/test-server.R
# or from this folder:        Rscript test-server.R
# What a browser adds (real mouse events, the table's paging, the phone layout) is checked by the
# deploy smoke test's interactions in apps/uat_irt/launch.json.

app <- Find(function(d) file.exists(file.path(d, "app.R")), c("../shiny", "uat_irt/shiny", "shiny"))
stopifnot("found the app folder" = !is.null(app))
html  <- function(x) paste(as.character(x$html), collapse = "")
has   <- function(x, pattern) grepl(pattern, html(x), fixed = TRUE)
plain <- function(x) gsub("\\s+", " ", trimws(gsub("<[^>]+>", "", html(x))))

shiny::testServer(normalizePath(app), {
  status <- function(id) rv$defects$Status[rv$defects$DefectID == id]
  mark   <- function(id, st) session$setInputs(test_set = list(id = id, status = st))

  # first load: every panel has content, and RAND-04 is selected so the Selected test card has
  # something to act on (the browser's table reports the same default selection once drawn)
  stopifnot(
    "KPIs"                     = identical(c(output$v_total, output$v_pass, output$v_fail, output$v_def, output$v_cov),
                                           c("29", "22", "2", "3", "97%")),
    "KPI notes"                = identical(c(output$v_total_note, output$v_pass_note, plain(output$v_fail_note),
                                             output$v_def_note, output$v_cov_note),
                                           c("7 not passing yet", "92% of the 24 executed", "RAND-04 and SUP-03",
                                             "2 critical or major", "29 of 30 have a test; 24 tested")),
    "failing IDs never break"  = has(output$v_fail_note, "uat-nw"),
    "seed state is named"      = identical(output$changes, "Seed data, no changes yet"),
    "RAND-04 selected"         = rv$tests$TestID[selected()] == "RAND-04",
    "detail shows it"          = has(output$detail, "RAND-04") && has(output$detail, "Close DEF-01"),
    "DEF-01 waits for a retest" = has(output$detail, "disabled") && has(output$detail, "Close it once RAND-04 passes its retest"),
    "gate names the blockers"  = all(vapply(c("NOT ready", "data-uat-jump=\"RAND-04\"", "data-uat-jump=\"COH-03\"",
                                              "data-uat-jump=\"SUP-03\"", "data-uat-cover=\"URS-SUP-005\"",
                                              "data-uat-jump=\"ENR-03\"", "5 tests not run yet"),
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

  # a defect closes only after its test passes a retest: DEF-01 stays Open while RAND-04 fails
  session$setInputs(defect_set = list(id = "DEF-01", to = "Closed"))
  stopifnot("DEF-01 refused before the retest" = status("DEF-01") == "Open",
            "and nothing counts as changed"    = identical(output$changes, "Seed data, no changes yet"))

  # marking a failing critical test as Pass (the buttons carry the test ID) lowers the count,
  # the next download carries the new status, the change counter moves, and its defect can close
  i <- which(rv$tests$Priority == "Critical" & rv$tests$Status != "Pass")[1]
  before <- gate()$crit_fail
  mark(rv$tests$TestID[i], "Pass")
  stopifnot("one fewer critical test not passing" = gate()$crit_fail == before - 1,
            "one change since the seed" = identical(output$changes, "1 change since the seed"),
            "DEF-01 can now be closed"  = !has(output$detail, "disabled"))
  session$setInputs(dl_tests = 2)
  back <- utils::read.csv(text = dl_payload()$content, stringsAsFactors = FALSE)
  stopifnot("download reflects the edit" = back$Status[i] == "Pass")
  mark("NOPE-99", "Pass")
  mark("RAND-01", "Sideways")
  stopifnot("unknown tests and statuses change nothing" = identical(output$changes, "1 change since the seed"))

  # closing a defect from the Selected test card, and from the defect log (typed in any case)
  session$setInputs(defect_set = list(id = "DEF-01", to = "Closed"))
  stopifnot("DEF-01 closed by its button" = status("DEF-01") == "Closed")
  r3 <- which(rv$defects$DefectID == "DEF-03")
  session$setInputs(defects_cell_edit = list(row = r3, col = 2, value = " closed "))
  stopifnot("DEF-03 refused while SUP-03 fails" = status("DEF-03") == "Open" && gate()$open_cm == 1)
  mark("SUP-03", "Pass")
  session$setInputs(defects_cell_edit = list(row = r3, col = 2, value = " closed "))
  stopifnot("no open critical or major defect" = gate()$open_cm == 0 && status("DEF-03") == "Closed")
  r4 <- which(rv$defects$DefectID == "DEF-04")
  session$setInputs(defects_cell_edit = list(row = r4, col = 2, value = "maybe"))
  stopifnot("an invalid status is refused" = status("DEF-04") == "Open")
  session$setInputs(defects_cell_edit = list(row = r4, col = 4, value = "Closed"))
  stopifnot("only the Status column is edited" = status("DEF-04") == "Open")

  # a fix that no longer passes its retest blocks the gate again; so does a failure with no defect
  mark("RAND-04", "Fail")
  stopifnot("a closed defect whose test fails blocks" = gate()$unretested == 1 && !gate()$defects_ok &&
              has(output$gate, "closed before its test passed a retest") && has(output$gate, "DEF-01 (RAND-04 is Fail)"),
            "listed once, not also as a failure with no defect" = gate()$untracked == 0)
  mark("RAND-04", "Pass")
  mark("ENR-03", "Fail")
  stopifnot("a failure with no open defect blocks" = gate()$untracked == 1 && has(output$gate, "with no open defect logged"))
  mark("ENR-03", "Pass")
  stopifnot("both cleared" = gate()$defects_ok)

  # the table is drawn: it reports its row list (data rows in its order and search)
  session$setInputs(tests_rows_all = seq_len(nrow(rv$tests)), tests_rows_selected = which(rv$tests$TestID == "RAND-04"))

  # COH-03 passes and a draft test covers URS-SUP-005: traced, but the gate waits until it is run
  session$setInputs(jump = "COH-03")   # selects the row in the browser; here: no error
  mark("COH-03", "Pass")
  session$setInputs(cover_gap = "URS-SUP-005")
  stopifnot(
    "draft test added"       = "SUP-05" %in% rv$tests$TestID && nrow(rv$tests) == 30,
    "requirement traced"     = gate()$trace_gap == 0 && identical(output$v_cov, "100%"),
    "but not READY yet"      = !gate()$go && has(output$gate, "data-uat-jump=\"SUP-05\"") && has(output$gate, "NOT ready"),
    "paged once the table has the row" = identical(pending_row()$row, 30L)
  )
  session$setInputs(tests_rows_all = seq_len(30))
  stopifnot("the new row's page was chosen" = is.null(pending_row()))

  # a chip whose test a search hides clears the search, then pages to it
  session$setInputs(tests_search = "Randomization", tests_rows_all = 1:6)
  session$setInputs(jump = "SUP-03")
  stopifnot("waiting for the cleared search" = identical(pending_row()$row, which(rv$tests$TestID == "SUP-03")))
  session$setInputs(tests_search = "", tests_rows_all = seq_len(30))
  stopifnot("paged after the search cleared" = is.null(pending_row()))

  # run the rest: the gate turns READY, and names the open minor defect for the person who signs
  for (id in c("DISP-03", "UNBL-03", "NOT-02", "SUP-05")) mark(id, "Pass")
  stopifnot(
    "gate READY"            = gate()$go && has(output$gate, "READY for sign-off") && !has(output$gate, "NOT ready"),
    "minor defect named"    = has(output$gate, "fix or waive the open minor defect DEF-04"),
    "KPIs at READY"         = identical(c(output$v_pass, output$v_fail, output$v_def, output$v_cov_note),
                                        c("30", "0", "1", "All 30 have a test, all tested")),
    "download has it"       = { session$setInputs(dl_tests = 3); grepl("SUP-05", dl_payload()$content, fixed = TRUE) }
  )

  # once the table is drawn, no selection means an explained empty state (never a blank card)
  session$setInputs(tests_rows_selected = NULL)
  stopifnot("explained empty state" = has(output$detail, "No test is selected"))
  session$setInputs(tests_rows_selected = which(rv$tests$TestID == "SUP-05"))
  stopifnot("a selected row shows its detail" = has(output$detail, "SUP-05") && has(output$detail, "No defect is logged"))

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
