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
                                          c(8, 1, 3, 135, 46, 8)),
          "next lock is CP-105" = k$next_dbl_id == "CP-105")

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
# the phases follow the database lock, and a locked database is clean
ctx <- lifecycle_context(d)
week_end <- as_of - 7 * (max(qt$week) - qt$week)
for (i in d$studies$id) {
  s <- d$studies[d$studies$id == i, ]; m <- ms[ms$study_id == i, ]
  lock <- m$date[m$milestone == "DBL"]; locked <- m$status[m$milestone == "DBL"] == "done"
  after <- qt$study_id == i & week_end >= lock
  stopifnot(
    "the context reads the lock from milestones.csv" = ctx[i, "locked"] == locked,
    "Startup and Conduct lock months ahead" = !s$phase %in% c("Startup", "Conduct") || (!locked && s$days_to_dbl > 21),
    "DB Lock studies lock days ahead, after the last participant's last visit" =
      s$phase != "DB Lock" || (!locked && s$days_to_dbl > 0 && s$days_to_dbl <= 20 && m$status[m$milestone == "LPLV"] == "done"),
    "Reporting studies are locked" = s$phase != "Reporting" || locked,
    "a locked study has no open queries" = !locked || s$open_queries == 0,
    "a locked study is fully cleaned and source-verified" = !locked || (s$clean_pct == 1 && s$sdv_pct == 1),
    "no trend week from the lock on has open queries" = !locked || all(qt$open_queries[after] == 0),
    "no final TLFs before the lock" = locked || s$tlf_finalized == 0,
    "no Reporting deliverables before the lock" =
      locked || d$deliverables$done[d$deliverables$study_id == i & d$deliverables$phase == "Reporting"] == 0
  )
}
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
backlog <- function(x) x$sev[x$who == "CP-103" & x$title == "Query backlog rising"]
stopifnot(
  "CP-103 at 120 open queries turns amber"   = a$st$rag[a$st$id == "CP-103"] == "amber",
  "... and On watch goes from 3 to 4"        = k$watch == 3 && a$k$watch == 4,
  "... and its backlog signal follows the what-if, from amber to red" =
    identical(backlog(sg), "amber") && identical(backlog(a$sg), "red"),
  "without a what-if the backlog signal reads the trend's own last week" =
    grepl("+25 open queries", sg$msg[sg$who == "CP-103" & sg$title == "Query backlog rising"], fixed = TRUE),
  "CP-108 at 80% double programming: At risk 0" = b$k$at_risk == 0,
  "... and its double-programming lag signal goes" =
    any(sg$who == "CP-108" & sg$title == "Double-programming lag") &&
    !any(b$sg$who == "CP-108" & b$sg$title == "Double-programming lag")
)

# the score breakdown's words
dr <- score_drivers(st[st$id == "CP-108", ])
stopifnot("drivers name all four dimensions" = identical(names(dr), SCORE_DIMS),
          "drivers carry the inputs" = grepl("5 of 72 TLFs finalized", dr[["TLF"]], fixed = TRUE) &&
            grepl("2 milestones overdue (+44); DB locked 70 days ago; next report: TLFs, 40 days overdue (+45)",
                  dr[["Timeline"]], fixed = TRUE),
          "before the lock the TLF words count dry runs" =
            grepl("28 of 90 TLFs QC'd as dry runs (31%)", score_drivers(st[st$id == "CP-105", ])[["TLF"]], fixed = TRUE))
# the Timeline words account for the Timeline score: their points add up to it (or it is capped)
points <- function(x) sum(as.numeric(regmatches(x, gregexpr("(?<=\\(\\+)[0-9]+(?=\\))", x, perl = TRUE))[[1]]))
for (i in st$id) {
  s <- st[st$id == i, ]; w <- score_drivers(s)[["Timeline"]]
  stopifnot("the Timeline words add up to the Timeline score" =
              if (grepl("capped at 100", w, fixed = TRUE)) s$Timeline == 100 else points(w) == s$Timeline)
}
# After the lock the timeline's deadline is the next report, so a study that locked on time and has
# delivered its reports carries no lock pressure; one whose next report is weeks away carries little.
done <- d; m107 <- done$milestones$study_id == "CP-107"
done$milestones$status[m107] <- "done"
done$studies$tlf_finalized[done$studies$id == "CP-107"] <- done$studies$tlf_planned[done$studies$id == "CP-107"]
s107 <- score_portfolio(done); s107 <- s107[s107$id == "CP-107", ]
soon <- d; m <- soon$milestones$study_id == "CP-107" & soon$milestones$milestone %in% c("TLFs", "CSR")
soon$milestones$date[m] <- c("2026-08-20", "2026-09-30"); soon$milestones$status[m] <- "todo"
t107 <- score_portfolio(soon); t107 <- t107[t107$id == "CP-107", ]
stopifnot("locked and every report delivered: Timeline 0" = s107$Timeline == 0 &&
            grepl("every report delivered (+0)", score_drivers(s107)[["Timeline"]], fixed = TRUE),
          "locked, next report in 60 days: Timeline 9" = t107$Timeline == 9 &&
            grepl("next report: TLFs, due in 60 days (+9)", score_drivers(t107)[["Timeline"]], fixed = TRUE))

# The rendered Quarto pages (the launch page links the guide and the read-only snapshot) show the
# same numbers as the app: their KPI boxes and the snapshot's ranked table must match the scoring
# on the committed CSVs. After a change to the data or the scoring, re-render them:
#   cd lifecycle_dashboard/quarto && quarto render lifecycle-dashboard.qmd && quarto render lifecycle-guide.qmd
qdir <- Find(function(x) file.exists(file.path(x, "lifecycle-dashboard.html")),
             c("../quarto", "lifecycle_dashboard/quarto", "quarto"))
stopifnot("found the rendered Quarto pages" = !is.null(qdir))
page_of <- function(f) paste(readLines(file.path(qdir, f), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
kpi_boxes <- function(html) {
  # the value (28px) and its label (11px, or 12px since the site redesign) of each box
  m <- regmatches(html, gregexpr(paste0('font-size:28px[^>]*>\\s*([^<]*?)\\s*</div>\\s*',
                                        '<div style="font-size:1[12]px[^>]*>\\s*([^<]*?)\\s*</div>'), html, perl = TRUE))[[1]]
  vals <- sub('(?s).*font-size:28px[^>]*>\\s*([^<]*?)\\s*</div>.*', "\\1", m, perl = TRUE)
  stats::setNames(vals, sub('(?s).*font-size:1[12]px[^>]*>\\s*([^<]*?)\\s*</div>$', "\\1", m, perl = TRUE))
}
want <- c("Active studies" = as.character(k$n), "At risk" = as.character(k$at_risk), "On watch" = as.character(k$watch),
          "Open queries" = as.character(k$open_q), "Avg deliverables" = paste0(k$avg_del, "%"),
          "Next DB lock" = if (is.na(k$next_dbl_days)) "-" else paste0(k$next_dbl_days, "d"))
for (f in c("lifecycle-dashboard.html", "lifecycle-guide.html")) {
  got <- kpi_boxes(page_of(f))
  if (!identical(got[names(want)], want)) {
    cat(f, "shows:", paste(names(got), got, sep = " = ", collapse = "; "), "\n")
    stop(f, ": the KPI boxes do not match the committed CSVs; re-render lifecycle_dashboard/quarto", call. = FALSE)
  }
}
snap <- page_of("lifecycle-dashboard.html")
tbl <- regmatches(snap, regexpr("(?s)<table.*?</table>", snap, perl = TRUE))
rows <- regmatches(tbl, gregexpr("(?s)<tr[^>]*>.*?</tr>", tbl, perl = TRUE))[[1]][-1]
cells <- lapply(rows, function(r) trimws(gsub("<[^>]+>", "", regmatches(r, gregexpr("(?s)<td[^>]*>.*?</td>", r, perl = TRUE))[[1]])))
shown <- data.frame(id = vapply(cells, `[`, "", 1), overall = as.numeric(vapply(cells, `[`, "", 3)), rag = vapply(cells, `[`, "", 8))
stopifnot("the snapshot ranks the studies as the app does" =
            identical(shown$id, st$id) && identical(shown$overall, as.numeric(st$overall)) && identical(shown$rag, st$rag))

cat("Lifecycle logic: all tests passed\n")

# A wrong explicit client input path must never fall back to the example.
stopifnot(inherits(try(lifecycle_load(file.path(tempdir(), "missing-explicit-input-20261028")), silent = TRUE), "try-error"))

# Invalid replacement inputs must not be clamped into a reassuring low score.
for (case in c("zero-plan", "negative-queries", "infinite", "invalid-proportion", "unknown-phase")) {
  x <- d$studies[1, ]
  if (case == "zero-plan") x$tlf_planned <- 0
  if (case == "negative-queries") x$open_queries <- -1
  if (case == "infinite") x$discrep <- Inf
  if (case == "invalid-proportion") x$clean_pct <- 70
  if (case == "unknown-phase") x$phase <- "Unknown"
  stopifnot(inherits(try(score_study(x, 0), silent = TRUE), "try-error"))
}
x <- d; x$deliverables$total[x$deliverables$study_id == d$studies$id[1]] <- 0
stopifnot(inherits(try(deliverables_pct(x, d$studies$id[1]), silent = TRUE), "try-error"))
cat("Lifecycle invalid-input guards: passed\n")
