#!/usr/bin/env Rscript
# Unit tests for the Study Lifecycle Monitor scoring. Base R only.
# Run:  Rscript lifecycle_dashboard/tests/test-logic.R

lp <- Find(file.exists, c("../shiny/R/logic.R", "lifecycle_dashboard/shiny/R/logic.R", "shiny/R/logic.R"))
stopifnot("found logic.R" = !is.null(lp)); source(lp)
dir <- Find(function(d) file.exists(file.path(d, "studies.csv")),
            c("../shiny/data", "lifecycle_dashboard/shiny/data", "shiny/data"))
d <- lifecycle_load(dir)
st <- score_portfolio(d)
k  <- lifecycle_kpis(st, d)
sg <- lifecycle_signals(st, d)

stopifnot(
  "8 studies"               = nrow(st) == 8,
  "scores in 0..100"        = all(st$overall >= 0 & st$overall <= 100),
  "CP-108 is at risk (red)" = st$rag[st$id == "CP-108"] == "red",
  "at least one at-risk"    = k$at_risk >= 1,
  "portfolio open queries positive" = k$open_q > 0,
  "signals ranked red-first" = nrow(sg) == 0 || sg$sev[1] == "red"
)

# scoring monotonic: more open queries never lowers the Data score
s <- d$studies[d$studies$id == "CP-103", ]
lo <- score_study(within(s, open_queries <- 5), 0)$Data
hi <- score_study(within(s, open_queries <- 120), 0)$Data
stopifnot("more open queries -> higher data risk" = hi >= lo)

cat("Lifecycle logic: all tests passed\n")
