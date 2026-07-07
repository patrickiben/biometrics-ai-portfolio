#!/usr/bin/env Rscript
# Unit tests for the find-hours logic. Zero dependencies (base R only).
# Run from the package root:  Rscript budget_reconciliation/tests/test-logic.R
# or from this folder:        Rscript test-logic.R

lp <- Find(file.exists, c("../shiny/R/logic.R", "budget_reconciliation/shiny/R/logic.R", "shiny/R/logic.R"))
stopifnot("found logic.R" = !is.null(lp))
source(lp)

d <- hours_load()
m <- hours_metrics(d$ledger, d$contingency)

stopifnot(
  "planned totals 850"   = m$planned == 850,
  "eac totals 831"       = m$eac == 831,
  "net slack 19"         = m$net_slack == 19,
  "contingency 40"       = m$contingency == 40,
  "net findable 59"      = m$findable == 59
)

# a 45 h ask is absorbable; a 90 h ask needs a 31 h change order
a45 <- find_hours(45, d$ledger, d$contingency)
a90 <- find_hours(90, d$ledger, d$contingency)
stopifnot(
  "45 h absorbable"          = a45$absorbable && a45$shortfall == 0,
  "90 h -> 31 h change order" = !a90$absorbable && a90$shortfall == 31,
  "sourcing order (slack first)" = a90$from_slack == 19 && a90$from_cont == 40
)

cat("find-hours logic: all tests passed\n")
