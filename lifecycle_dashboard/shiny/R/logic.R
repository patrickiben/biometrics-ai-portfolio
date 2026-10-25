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

# The overall score is this weighted blend of the four dimensions (each 0..100, higher = riskier).
SCORE_WEIGHTS <- c(Timeline = 0.30, Data = 0.28, TLF = 0.27, Resource = 0.15)
SCORE_DIMS <- names(SCORE_WEIGHTS)

# RAG status of a 0..100 score: above 66 red (at risk), 34 to 66 amber (watch), 33 or less green.
rag_of <- function(score) ifelse(score > 66, "red", ifelse(score > 33, "amber", "green"))

# How close a deadline is, 0..1: 1 once it has passed, .85 inside two weeks, down to .2 beyond
# two months; 0 when there is no deadline left (NA).
deadline_pressure <- function(days) {
  if (is.na(days)) return(0)
  if (days <= 0) 1 else if (days < 14) .85 else if (days < 30) .6 else if (days < 60) .35 else .2
}
# Pressure from the database lock: low in Startup, then rising as the lock nears; 1 at and after it.
dbl_pressure <- function(phase, days_to_dbl) {
  if (phase == "Startup") return(0.15)
  deadline_pressure(days_to_dbl)
}
rep_pressure <- function(phase)
  switch(phase, "Reporting" = 1, "DB Lock" = .6, "Conduct" = .25, "Startup" = .1, .1)

# The timeline's deadline: the database lock until it is done, then the next report that is not
# done (TLFs, then CSR). A study that locked on time carries no lock pressure; one whose reports
# are overdue carries the full pressure. No report left: no pressure.
timeline_pressure <- function(s, locked, days_to_report = NA)
  if (locked) deadline_pressure(days_to_report) else dbl_pressure(s$phase, s$days_to_dbl)

# TLF progress, 0..1: after the lock, the TLFs finalized. Final TLFs cannot exist before the lock,
# so before it, progress is the TLFs programmed and QC'd as dry runs.
tlf_progress <- function(s, locked)
  (if (locked) s$tlf_finalized else s$tlf_qcd) / s$tlf_planned

# Score one study. `overdue` = number of milestones past due (status == "risk"); `locked` = its
# database lock is done; `days_to_report` = days to its next report due (TLFs or CSR), NA if none.
score_study <- function(s, overdue, locked = s$days_to_dbl <= 0, days_to_report = NA) {
  dblp <- dbl_pressure(s$phase, s$days_to_dbl); repp <- rep_pressure(s$phase)
  timeline <- clamp(overdue * 22 + timeline_pressure(s, locked, days_to_report) * 45)
  data <- clamp((min(1, s$open_queries / 120) * 45 + (1 - s$clean_pct) * 30 +
                 (1 - s$sdv_pct) * 25) * (0.5 + 0.6 * dblp))
  tlf <- clamp((1 - tlf_progress(s, locked)) * 100 * (0.3 + 0.8 * repp))
  resource <- clamp((1 - s$dbl_prog_pct / 100) * 55 + min(1, s$discrep / 18) * 45 * repp)
  w <- SCORE_WEIGHTS
  overall <- clamp(w[["Timeline"]] * timeline + w[["Data"]] * data + w[["TLF"]] * tlf + w[["Resource"]] * resource)
  list(Timeline = timeline, Data = data, TLF = tlf, Resource = resource, overall = overall)
}

# Each study's place in its schedule, from milestones.csv: milestones overdue, whether the
# database lock is done (from days_to_dbl when there is no DBL row), and the next report due
# (TLFs, then CSR) with the days from the snapshot to it.
lifecycle_context <- function(d) {
  ms <- d$milestones; as_of <- lifecycle_as_of(d)
  one <- function(i, days_to_dbl) {
    m <- ms[ms$study_id == i, ]
    dbl <- m$status[m$milestone == "DBL"]
    nr <- m[m$milestone %in% c("TLFs", "CSR") & m$status != "done", ]
    nr <- nr[order(match(nr$milestone, c("TLFs", "CSR"))), ]
    data.frame(overdue = sum(m$status == "risk"),
               locked = if (length(dbl)) dbl[1] == "done" else days_to_dbl <= 0,
               next_report = if (nrow(nr)) nr$milestone[1] else NA_character_,
               days_to_report = if (nrow(nr) && !is.na(as_of)) as.integer(as.Date(nr$date[1]) - as_of) else NA_integer_)
  }
  if (!nrow(d$studies)) return(data.frame(overdue = integer(), locked = logical(),
                                          next_report = character(), days_to_report = integer()))
  do.call(rbind, Map(one, d$studies$id, d$studies$days_to_dbl))
}

# Attach score columns (Timeline/Data/TLF/Resource/overall) to the studies frame.
score_portfolio <- function(d) {
  st <- d$studies
  ctx <- lifecycle_context(d)
  overdue <- ctx$overdue
  st$locked <- ctx$locked; st$next_report <- ctx$next_report; st$days_to_report <- ctx$days_to_report
  sc <- lapply(seq_len(nrow(st)), function(j) score_study(st[j, ], overdue[[j]], st$locked[j], st$days_to_report[j]))
  st$overdue  <- overdue
  st$Timeline <- round(vapply(sc, `[[`, numeric(1), "Timeline"))
  st$Data     <- round(vapply(sc, `[[`, numeric(1), "Data"))
  st$TLF      <- round(vapply(sc, `[[`, numeric(1), "TLF"))
  st$Resource <- round(vapply(sc, `[[`, numeric(1), "Resource"))
  st$overall  <- round(vapply(sc, `[[`, numeric(1), "overall"))
  st$rag <- rag_of(st$overall)
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
    locked <- if (is.null(s$locked)) s$days_to_dbl <= 0 else s$locked
    qt <- d$query_trend[d$query_trend$study_id == s$id, ]; qt <- qt[order(qt$week), ]
    if (s$days_to_dbl > 0 && s$days_to_dbl < 21 && s$open_queries > 15)
      add(if (s$days_to_dbl < 10) "red" else "amber", s$id, "DB lock at risk",
          sprintf("%d open queries with DBL in %d days", s$open_queries, s$days_to_dbl))
    # the snapshot week is the study's open queries now, so a what-if moves this signal too
    if (nrow(qt) >= 4) { qd <- s$open_queries - qt$open_queries[nrow(qt) - 3]
      if (qd > 10) add(if (qd > 25) "red" else "amber", s$id, "Query backlog rising",
                       sprintf("+%d open queries over the last 3 weeks", qd)) }
    prog <- tlf_progress(s, locked)
    if (rep_pressure(s$phase) >= .6 && prog < .6)
      add(if (prog < .35) "red" else "amber", s$id, "TLF production behind",
          if (locked) sprintf("%d%% finalized while in %s", round(100 * prog), s$phase)
          else sprintf("%d%% QC'd as dry runs, %s", round(100 * prog), lock_words(s$days_to_dbl)))
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

# The snapshot date of the data: each study's DB lock milestone date minus its days_to_dbl (the
# most common value, so one inconsistent row cannot move it). NA when the data cannot say.
lifecycle_as_of <- function(d) {
  m <- d$milestones[d$milestones$milestone == "DBL", c("study_id", "date")]
  x <- merge(m, d$studies[, c("id", "days_to_dbl")], by.x = "study_id", by.y = "id")
  dates <- as.Date(x$date) - x$days_to_dbl
  dates <- dates[!is.na(dates)]
  if (!length(dates)) return(as.Date(NA))
  tab <- table(format(dates))
  as.Date(names(tab)[which.max(tab)])
}

# A lock that is not done yet, in words.
lock_words <- function(days) if (days > 0) sprintf("DB lock in %d days", days) else
  if (days == 0) "DB lock due today" else sprintf("DB lock overdue by %d days", -days)

# What drives each dimension of one study's score, in words (for the score breakdown). The
# Timeline line gives the points behind its score: 22 per overdue milestone plus up to 45 from
# its deadline (the lock, or after the lock the next report), so the line adds up to the score.
score_drivers <- function(s, overdue = s$overdue) {
  pct <- function(x) sprintf("%d%%", round(100 * x))
  pts <- function(x) sprintf("(+%d)", round(x))
  locked <- if (is.null(s$locked)) s$days_to_dbl <= 0 else isTRUE(s$locked)
  dtr <- if (is.null(s$days_to_report)) NA else s$days_to_report
  tp <- 45 * timeline_pressure(s, locked, dtr)
  od <- sprintf("%s overdue %s", if (overdue == 1) "1 milestone" else sprintf("%d milestones", overdue), pts(22 * overdue))
  when <- if (locked) {
    ago <- if (s$days_to_dbl < 0) sprintf("DB locked %d days ago", -s$days_to_dbl) else "DB locked"
    if (is.na(dtr)) paste(ago, "and every report delivered", pts(tp))
    else sprintf("%s; next report: %s, %s %s", ago, s$next_report,
                 if (dtr > 0) sprintf("due in %d days", dtr) else if (dtr == 0) "due today" else sprintf("%d days overdue", -dtr),
                 pts(tp))
  } else paste(if (s$phase == "Startup") paste0("Startup, ", lock_words(s$days_to_dbl)) else lock_words(s$days_to_dbl), pts(tp))
  capped <- if (22 * overdue + tp > 100) "; capped at 100" else ""
  c(Timeline = paste0(od, "; ", when, capped),
    Data     = sprintf("%s%d open queries; %s clean; %s source-verified", if (locked) "DB locked: " else "",
                       s$open_queries, pct(s$clean_pct), pct(s$sdv_pct)),
    TLF      = if (locked) sprintf("%d of %d TLFs finalized (%s), in %s", s$tlf_finalized, s$tlf_planned,
                                   pct(s$tlf_finalized / s$tlf_planned), s$phase)
               else sprintf("%d of %d TLFs QC'd as dry runs (%s), in %s; final TLFs follow the lock",
                            s$tlf_qcd, s$tlf_planned, pct(s$tlf_qcd / s$tlf_planned), s$phase),
    Resource = sprintf("%d%% double-programmed; %d open discrepancies", s$dbl_prog_pct, s$discrep))
}
