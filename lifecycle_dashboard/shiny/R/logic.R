# ---------------------------------------------------------------------------
# logic.R - pure operational-risk scoring for the Study Lifecycle Monitor.
# No PHI, no participant-level data. Plain functions shared by the Shiny app,
# the Quarto docs, and the unit tests. The scoring is deliberately transparent:
# a weighted blend of four operational dimensions, all visible.
# ---------------------------------------------------------------------------

lifecycle_load <- function(dir = NULL) {
  cand <- c(dir, "data", "../data", "shiny/data", "lifecycle_dashboard/shiny/data")
  cand <- Filter(Negate(is.null), cand)
  base <- Find(function(d) file.exists(file.path(d, "studies.csv")), cand)
  if (is.null(base)) stop("Cannot find studies.csv (run R/gen_data.R first)")
  rd <- function(f) utils::read.csv(file.path(base, f), stringsAsFactors = FALSE)
  list(studies = rd("studies.csv"), milestones = rd("milestones.csv"),
       deliverables = rd("deliverables.csv"), query_trend = rd("query_trend.csv"))
}

clamp <- function(x) pmax(0, pmin(100, x))

dbl_pressure <- function(phase, days_to_dbl) {
  if (phase == "Startup") return(0.15)
  d <- days_to_dbl
  if (d <= 0) 1 else if (d < 14) .85 else if (d < 30) .6 else if (d < 60) .35 else .2
}
rep_pressure <- function(phase)
  switch(phase, "Reporting" = 1, "DB Lock" = .6, "Conduct" = .25, "Startup" = .1, .1)

# Score one study. `overdue` = number of milestones past due (status == "risk").
score_study <- function(s, overdue) {
  dblp <- dbl_pressure(s$phase, s$days_to_dbl); repp <- rep_pressure(s$phase)
  timeline <- clamp(overdue * 22 + dblp * 45)
  data <- clamp((min(1, s$open_queries / 120) * 45 + (1 - s$clean_pct) * 30 +
                 (1 - s$sdv_pct) * 25) * (0.5 + 0.6 * dblp))
  tlf <- clamp((1 - s$tlf_finalized / s$tlf_planned) * 100 * (0.3 + 0.8 * repp))
  resource <- clamp((1 - s$dbl_prog_pct / 100) * 55 + min(1, s$discrep / 18) * 45 * repp)
  overall <- clamp(0.30 * timeline + 0.28 * data + 0.27 * tlf + 0.15 * resource)
  list(Timeline = timeline, Data = data, TLF = tlf, Resource = resource, overall = overall)
}

# Attach score columns (Timeline/Data/TLF/Resource/overall) to the studies frame.
score_portfolio <- function(d) {
  st <- d$studies
  overdue <- vapply(st$id, function(i)
    sum(d$milestones$study_id == i & d$milestones$status == "risk"), integer(1))
  sc <- lapply(seq_len(nrow(st)), function(j) score_study(st[j, ], overdue[[j]]))
  st$overdue  <- overdue
  st$Timeline <- round(vapply(sc, `[[`, numeric(1), "Timeline"))
  st$Data     <- round(vapply(sc, `[[`, numeric(1), "Data"))
  st$TLF      <- round(vapply(sc, `[[`, numeric(1), "TLF"))
  st$Resource <- round(vapply(sc, `[[`, numeric(1), "Resource"))
  st$overall  <- round(vapply(sc, `[[`, numeric(1), "overall"))
  st$rag <- ifelse(st$overall > 66, "red", ifelse(st$overall > 33, "amber", "green"))
  st[order(-st$overall), ]
}

deliverables_pct <- function(d, study_id) {
  x <- d$deliverables[d$deliverables$study_id == study_id, ]
  if (!nrow(x)) return(0)
  round(100 * sum(x$done) / sum(x$total))
}

lifecycle_kpis <- function(st, d) {
  at_risk <- sum(st$overall > 66); watch <- sum(st$overall > 33 & st$overall <= 66)
  tot_q <- sum(st$open_queries)
  avg_del <- round(mean(vapply(st$id, function(i) deliverables_pct(d, i), numeric(1))))
  future <- st[st$days_to_dbl > 0, ]
  next_dbl <- if (nrow(future)) future[order(future$days_to_dbl), ][1, ] else NULL
  list(n = nrow(st), at_risk = at_risk, watch = watch, open_q = tot_q, avg_del = avg_del,
       next_dbl_days = if (is.null(next_dbl)) NA_integer_ else next_dbl$days_to_dbl,
       next_dbl_id = if (is.null(next_dbl)) NA_character_ else next_dbl$id)
}

# Operational early-warning signals, ranked (red before amber).
lifecycle_signals <- function(st, d) {
  sigs <- list()
  add <- function(sev, who, t, m) sigs[[length(sigs) + 1]] <<-
    data.frame(sev = sev, who = who, title = t, msg = m, stringsAsFactors = FALSE)
  for (j in seq_len(nrow(st))) {
    s <- st[j, ]
    qt <- d$query_trend[d$query_trend$study_id == s$id, ]; qt <- qt[order(qt$week), ]
    if (s$days_to_dbl > 0 && s$days_to_dbl < 21 && s$open_queries > 15)
      add(if (s$days_to_dbl < 10) "red" else "amber", s$id, "DB lock at risk",
          sprintf("%d open queries with DBL in %d days", s$open_queries, s$days_to_dbl))
    if (nrow(qt) >= 8) { qd <- qt$open_queries[8] - qt$open_queries[5]
      if (qd > 10) add(if (qd > 25) "red" else "amber", s$id, "Query backlog rising",
                       sprintf("+%d open queries over the last 3 weeks", qd)) }
    if (rep_pressure(s$phase) >= .6 && s$tlf_finalized / s$tlf_planned < .6)
      add(if (s$tlf_finalized / s$tlf_planned < .35) "red" else "amber", s$id, "TLF production behind",
          sprintf("%d%% finalized while in %s", round(100 * s$tlf_finalized / s$tlf_planned), s$phase))
    if (rep_pressure(s$phase) >= .6 && s$dbl_prog_pct < 60)
      add("amber", s$id, "Double-programming lag",
          sprintf("%d%% double-programmed, %d open discrepancies", s$dbl_prog_pct, s$discrep))
    od <- d$milestones[d$milestones$study_id == s$id & d$milestones$status == "risk", ]
    if (nrow(od)) add("red", s$id, "Milestone overdue", paste0(paste(od$milestone, collapse = ", "), " past due"))
  }
  if (!length(sigs)) return(data.frame())
  out <- do.call(rbind, sigs)
  out[order(out$sev != "red"), ]
}
