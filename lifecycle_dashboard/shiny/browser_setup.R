BW_TEMPLATES <- stats::setNames(lapply(seed, function(x) list(data = x, required = TRUE)), c("studies.csv", "milestones.csv", "deliverables.csv", "query_trend.csv"))
bw_lifecycle_validate <- function(frames, settings = NULL) {
  d <- stats::setNames(frames, names(seed)); s <- d$studies
  bw_key(s, "id", "Studies")
  if (!is.null(settings$selected_study)) bw_need(is.character(settings$selected_study) && length(settings$selected_study) == 1L && settings$selected_study %in% s$id, "Saved study selection must name an included study.")
  for (field in c("name", "phase", "design", "owner")) bw_need(bw_nonblank(s[[field]]), paste("Study field must be nonblank:", field))
  for (field in c("target", "enrolled", "sites")) bw_need(is.numeric(s[[field]]) && all(is.finite(s[[field]]) & s[[field]] >= 0 & s[[field]] == floor(s[[field]])), paste("Study counts must be finite nonnegative integers:", field))
  bw_need(all(s$target > 0), "Enrollment targets must be positive.")
  for (name in c("milestones", "deliverables", "query_trend")) {
    frame <- d[[name]]
    bw_need(all(frame$study_id %in% s$id), paste(name, "references a study absent from studies.csv."))
    bw_need(all(s$id %in% frame$study_id), paste(name, "must cover every included study; missing feeds are not zero."))
  }
  bw_key(d$milestones, c("study_id", "milestone"), "Milestones")
  bw_need(all(d$milestones$milestone %in% c("Protocol", "SAP", "FPFV", "LPLV", "DBL", "TLFs", "CSR")), "Unsupported milestone name; use the documented milestone vocabulary.")
  dates <- suppressWarnings(as.Date(d$milestones$date, format = "%Y-%m-%d"))
  bw_need(!anyNA(dates) && all(format(dates, "%Y-%m-%d") == d$milestones$date), "Milestone dates require valid YYYY-MM-DD values.")
  bw_need(all(d$milestones$status %in% c("done", "wip", "risk", "todo")), "Milestone status requires done, wip, risk or todo.")
  bw_key(d$deliverables, c("study_id", "phase"), "Deliverables")
  bw_need(all(is.finite(d$deliverables$done) & is.finite(d$deliverables$total) & d$deliverables$done >= 0 & d$deliverables$total > 0 & d$deliverables$done <= d$deliverables$total), "Deliverables require valid done/total counts.")
  bw_key(d$query_trend, c("study_id", "week"), "Query trend")
  for (field in c("week", "open_queries")) bw_need(all(is.finite(d$query_trend[[field]]) & d$query_trend[[field]] >= 0 & d$query_trend[[field]] == floor(d$query_trend[[field]])), "Query weeks and counts must be nonnegative integers.")
  bw_need(all(d$query_trend$week >= 1), "Query week must be at least one.")
  snap <- merge(d$milestones[d$milestones$milestone == "DBL", ], s[c("id", "days_to_dbl")], by.x = "study_id", by.y = "id")
  bw_need(nrow(snap) == nrow(s), "Each study requires one DBL milestone to establish its snapshot date.")
  bw_need(length(unique(as.Date(snap$date) - snap$days_to_dbl)) == 1L, "DBL dates and days-to-DBL disagree on the portfolio snapshot date.")
  scored <- score_portfolio(d); lifecycle_kpis(scored, d); lifecycle_signals(scored, d); d
}
