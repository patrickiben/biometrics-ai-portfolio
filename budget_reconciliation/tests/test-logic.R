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

reject <- function(expr) inherits(try(force(expr), silent = TRUE), "try-error")
for (bad in c(-1, Inf, NA_real_, NaN)) {
  x <- d$ledger; x$eac[1] <- bad
  stopifnot(reject(hours_metrics(x)), reject(find_hours(bad, d$ledger)),
            reject(hours_metrics(d$ledger, bad)))
}
x <- d$ledger; x$eac[1] <- x$actual[1] - 1
stopifnot(reject(hours_metrics(x)))
x <- d$ledger; x$pct[1] <- 101
stopifnot(reject(hours_metrics(x)))
fraction <- find_hours(59.5, d$ledger, d$contingency)
stopifnot(fraction$need == 59.5, fraction$shortfall == .5,
          fraction$verdict == "Change order needed: 0.5 h")
tmp <- tempfile(fileext = ".csv")
raw <- d$ledger
names(raw) <- c("Deliverable", "PlannedHours", "ActualToDate", "PctComplete", "EAC")
write.csv(raw, tmp, row.names = FALSE)
stopifnot(hours_load(tmp)$contingency == 0)
unlink(tmp)
cat("Find-hours input guards and fractional-hour shortfall: passed\n")

# Forecast overruns consume reserve before a new ask. Preserve any baseline
# deficit in the total gap, while allocations to the request stay nonnegative.
over <- d$ledger; over$eac[1] <- 147
gap <- find_hours(45, over, 40)
stopifnot(gap$metrics$eac == 900, gap$metrics$findable == -10,
          gap$metrics$reserve_used == 40, gap$metrics$remaining_contingency == 0,
          gap$from_slack == 0, gap$from_cont == 0, gap$request_shortfall == 45,
          gap$baseline_deficit == 10, gap$shortfall == 55, !gap$absorbable,
          gap$contingency_left == 0,
          grepl("Absorbed internally: 0 h", change_order_text(gap), fixed = TRUE))
over$eac[1] <- 117 # EAC870: only20 of40reserve remains available.
gap <- find_hours(45, over, 40)
stopifnot(gap$metrics$findable == 20, gap$from_cont == 20,
          gap$request_shortfall == 25, gap$baseline_deficit == 0, gap$shortfall == 25)
over$eac[1] <- 147
stopifnot(find_hours(0, over, 40)$shortfall == 10)
cat("Find-hours existing overruns consume reserve: passed\n")

roundtrip <- d$ledger; roundtrip$eac[1] <- 78.5
exported <- hours_export(roundtrip, 23.75)
write.csv(exported, tmp, row.names = FALSE)
reloaded <- hours_load(tmp)
stopifnot(identical(reloaded$ledger, roundtrip), reloaded$contingency == 23.75,
          hours_metrics(reloaded$ledger, reloaded$contingency)$findable == 42.25)
unlink(tmp)
cat("Find-hours CSV preserves edited ledger and reserve: passed\n")

# A wrong explicit client input path must never fall back to the example.
stopifnot(inherits(try(hours_load(file.path(tempdir(), "missing-explicit-input-20261028")), silent = TRUE), "try-error"))
