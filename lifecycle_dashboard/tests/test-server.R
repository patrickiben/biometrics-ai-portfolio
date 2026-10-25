#!/usr/bin/env Rscript
# Server tests for the Study Lifecycle Monitor, driven headless with shiny::testServer (no browser).
# Needs the app's packages: shiny, bslib, DT, ggplot2. No testthat.
# Run:  Rscript lifecycle_dashboard/tests/test-server.R   (or from this folder)

app <- Find(function(d) file.exists(file.path(d, "app.R")),
            c("../shiny", "lifecycle_dashboard/shiny", "shiny"))
stopifnot("found the app folder" = !is.null(app))
app <- normalizePath(app)

# The what-if sliders open on the selected study's own values, so the first values a browser
# sends cannot rewrite that study (the app used to show At risk 0 for a moment at startup).
e <- new.env()
old <- setwd(app); sys.source("app.R", envir = e); setwd(old)
ui <- as.character(e$ui)
slider_from <- function(id) as.numeric(sub('.*data-from="([0-9.]+)".*', "\\1",
  regmatches(ui, regexpr(sprintf('<input[^>]*id="%s"[^>]*>', id), ui))))
s0 <- e$seed$studies[e$seed$studies$id == "CP-108", ]
stopifnot(
  "open-queries slider starts at CP-108's value" = slider_from("openq") == s0$open_queries,
  "double-programming slider starts at CP-108's value" = slider_from("dblprog") == s0$dbl_prog_pct
)

seed <- e$seed   # app.R's globals are not visible inside testServer, so pass the seed in
shiny::testServer(app, {
  k0 <- lifecycle_kpis(score_portfolio(seed), seed)
  # the values a browser sends when the page opens
  session$setInputs(study = "CP-108", openq = s0$open_queries, dblprog = s0$dbl_prog_pct)
  stopifnot(
    "opening the app leaves the data as loaded" = identical(rv$studies, seed$studies),
    "KPIs at startup match the logic"            = identical(kpi()[c("at_risk", "open_q")], k0[c("at_risk", "open_q")]),
    "CP-108 is at risk at startup"              = kpi()$at_risk >= 1
  )
  # a what-if moves the score; reset restores the data
  session$setInputs(openq = 150)
  stopifnot("what-if raises portfolio open queries" = kpi()$open_q == k0$open_q - s0$open_queries + 150)
  session$setInputs(reset = 1)
  stopifnot("reset restores the data" = identical(rv$studies, seed$studies))
})

cat("Lifecycle server: all tests passed\n")
