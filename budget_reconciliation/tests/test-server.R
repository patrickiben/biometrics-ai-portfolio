#!/usr/bin/env Rscript
# Fractional-hour edits render; invalid edits cannot fabricate available hours.
app <- normalizePath("budget_reconciliation/shiny")
shiny::testServer(app, {
  session$setInputs(need = 59.5, contingency = 40)
  stopifnot(fh()$shortfall == .5, grepl("0.5 h", paste(output$verdict$html, collapse = ""), fixed = TRUE))
  before <- rv$ledger
  for (value in c("-100", "Inf", "0", "not a number")) {
    session$setInputs(ledger_cell_edit = list(row = 1, col = 4, value = value))
    stopifnot(identical(rv$ledger, before))
  }
  session$setInputs(ledger_cell_edit = list(row = 999, col = 4, value = "100"))
  stopifnot(identical(rv$ledger, before))
  session$setInputs(ledger_cell_edit = list(row = 1, col = 4, value = "78.5"))
  stopifnot(rv$ledger$eac[1] == 78.5, metrics()$eac == 831.5, fh()$shortfall == 1)
  stopifnot(grepl("831.5 h", output$v_eac, fixed = TRUE))
  session$setInputs(need = 45, ledger_cell_edit = list(row = 1, col = 4, value = "147"))
  stopifnot(metrics()$findable == -10, fh()$shortfall == 55,
            fh()$request_shortfall == 45, fh()$baseline_deficit == 10,
            output$v_cont == "0 h", output$v_find == "-10 h",
            grepl("Total funding gap: 55 h", output$verdict$html, fixed = TRUE),
            grepl("uses 0 h internally", output$verdict$html, fixed = TRUE))
})
cat("Find-hours Shiny server: fractional hours and invalid edits passed\n")
