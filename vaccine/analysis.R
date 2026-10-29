# Client-neutral vaccine descriptive analyses. Source to load; no analysis runs on source.
# Methods: log-scale Student-t summaries; paired log differences; exact binomial CIs.
# References: https://www.fda.gov/media/78417/download (GMT/GMC log-t intervals)
# https://www.stat.ethz.ch/R-manual/R-devel/library/stats/html/binom.test.html
# https://www.cdisc.org/standards/therapeutic-areas/vaccines/vaccines-therapeutic-area-user-guide-v11/html
# These summaries do not estimate vaccine efficacy, protection or immunobridging success.

vaccine_stop <- function(...) stop(..., call. = FALSE)
vaccine_text <- function(x, label, allow_empty = FALSE) {
  x <- trimws(as.character(x))
  if (anyNA(x) || (!allow_empty && any(!nzchar(x)))) vaccine_stop(label, " must be nonmissing text.")
  x
}
vaccine_number <- function(x, label, missing = FALSE, integer = FALSE) {
  original <- x; x <- suppressWarnings(as.numeric(x))
  blank <- is.na(original) | trimws(as.character(original)) == ""
  if (any(!blank & (is.na(x) | !is.finite(x))) || (!missing && any(blank))) vaccine_stop(label, " must contain finite numeric values", if (missing) " or blanks." else ".")
  x[blank] <- NA_real_
  if (integer && any(!is.na(x) & x != floor(x))) vaccine_stop(label, " must contain whole numbers.")
  x
}
vaccine_unique <- function(d, keys, label) {
  if (nrow(d) && anyDuplicated(d[keys])) vaccine_stop(label, " has duplicate keys: ", paste(keys, collapse = ", "), ". Resolve repeated measurements before analysis.")
}
vaccine_columns <- function(d, fields, label) {
  if (!is.data.frame(d)) vaccine_stop(label, " must be a data frame.")
  missing <- setdiff(fields, names(d))
  if (length(missing)) vaccine_stop(label, " is missing columns: ", paste(missing, collapse = ", "))
  d[fields]
}
vaccine_scalar <- function(cfg, key, default = NULL) {
  value <- cfg[[key]]; if (is.null(value)) value <- default
  if (length(value) != 1L || is.na(value)) vaccine_stop("Configure one ", key, ".")
  value
}
vaccine_choices <- function(cfg, key) {
  x <- vaccine_text(unlist(cfg[[key]], use.names = FALSE), key)
  if (!length(x) || length(x) > 50 || anyDuplicated(x) || any(nchar(x) > 200) || any(grepl("[[:cntrl:]]", x))) vaccine_stop(key, " must contain 1–50 distinct single-line labels of at most 200 characters.")
  x
}
vaccine_log_summary <- function(log_values, confidence = .95) {
  if (length(confidence) != 1L || !is.finite(confidence) || confidence <= 0 || confidence >= 1) vaccine_stop("confidence must be between zero and one.")
  if (any(!is.finite(log_values))) vaccine_stop("Log-summary values must be finite; select evaluable observations first.")
  n <- length(log_values); point <- lower <- upper <- NA_real_
  status <- "Not estimable: no evaluable observations"
  if (n) {
    mu <- mean(log_values); point <- exp(mu)
    status <- "Point estimate only: one evaluable observation"
    if (n > 1L) {
      se <- stats::sd(log_values) / sqrt(n)
      half <- stats::qt((1 + confidence)/2, n - 1L) * se
      lower <- exp(mu - half); upper <- exp(mu + half)
      status <- if (se == 0) "Estimated; zero observed log variance" else "Estimated"
      if (any(!is.finite(c(point, lower, upper))) || lower == 0) {
        lower <- upper <- NA_real_; status <- "Interval not estimable within numeric range"
      }
    }
    if (!is.finite(point) || point == 0) { point <- NA_real_; status <- "Point estimate not estimable within numeric range" }
  }
  data.frame(n = n, estimate = point, lower = lower, upper = upper, confidence = confidence, status = status, stringsAsFactors = FALSE)
}
vaccine_exact_ci <- function(x, n, confidence = .95) {
  if (length(x) != 1L || length(n) != 1L || !is.finite(x) || !is.finite(n) || x != floor(x) || n != floor(n) || x < 0 || n < x) vaccine_stop("Exact-binomial counts must be whole numbers with 0 <= x <= n.")
  if (length(confidence) != 1L || !is.finite(confidence) || confidence <= 0 || confidence >= 1) vaccine_stop("confidence must be between zero and one.")
  ci <- if (n) unname(stats::binom.test(x, n, conf.level = confidence)$conf.int) else c(NA_real_, NA_real_)
  data.frame(n = n, events = x, percent = if (n) 100 * x/n else NA_real_, lower_percent = 100 * ci[1], upper_percent = 100 * ci[2], confidence = confidence, status = if (n) "Estimated: exact Clopper-Pearson" else "Not estimable: zero denominator", stringsAsFactors = FALSE)
}
vaccine_bind <- function(rows) { result <- do.call(rbind, rows); rownames(result) <- NULL; result }
vaccine_prepare <- function(data, cfg) {
  ids <- vaccine_choices(cfg, "outputs")
  allowed <- c("immunogenicity", "fold_rise", "response", "titer_plot", "reactogenicity", "diary_profile")
  if (any(!ids %in% allowed)) vaccine_stop("Unknown vaccine output.")
  confidence <- vaccine_number(vaccine_scalar(cfg, "confidence", .95), "confidence")
  if (confidence <= 0 || confidence >= 1) vaccine_stop("confidence must be between zero and one.")
  p <- vaccine_columns(data$participants, c("USUBJID", "ARM", "IMMFL", "SAFEFL"), "participants")
  for (name in names(p)) p[[name]] <- vaccine_text(p[[name]], paste("participants", name))
  vaccine_unique(p, "USUBJID", "participants")
  if (!nrow(p)) vaccine_stop("Participants roster is empty.")
  if (any(!p$IMMFL %in% c("Y", "N")) || any(!p$SAFEFL %in% c("Y", "N"))) vaccine_stop("Population flags must be canonical Y or N.")
  if (length(unique(p$ARM)) > 50) vaccine_stop("This revision supports up to 50 distinct arm labels. Check the ARM mapping.")
  p <- p[order(p$ARM, p$USUBJID), , drop = FALSE]
  prepared <- list(participants = p, arms = sort(unique(p$ARM)), confidence = confidence, outputs = ids)
  audits <- list(data.frame(source = "participants", category = c("All participants", "Immunogenicity population", "Safety population"), n_records = c(nrow(p), sum(p$IMMFL == "Y"), sum(p$SAFEFL == "Y"))))
  if (any(ids %in% c("immunogenicity", "fold_rise", "response", "titer_plot"))) {
    assay <- vaccine_text(vaccine_scalar(cfg, "assay"), "assay")
    antigen <- vaccine_text(vaccine_scalar(cfg, "antigen"), "antigen")
    unit <- vaccine_text(vaccine_scalar(cfg, "unit"), "unit")
    baseline <- vaccine_text(vaccine_scalar(cfg, "baseline_visit"), "baseline_visit")
    followup <- vaccine_choices(cfg, "followup_visits")
    if (baseline %in% followup) vaccine_stop("Baseline must be distinct from follow-up visits.")
    visits <- c(baseline, followup)
    bp <- vaccine_scalar(cfg, "blq_policy", "exclude"); ap <- vaccine_scalar(cfg, "alq_policy", "exclude")
    if (!bp %in% c("exclude", "half_lloq", "lloq") || !ap %in% c("exclude", "uloq")) vaccine_stop("Unsupported assay-limit policy.")
    t <- vaccine_columns(data$titers, c("USUBJID", "ASSAY", "ANTIGEN", "UNIT", "VISIT", "AVAL", "QUALIFIER", "LLOQ", "ULOQ"), "titers")
    for (name in c("USUBJID", "ASSAY", "ANTIGEN", "UNIT", "VISIT", "QUALIFIER")) t[[name]] <- vaccine_text(t[[name]], paste("titers", name))
    for (name in c("AVAL", "LLOQ", "ULOQ")) t[[name]] <- vaccine_number(t[[name]], paste("titers", name), missing = TRUE)
    if (any(!t$USUBJID %in% p$USUBJID)) vaccine_stop("Titers contain orphan participant IDs.")
    if (any(!t$QUALIFIER %in% c("EXACT", "BLQ", "ALQ", "MISSING"))) vaccine_stop("QUALIFIER must be EXACT, BLQ, ALQ or MISSING.")
    if (any(t$QUALIFIER == "EXACT" & (is.na(t$AVAL) | t$AVAL <= 0))) vaccine_stop("EXACT titers must be positive and nonmissing.")
    if (any(t$QUALIFIER != "EXACT" & !is.na(t$AVAL))) vaccine_stop("BLQ, ALQ and MISSING qualifiers cannot have an AVAL; the limit policy derives the analysis value.")
    if (any(t$QUALIFIER == "BLQ" & is.na(t$LLOQ)) || any(t$QUALIFIER == "ALQ" & is.na(t$ULOQ))) vaccine_stop("BLQ requires a positive LLOQ and ALQ requires a positive ULOQ, even when excluded.")
    if (any(t$QUALIFIER == "EXACT" & ((!is.na(t$LLOQ) & t$AVAL < t$LLOQ) | (!is.na(t$ULOQ) & t$AVAL > t$ULOQ)))) vaccine_stop("EXACT values must lie within supplied quantification limits.")
    if (any(!is.na(t$LLOQ) & t$LLOQ <= 0) || any(!is.na(t$ULOQ) & t$ULOQ <= 0) || any(!is.na(t$LLOQ) & !is.na(t$ULOQ) & t$LLOQ >= t$ULOQ)) vaccine_stop("Assay limits must be positive with LLOQ < ULOQ.")
    selected <- t$ASSAY == assay & t$ANTIGEN == antigen & t$VISIT %in% visits
    if (any(t$UNIT[selected] != unit)) vaccine_stop("Mixed or unexpected units for the selected assay, antigen and visits. Standardize units before analysis.")
    eligible <- p$USUBJID[p$IMMFL == "Y"]
    if (!length(eligible)) vaccine_stop("No participants are included in the immunogenicity population.")
    if (as.double(length(eligible)) * length(visits) > 1000000) vaccine_stop("Expected immunogenicity grid exceeds 1,000,000 participant/visit assessments. Select fewer follow-up visits while retaining the full eligible population.")
    vaccine_unique(t[selected, , drop = FALSE], c("USUBJID", "VISIT"), "Selected immunogenicity records")
    s <- t[selected & t$USUBJID %in% eligible, , drop = FALSE]
    s$value <- rep(NA_real_, nrow(s)); s$analysis_status <- if (nrow(s)) paste0("excluded_", tolower(s$QUALIFIER)) else character()
    exact <- s$QUALIFIER == "EXACT"; s$value[exact] <- s$AVAL[exact]; s$analysis_status[exact] <- "observed_exact"
    blq <- s$QUALIFIER == "BLQ"; alq <- s$QUALIFIER == "ALQ"
    if (bp != "exclude") {
      if (any(is.na(s$LLOQ[blq]))) vaccine_stop("Selected BLQ substitution requires a positive LLOQ on every BLQ record.")
      s$value[blq] <- s$LLOQ[blq] / if (bp == "half_lloq") 2 else 1
      s$analysis_status[blq] <- paste0("substituted_", bp)
    }
    if (ap == "uloq") {
      if (any(is.na(s$ULOQ[alq]))) vaccine_stop("Selected ALQ substitution requires a positive ULOQ on every ALQ record.")
      s$value[alq] <- s$ULOQ[alq]; s$analysis_status[alq] <- "substituted_uloq"
    }
    grid <- expand.grid(USUBJID = eligible, VISIT = visits, stringsAsFactors = FALSE)
    grid <- merge(grid, s, by = c("USUBJID", "VISIT"), all.x = TRUE, sort = FALSE)
    grid$ARM <- p$ARM[match(grid$USUBJID, p$USUBJID)]
    absent <- is.na(grid$QUALIFIER); grid$analysis_status[absent] <- "absent_record"; grid$QUALIFIER[absent] <- "ABSENT"
    grid <- grid[order(grid$ARM, grid$USUBJID, match(grid$VISIT, visits)), , drop = FALSE]
    prepared$titers <- grid; prepared$visits <- visits; prepared$baseline <- baseline
    prepared$assay <- assay; prepared$antigen <- antigen; prepared$unit <- unit
    prepared$blq_policy <- bp; prepared$alq_policy <- ap
    prepared$titer_summary <- vaccine_immunogenicity(prepared)
    prepared$pairs <- vaccine_pairs(prepared)
    if ("response" %in% ids) {
      rule <- vaccine_scalar(cfg, "response_rule")
      if (!rule %in% c("threshold", "fold_rise", "conditional")) vaccine_stop("Unsupported response rule.")
      for (key in if (rule == "threshold") "response_threshold" else if (rule == "fold_rise") "fold_threshold" else c("response_threshold", "fold_threshold", "baseline_threshold")) {
        value <- vaccine_number(vaccine_scalar(cfg, key), key)
        if (value <= if (key == "fold_threshold") 1 else 0) vaccine_stop(key, " must exceed ", if (key == "fold_threshold") 1 else 0, ".")
      }
    }
    audits[[length(audits) + 1L]] <- data.frame(source = "titers", category = c("Uploaded records", "Other assay or antigen", "Selected assay/antigen outside selected visits", "Selected records outside immunogenicity population", "Selected immunogenicity records", "Absent expected participant/visit records", "Selected BLQ records", "Selected ALQ records", "Substituted selected records"), n_records = c(nrow(t), sum(t$ASSAY != assay | t$ANTIGEN != antigen), sum(t$ASSAY == assay & t$ANTIGEN == antigen & !t$VISIT %in% visits), sum(selected & !t$USUBJID %in% eligible), nrow(s), sum(absent), sum(blq), sum(alq), sum(grepl("^substituted", s$analysis_status))))
  }
  if (any(ids %in% c("reactogenicity", "diary_profile"))) {
    dose_labels <- vaccine_choices(cfg, "dose_labels"); symptoms <- vaccine_choices(cfg, "symptoms")
    start <- vaccine_number(vaccine_scalar(cfg, "day_start"), "day_start", integer = TRUE)
    end <- vaccine_number(vaccine_scalar(cfg, "day_end"), "day_end", integer = TRUE)
    max_grade <- vaccine_number(vaccine_scalar(cfg, "max_grade"), "max_grade", integer = TRUE)
    if (start < -1 || end > 60 || end < start) vaccine_stop("Diary window must be ordered within -1 to 60 days inclusive.")
    if (max_grade < 1 || max_grade > 5) vaccine_stop("max_grade must be from 1 through 5.")
    policy <- vaccine_scalar(cfg, "react_denominator", "complete")
    if (!policy %in% c("complete", "observed")) vaccine_stop("react_denominator must be complete or observed.")
    doses <- vaccine_columns(data$doses, c("USUBJID", "DOSE"), "doses")
    for (name in names(doses)) doses[[name]] <- vaccine_text(doses[[name]], paste("doses", name))
    vaccine_unique(doses, c("USUBJID", "DOSE"), "Actual administered doses")
    if (any(!doses$USUBJID %in% p$USUBJID)) vaccine_stop("Doses contain orphan participant IDs.")
    diary <- vaccine_columns(data$diary, c("USUBJID", "DOSE", "DAY", "SYMPTOM", "GRADE"), "diary")
    for (name in c("USUBJID", "DOSE", "SYMPTOM")) diary[[name]] <- vaccine_text(diary[[name]], paste("diary", name))
    diary$DAY <- vaccine_number(diary$DAY, "diary DAY", integer = TRUE)
    diary$GRADE <- vaccine_number(diary$GRADE, "diary GRADE", integer = TRUE, missing = TRUE)
    if (any(!is.na(diary$GRADE) & (diary$GRADE < 0 | diary$GRADE > max_grade))) vaccine_stop("Diary grades must be 0 through configured max_grade, or missing.")
    if (any(!diary$USUBJID %in% p$USUBJID)) vaccine_stop("Diary contains orphan participant IDs.")
    key <- function(d) paste(nchar(d$USUBJID), d$USUBJID, nchar(d$DOSE), d$DOSE, sep = ":")
    if (any(!key(diary) %in% key(doses))) vaccine_stop("Diary contains orphan doses not present in the administered-dose roster.")
    eligible <- p$USUBJID[p$SAFEFL == "Y"]
    roster <- doses[doses$USUBJID %in% eligible & doses$DOSE %in% dose_labels, , drop = FALSE]
    if (!nrow(roster)) vaccine_stop("No safety-population recipients have a selected administered dose.")
    expected_size <- as.double(nrow(roster)) * length(symptoms) * (end - start + 1)
    if (expected_size > 1000000) vaccine_stop("Expected diary grid exceeds 1,000,000 assessments. Select fewer doses or symptoms while retaining the prespecified window and population.")
    roster$ARM <- p$ARM[match(roster$USUBJID, p$USUBJID)]
    vaccine_unique(diary, c("USUBJID", "DOSE", "SYMPTOM", "DAY"), "Daily diary records")
    selected <- diary$USUBJID %in% eligible & diary$DOSE %in% dose_labels & diary$SYMPTOM %in% symptoms & diary$DAY >= start & diary$DAY <= end
    s <- diary[selected, , drop = FALSE]
    grid <- merge(roster, expand.grid(SYMPTOM = symptoms, DAY = seq.int(start, end), stringsAsFactors = FALSE), by = NULL)
    s$record_present <- rep(TRUE, nrow(s))
    grid <- merge(grid, s, by = c("USUBJID", "DOSE", "SYMPTOM", "DAY"), all.x = TRUE, sort = FALSE)
    grid$record_present[is.na(grid$record_present)] <- FALSE
    grid <- grid[order(grid$ARM, grid$DOSE, grid$USUBJID, grid$SYMPTOM, grid$DAY), , drop = FALSE]
    prepared$diary <- grid; prepared$doses <- roster; prepared$dose_labels <- dose_labels; prepared$symptoms <- symptoms
    prepared$day_start <- start; prepared$day_end <- end; prepared$max_grade <- max_grade; prepared$react_denominator <- policy
    prepared$diary_maxima <- vaccine_diary_maxima(prepared)
    audits[[length(audits) + 1L]] <- data.frame(source = "diary", category = c("Uploaded daily records", "Outside selected population/doses/symptoms/window", "Selected daily records", "Expected participant/dose/symptom/day assessments", "Absent daily rows", "Present rows with missing grades", "Explicit grade-zero assessments"), n_records = c(nrow(diary), sum(!selected), nrow(s), nrow(grid), sum(!grid$record_present), sum(grid$record_present & is.na(grid$GRADE)), sum(grid$GRADE == 0, na.rm = TRUE)))
  }
  prepared$audit <- vaccine_bind(audits)
  class(prepared) <- c("vaccine_prepared", "list")
  prepared
}

vaccine_immunogenicity <- function(p) {
  rows <- list()
  for (arm in p$arms) for (visit in p$visits) {
    d <- p$titers[p$titers$ARM == arm & p$titers$VISIT == visit, , drop = FALSE]; ok <- !is.na(d$value)
    stats <- vaccine_log_summary(log(d$value[ok]), p$confidence)
    names(stats)[names(stats) == "estimate"] <- "geometric_mean"
    rows[[length(rows) + 1L]] <- cbind(data.frame(ARM = arm, VISIT = visit, ASSAY = p$assay, ANTIGEN = p$antigen, UNIT = p$unit, n_population = nrow(d), n_records = sum(d$QUALIFIER != "ABSENT"), n_evaluable = sum(ok), n_not_evaluable = sum(!ok), n_absent = sum(d$QUALIFIER == "ABSENT"), n_missing_result = sum(d$QUALIFIER == "MISSING"), n_blq = sum(d$QUALIFIER == "BLQ"), n_alq = sum(d$QUALIFIER == "ALQ"), n_substituted = sum(grepl("^substituted", d$analysis_status)), blq_policy = p$blq_policy, alq_policy = p$alq_policy, stringsAsFactors = FALSE), stats[setdiff(names(stats), "n")])
  }
  vaccine_bind(rows)
}
vaccine_pairs <- function(p) {
  base <- p$titers[p$titers$VISIT == p$baseline, c("USUBJID", "value"), drop = FALSE]; names(base)[2] <- "baseline_value"
  post <- p$titers[p$titers$VISIT != p$baseline, c("USUBJID", "ARM", "VISIT", "value"), drop = FALSE]; names(post)[4] <- "post_value"
  result <- merge(post, base, by = "USUBJID", all.x = TRUE, sort = FALSE)
  result$paired <- !is.na(result$baseline_value) & !is.na(result$post_value)
  result$log_fold_rise <- rep(NA_real_, nrow(result)); result$log_fold_rise[result$paired] <- log(result$post_value[result$paired]) - log(result$baseline_value[result$paired])
  result[order(result$ARM, match(result$VISIT, p$visits), result$USUBJID), , drop = FALSE]
}
vaccine_fold_rise <- function(p) {
  rows <- list()
  for (arm in p$arms) for (visit in p$visits[-1]) {
    d <- p$pairs[p$pairs$ARM == arm & p$pairs$VISIT == visit, , drop = FALSE]
    stats <- vaccine_log_summary(d$log_fold_rise[d$paired], p$confidence); names(stats)[names(stats) == "estimate"] <- "geometric_mean_fold_rise"
    rows[[length(rows) + 1L]] <- cbind(data.frame(ARM = arm, VISIT = visit, baseline_visit = p$baseline, ASSAY = p$assay, ANTIGEN = p$antigen, n_population = nrow(d), n_paired = sum(d$paired), n_unpaired = sum(!d$paired), n_baseline_unavailable = sum(is.na(d$baseline_value)), n_post_unavailable = sum(is.na(d$post_value)), n_both_unavailable = sum(is.na(d$baseline_value) & is.na(d$post_value)), stringsAsFactors = FALSE), stats[setdiff(names(stats), "n")])
  }
  vaccine_bind(rows)
}
vaccine_fold_response <- function(post, baseline, threshold) {
  # Multiplying a positive baseline by a threshold >1 cannot underflow.
  # Above this bound no finite post-value can meet the threshold; never multiply it.
  safe <- baseline <= .Machine$double.xmax / threshold
  result <- rep(FALSE, length(post))
  result[safe] <- post[safe] >= baseline[safe] * threshold
  result
}
vaccine_response <- function(p, cfg) {
  rule <- vaccine_scalar(cfg, "response_rule"); rt <- if (rule != "fold_rise") as.numeric(cfg$response_threshold) else NA_real_; ft <- if (rule != "threshold") as.numeric(cfg$fold_threshold) else NA_real_; bt <- if (rule == "conditional") as.numeric(cfg$baseline_threshold) else NA_real_
  rows <- list()
  for (arm in p$arms) for (visit in p$visits[-1]) {
    d <- p$pairs[p$pairs$ARM == arm & p$pairs$VISIT == visit, , drop = FALSE]
    evaluable <- if (rule == "threshold") !is.na(d$post_value) else d$paired
    respond <- rep(FALSE, nrow(d))
    if (rule == "threshold") respond[evaluable] <- d$post_value[evaluable] >= rt
    if (rule == "fold_rise") respond[evaluable] <- vaccine_fold_response(d$post_value[evaluable], d$baseline_value[evaluable], ft)
    if (rule == "conditional") respond[evaluable] <- ifelse(d$baseline_value[evaluable] < bt, d$post_value[evaluable] >= rt, vaccine_fold_response(d$post_value[evaluable], d$baseline_value[evaluable], ft))
    stats <- vaccine_exact_ci(sum(respond), sum(evaluable), p$confidence)
    names(stats)[names(stats) == "events"] <- "n_responders"; names(stats)[names(stats) == "n"] <- "n_evaluable"
    rows[[length(rows) + 1L]] <- cbind(data.frame(ARM = arm, VISIT = visit, baseline_visit = p$baseline, n_population = nrow(d), n_not_evaluable = sum(!evaluable), n_unpaired = sum(!d$paired), rule = rule, response_threshold = rt, threshold_unit = p$unit, fold_threshold = ft, baseline_threshold = bt, stringsAsFactors = FALSE), stats)
  }
  vaccine_bind(rows)
}
vaccine_diary_maxima <- function(p) {
  grid <- p$diary
  if (!nrow(grid)) return(data.frame(USUBJID = character(), ARM = character(), DOSE = character(), SYMPTOM = character(), day_start = numeric(), day_end = numeric(), n_expected_days = numeric(), n_assessed_days = numeric(), n_missing_days = numeric(), n_absent_rows = numeric(), complete_window = logical(), observed_max_grade = numeric()))
  # Collision-safe numeric keys and vector aggregation avoid a full-grid scan or
  # separate data frame allocation for each participant/dose/symptom.
  keys <- paste(match(grid$USUBJID, p$participants$USUBJID), match(grid$DOSE, p$dose_labels), match(grid$SYMPTOM, p$symptoms), sep = ":")
  group <- match(keys, unique(keys)); first <- match(seq_len(max(group)), group)
  total <- function(values) as.integer(rowsum(as.integer(values), group, reorder = FALSE)[, 1])
  assessed <- !is.na(grid$GRADE); n <- total(assessed)
  maximum <- rep(0, length(n))
  for (grade in seq_len(p$max_grade)) maximum[total(assessed & grid$GRADE == grade) > 0] <- grade
  maximum[n == 0] <- NA_real_
  expected <- p$day_end - p$day_start + 1L
  result <- data.frame(grid[first, c("USUBJID", "ARM", "DOSE", "SYMPTOM"), drop = FALSE], day_start = p$day_start, day_end = p$day_end, n_expected_days = expected, n_assessed_days = n, n_missing_days = expected - n, n_absent_rows = total(!grid$record_present), complete_window = n == expected, observed_max_grade = maximum, row.names = NULL, stringsAsFactors = FALSE)
  result[order(result$ARM, result$DOSE, result$SYMPTOM, result$USUBJID), , drop = FALSE]
}

vaccine_reactogenicity <- function(p) {
  rates <- distributions <- list()
  for (arm in p$arms) for (dose in p$dose_labels) for (symptom in p$symptoms) {
    d <- p$diary_maxima[p$diary_maxima$ARM == arm & p$diary_maxima$DOSE == dose & p$diary_maxima$SYMPTOM == symptom, , drop = FALSE]
    observed <- d$n_assessed_days > 0; complete <- d$complete_window; partial <- observed & !complete
    use <- if (p$react_denominator == "complete") complete else observed
    events <- sum(d$observed_max_grade[use] >= 1)
    stats <- vaccine_exact_ci(events, sum(use), p$confidence); names(stats)[names(stats) == "n"] <- "n_denominator"; names(stats)[names(stats) == "events"] <- "n_reaction"
    rates[[length(rates) + 1L]] <- cbind(data.frame(ARM = arm, DOSE = dose, SYMPTOM = symptom, day_start = p$day_start, day_end = p$day_end, n_dosed = nrow(d), n_complete = sum(complete), n_partial = sum(partial), n_unassessed = sum(!observed), n_partial_positive = sum(d$observed_max_grade[partial] >= 1), n_missing_day_assessments = sum(d$n_missing_days), denominator_policy = p$react_denominator, interpretation = if (p$react_denominator == "complete") "Reaction among participants with every window day assessed for this symptom" else "Observed reaction among participants with at least one assessed day; incomplete diaries can miss reactions", stringsAsFactors = FALSE), stats)
    for (scope in c("Complete-window maximum", "Observed maximum over available days")) for (grade in seq.int(0, p$max_grade)) {
      target <- if (scope == "Complete-window maximum") complete else observed
      n <- sum(target); count <- sum(d$observed_max_grade[target] == grade)
      distributions[[length(distributions) + 1L]] <- data.frame(ARM = arm, DOSE = dose, SYMPTOM = symptom, scope = scope, grade = grade, n_grade = count, n_denominator = n, percent = if (n) 100 * count/n else NA_real_, n_unassessed = sum(!observed), stringsAsFactors = FALSE)
    }
  }
  list(rates = vaccine_bind(rates), distribution = vaccine_bind(distributions))
}
vaccine_daily <- function(p) {
  rows <- list()
  for (arm in p$arms) for (dose in p$dose_labels) for (symptom in p$symptoms) for (day in seq.int(p$day_start, p$day_end)) {
    d <- p$diary[p$diary$ARM == arm & p$diary$DOSE == dose & p$diary$SYMPTOM == symptom & p$diary$DAY == day, , drop = FALSE]; assessed <- !is.na(d$GRADE)
    stats <- vaccine_exact_ci(sum(d$GRADE[assessed] >= 1), sum(assessed), p$confidence); names(stats)[names(stats) == "n"] <- "n_assessed"; names(stats)[names(stats) == "events"] <- "n_reaction"
    rows[[length(rows) + 1L]] <- cbind(data.frame(ARM = arm, DOSE = dose, SYMPTOM = symptom, DAY = day, n_dosed = nrow(d), n_missing = sum(!assessed), n_absent_rows = sum(!d$record_present), stringsAsFactors = FALSE), stats)
  }
  vaccine_bind(rows)
}
vaccine_empty_plot <- function(title, label) {
  ggplot2::ggplot() + ggplot2::annotate("text", x = 0, y = 0, label = label, size = 4) + ggplot2::labs(title = title) + ggplot2::theme_void()
}
vaccine_output <- function(id, prepared, cfg) {
  p <- prepared
  if (!inherits(p, "vaccine_prepared") || !id %in% p$outputs) vaccine_stop("Output was not selected in this prepared vaccine analysis.")
  component <- function(name, value) list(name = name, value = value)
  notes <- c("Descriptive study summaries; no efficacy, protection or immunobridging conclusion is calculated.", "Confidence intervals are pointwise and unadjusted for multiplicity; no between-arm tests are performed.", paste0("Two-sided confidence level: ", 100 * p$confidence, "%. Population flags and prespecified visit assignments are supplied by the study."))
  warnings <- character(); components <- list()
  if (id %in% c("immunogenicity", "fold_rise", "response", "titer_plot")) {
    notes <- c(notes, paste("Assay:", p$assay, "| Antigen:", p$antigen, "| Units:", p$unit), paste("BLQ policy:", p$blq_policy, "| ALQ policy:", p$alq_policy, "| No other missing-value imputation."), "GMT/GMC and paired GMFR use natural-log Student-t intervals. One evaluable observation provides a point estimate without a confidence interval.")
    if (id == "immunogenicity") { title <- "Immunogenicity: GMT / GMC by visit"; components <- list(component("Geometric means and missingness", p$titer_summary)) }
    if (id == "fold_rise") { title <- "Paired geometric mean fold rise"; components <- list(component("Paired GMFR", vaccine_fold_rise(p))); notes <- c(notes, paste("Paired reference visit:", p$baseline, "| Complete positive analysis-value pairs only.")) }
    if (id == "response") { title <- "Prespecified responder analysis"; components <- list(component("Responder rates", vaccine_response(p, cfg))); notes <- c(notes, "Response uses inclusive post-value/fold-rise boundaries and exact Clopper-Pearson intervals. Conditional rule: baseline below its threshold requires the post-value threshold; baseline at or above its threshold requires the fold-rise threshold. Thresholds are study definitions, not claims of protection.") }
    if (id == "titer_plot") {
      title <- "Immunogenicity visit trends"
      d <- p$titer_summary; d$VISIT <- factor(d$VISIT, levels = p$visits)
      plot <- ggplot2::ggplot(d, ggplot2::aes(x = VISIT, y = geometric_mean, colour = ARM, group = ARM)) + ggplot2::geom_point(size = 2, na.rm = TRUE) + ggplot2::geom_line(na.rm = TRUE) + ggplot2::geom_errorbar(data = d[!is.na(d$lower) & !is.na(d$upper), ], ggplot2::aes(ymin = lower, ymax = upper), width = .1) + ggplot2::scale_y_log10() + ggplot2::labs(title = title, subtitle = paste(p$assay, p$antigen, sep = " · "), x = "Prespecified visit", y = paste("GMT / GMC (", p$unit, "; log scale)", sep = ""), colour = "Study arm", caption = "Observed/substituted analysis values under the configured limit policies; counts are in the accompanying table.") + ggplot2::theme_minimal(base_size = 12) + ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 30, hjust = 1), legend.position = "bottom")
      if (!any(!is.na(d$geometric_mean))) plot <- vaccine_empty_plot(title, "No evaluable titers under the configured assay-limit policies.\nSee the accompanying population and missingness table.")
      components <- list(component("Visit trend", plot), component("Trend estimates and denominators", p$titer_summary))
    }
  } else {
    notes <- c(notes, paste0("Inclusive diary window: days ", p$day_start, " through ", p$day_end, "; grades 0–", p$max_grade, " are supplied under the protocol's grading rules."), "An explicit grade 0 is an assessed absence. Blank grades and absent rows are missing; no absence or grade is imputed.", "Denominators use safety-population participants with an actual administered dose. Completeness is assessed separately for each symptom and dose.")
    if (id == "reactogenicity") {
      title <- "Solicited reactions by dose and maximum grade"; result <- vaccine_reactogenicity(p)
      components <- list(component("Reaction incidence and missingness", result$rates), component("Maximum-grade distributions with distinct completeness scopes", result$distribution), component("Participant observed maxima and diary completeness", p$diary_maxima))
      notes <- c(notes, paste("Selected incidence denominator:", p$react_denominator), "Observed maximum grades in incomplete diaries may underestimate the true window maximum. Partial-diary positives are shown separately and are excluded from complete-window incidence.")
    } else {
      title <- "Daily solicited-reaction profile"; d <- vaccine_daily(p)
      components <- list()
      for (dose in p$dose_labels) for (first in seq.int(1L, length(p$symptoms), by = 4L)) {
        panel_symptoms <- p$symptoms[seq.int(first, min(first + 3L, length(p$symptoms)))]
        part <- d[d$DOSE == dose & d$SYMPTOM %in% panel_symptoms, , drop = FALSE]
        part$SYMPTOM <- factor(part$SYMPTOM, levels = panel_symptoms)
        plot <- ggplot2::ggplot(part, ggplot2::aes(x = DAY, y = percent, colour = ARM, group = ARM)) + ggplot2::geom_line(na.rm = TRUE) + ggplot2::geom_point(na.rm = TRUE) + ggplot2::facet_wrap(~ SYMPTOM, ncol = 2, drop = FALSE) + ggplot2::scale_y_continuous(limits = c(0, 100)) + ggplot2::labs(title = paste(title, dose, sep = " · "), x = "Configured day relative to vaccination", y = "Observed reaction among assessed participants (%)", colour = "Study arm", caption = "Each day uses assessed participants for that symptom and dose. Missing diaries are never coded as no reaction.") + ggplot2::theme_minimal(base_size = 12) + ggplot2::theme(legend.position = "bottom")
        no_assessed <- panel_symptoms[!vapply(panel_symptoms, function(symptom) any(!is.na(part$percent[part$SYMPTOM == symptom])), logical(1))]
        if (length(no_assessed)) {
          labels <- data.frame(SYMPTOM = factor(no_assessed, levels = panel_symptoms), DAY = mean(c(p$day_start, p$day_end)), percent = 50, label = "No assessed diary days")
          plot <- plot + ggplot2::geom_text(data = labels, ggplot2::aes(x = DAY, y = percent, label = label), inherit.aes = FALSE, colour = "grey35", size = 3)
        }
        components[[length(components) + 1L]] <- component(paste("Daily reactions", dose, paste(panel_symptoms, collapse = ", "), sep = " · "), plot)
      }
      components[[length(components) + 1L]] <- component("Complete daily counts, exact intervals and missingness", d)
      notes <- c(notes, "Daily figures are paginated by dose with at most four symptoms per figure. The daily table includes every selected dose, symptom, day and arm.")
    }
    if (any(p$diary_maxima$n_missing_days > 0)) warnings <- "Incomplete or entirely missing diary windows are present. Review the displayed denominators and partial-positive counts."
  }
  components[[length(components) + 1L]] <- component("Input selection and missingness audit", p$audit)
  list(title = list(titles = c("", "", title), footnotes = notes), components = components, warnings = warnings)
}
