#!/usr/bin/env Rscript
# Unit tests for the UAT gate/KPI logic. Zero dependencies (base R only).
# Run from the package root:  Rscript uat_irt/tests/test-logic.R
# or from this folder:        Rscript test-logic.R

lp <- Find(file.exists, c("../shiny/R/logic.R", "uat_irt/shiny/R/logic.R", "shiny/R/logic.R"))
stopifnot("found logic.R" = !is.null(lp))
source(lp)

dir <- Find(function(d) file.exists(file.path(d, "test_scripts.csv")),
            c("../templates", "uat_irt/templates", "templates"))
d <- uat_load(dir)

g <- uat_gate(d$tests, d$defects, d$trace)
s <- uat_summary(d$tests, d$defects, d$trace)

stopifnot(
  "seed gate is blocked"          = !g$go,
  "two open critical/major"       = g$open_cm == 2,
  "one traceability gap"          = g$trace_gap == 1,
  "at least one critical failing" = g$crit_fail >= 1,
  "coverage < 100 with the gap"   = s$cov < 100,
  "totals add up"                 = s$pass + s$fail + s$open_now == s$total
)

# fixing every criterion makes the gate READY
t2  <- d$tests;   t2$Status[t2$Priority == "Critical"] <- "Pass"
df2 <- d$defects; df2$Status[df2$Severity %in% c("Critical", "Major")] <- "Closed"
tr2 <- d$trace;   tr2$Covered <- "Y"
stopifnot("fixing all criteria -> READY" = uat_gate(t2, df2, tr2)$go)

cat("UAT logic: all tests passed\n")
