#!/usr/bin/env Rscript
# Real Shiny/DT output evaluation plus malformed browser-message regressions.
app <- normalizePath("risk_monitor/shiny")
shiny::testServer(app, {
  session$flushReact(); stopifnot(!bw$active())
  session$setInputs(bw_action = list(action = "example", generation = 1, nonce = 1))
  session$flushReact(); stopifnot(bw$active())
  initial <- rv$signals
  session$setInputs(tier = "All", sig = initial$id[1], level = as.character(initial$level[1]))
  stopifnot(identical(rv$signals, initial), is.finite(ov()$score))
  # Previously seven data columns had eight display labels, breaking rendering.
  stopifnot(nchar(paste(output$signals, collapse = "")) > 0)
  session$setInputs(tier = "Study")
  stopifnot(nchar(paste(output$signals, collapse = "")) > 0)
  before <- rv$signals
  session$setInputs(level = "unknown")
  session$setInputs(signals_rows_selected = 9999)
  stopifnot(identical(rv$signals, before), is.finite(ov()$score))
})
cat("Risk Shiny server: table rendering and invalid messages passed\n")
