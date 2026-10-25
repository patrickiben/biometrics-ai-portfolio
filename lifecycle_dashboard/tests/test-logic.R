#!/usr/bin/env Rscript
# Unit tests for the Study Lifecycle Monitor scoring and its synthetic data. Base R only.
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
  "signals ranked red-first" = nrow(sg) == 0 || sg$sev[1] == "red",
  "weights sum to 1"        = isTRUE(all.equal(sum(SCORE_WEIGHTS), 1)),
  "RAG thresholds"          = identical(rag_of(c(0, 33, 34, 66, 67, 100)), c("green", "green", "amber", "amber", "red", "red"))
)

# the headline values the launch page's smoke test pins (apps/lifecycle_dashboard/launch.json)
stopifnot("KPIs as published" = identical(c(k$n, k$at_risk, k$watch, k$open_q, k$avg_del, k$next_dbl_days),
                                          c(8, 1, 3, 148, 48, 33)),
          "next lock is CP-103" = k$next_dbl_id == "CP-103")

# scoring monotonic: more open queries never lowers the Data score
s <- d$studies[d$studies$id == "CP-103", ]
lo <- score_study(within(s, open_queries <- 5), 0)$Data
hi <- score_study(within(s, open_queries <- 120), 0)$Data
stopifnot("more open queries -> higher data risk" = hi >= lo)

# the data are internally consistent, so no panel contradicts another
as_of <- lifecycle_as_of(d)
ms <- d$milestones; ms$date <- as.Date(ms$date)
qt <- d$query_trend
last <- qt[qt$week == max(qt$week), ]
stopifnot(
  "snapshot date is 2026-06-21" = identical(as_of, as.Date("2026-06-21")),
  "days_to_dbl = DB lock date minus the snapshot" = all(vapply(d$studies$id, function(i)
    d$studies$days_to_dbl[d$studies$id == i] == as.integer(ms$date[ms$study_id == i & ms$milestone == "DBL"] - as_of), TRUE)),
  "each trend ends on the study's open queries" =
    identical(last$open_queries[match(d$studies$id, last$study_id)], as.integer(d$studies$open_queries)),
  "the portfolio trend ends on the KPI" = sum(last$open_queries) == k$open_q,
  "past-due milestones are done or overdue" = all(ms$status[ms$date < as_of] %in% c("done", "risk")),
  "future milestones are not overdue" = !any(ms$status[ms$date >= as_of] == "risk"),
  "deliverables never exceed their totals" = all(d$deliverables$done <= d$deliverables$total & d$deliverables$done >= 0)
)
for (i in d$studies$id) {
  s <- d$studies[d$studies$id == i, ]; m <- ms[ms$study_id == i, ]
  tlf_done <- m$status[m$milestone == "TLFs"] == "done"; csr_done <- m$status[m$milestone == "CSR"] == "done"
  rep <- d$deliverables[d$deliverables$study_id == i & d$deliverables$phase == "Reporting", ]
  stopifnot(
    "TLFs done only when every TLF is finalized" = !tlf_done || s$tlf_finalized >= s$tlf_planned,
    "the CSR is done only after the TLFs" = !csr_done || tlf_done,
    "Reporting deliverables follow TLF finalization" = csr_done ||
      rep$done / rep$total <= s$tlf_finalized / s$tlf_planned + 0.06
  )
}
stopifnot("CP-108's register is far from complete" = deliverables_pct(d, "CP-108") < 70,
          "CP-107 has its TLFs and CSR overdue" = st$overdue[st$id == "CP-107"] == 2)

# the generator is deterministic and wrote exactly these files
gp <- Find(file.exists, c("../shiny/R/gen_data.R", "lifecycle_dashboard/shiny/R/gen_data.R", "shiny/R/gen_data.R"))
tmp <- tempfile("lifecycle-data-"); local({ source(gp, local = TRUE); gen_portfolio(tmp) })
for (f in c("studies.csv", "milestones.csv", "deliverables.csv", "query_trend.csv"))
  stopifnot("gen_data.R reproduces the committed CSVs" = identical(readLines(file.path(tmp, f)), readLines(file.path(dir, f))))
unlink(tmp, recursive = TRUE)

# what the guidance in the app and on the launch page says will happen
whatif <- function(id, field, value) {
  x <- d; x$studies[[field]][x$studies$id == id] <- value
  s <- score_portfolio(x); list(st = s, k = lifecycle_kpis(s, x), sg = lifecycle_signals(s, x))
}
a <- whatif("CP-103", "open_queries", 120)
b <- whatif("CP-108", "dbl_prog_pct", 80)
stopifnot(
  "CP-103 at 120 open queries turns amber"   = a$st$rag[a$st$id == "CP-103"] == "amber",
  "... and On watch goes from 3 to 4"        = k$watch == 3 && a$k$watch == 4,
  "CP-108 at 80% double programming: At risk 0" = b$k$at_risk == 0,
  "... and its double-programming lag signal goes" =
    any(sg$who == "CP-108" & sg$title == "Double-programming lag") &&
    !any(b$sg$who == "CP-108" & b$sg$title == "Double-programming lag")
)

# the score breakdown's words
dr <- score_drivers(st[st$id == "CP-108", ], st$overdue[st$id == "CP-108"])
stopifnot("drivers name all four dimensions" = identical(names(dr), SCORE_DIMS),
          "drivers carry the inputs" = grepl("7 of 72 TLFs finalized", dr[["TLF"]], fixed = TRUE) &&
            grepl("2 milestones overdue; DB locked 70 days ago", dr[["Timeline"]], fixed = TRUE))

cat("Lifecycle logic: all tests passed\n")
