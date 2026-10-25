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

# Data without CP-108 (for example a CTMS export): the app still starts, on the first study.
# Runs on a temporary copy of the app with CP-108 renamed to CP-208 in every data file.
tmp <- file.path(tempfile("lifecycle-"), "shiny")
dir.create(tmp, recursive = TRUE)
invisible(file.copy(list.files(app, full.names = TRUE), tmp, recursive = TRUE))
for (f in list.files(file.path(tmp, "data"), pattern = "[.]csv$", full.names = TRUE))
  writeLines(gsub("CP-108", "CP-208", readLines(f), fixed = TRUE), f)
e2 <- new.env()
old <- setwd(tmp); built <- tryCatch({ sys.source("app.R", envir = e2); TRUE },
                                    error = function(err) conditionMessage(err)); setwd(old)
stopifnot("the app builds when the data have no CP-108" = isTRUE(built))
ui <- as.character(e2$ui)
first <- sort(e2$seed$studies$id)[1]
s1 <- e2$seed$studies[e2$seed$studies$id == first, ]
stopifnot(
  "the renamed data have no CP-108"              = !"CP-108" %in% e2$seed$studies$id,
  "it opens on the first study"                  = e2$OPEN_ID == first,
  "open-queries slider starts at that study's value" = slider_from("openq") == s1$open_queries,
  "double-programming slider starts at that study's value" = slider_from("dblprog") == s1$dbl_prog_pct
)
seed2 <- e2$seed
shiny::testServer(tmp, {
  session$setInputs(study = first, openq = s1$open_queries, dblprog = s1$dbl_prog_pct)
  stopifnot("opening the app leaves the renamed data as loaded" = identical(rv$studies, seed2$studies),
            "the KPIs compute"                                  = kpi()$n == nrow(seed2$studies))
})
unlink(dirname(tmp), recursive = TRUE)

cat("Lifecycle server: all tests passed\n")
