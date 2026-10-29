# Runnable, client-neutral analysis functions. Settings are supplied by the launcher.
# These implement the named statistical methods; suitability remains study-specific.
tfl_model_setting <- function(name, default = NULL) getOption("tfl.settings", list())[[name]] %||% default
`%||%` <- function(x, y) if (is.null(x)) y else x
tfl_model_codes <- function(name, default) {
  x <- tfl_model_setting(name, default)
  if (is.list(x)) x <- unlist(x, use.names = FALSE)
  x <- unique(trimws(unlist(strsplit(as.character(x), ",", fixed = TRUE))))
  if (!length(x) || any(!nzchar(x))) stop(name, " must contain nonempty codes.")
  x
}
tfl_model_number <- function(name, default) {
  x <- suppressWarnings(as.numeric(tfl_model_setting(name, default)))
  if (length(x) != 1L || !is.finite(x)) stop(name, " must be one finite number.")
  x
}
tfl_model_confidence <- function(name, default) {
  x <- tfl_model_number(name, default)
  if (x <= 0 || x >= 1) stop(name, " must be between zero and one.")
  x
}
tfl_model_bounds <- function(prefix) {
  x <- c(tfl_model_number(paste0(prefix, "_lower"), .8), tfl_model_number(paste0(prefix, "_upper"), 1.25))
  if (x[1] <= 0 || x[1] >= 1 || x[2] <= 1) stop(prefix, " bounds must straddle one and be positive.")
  x
}
tfl_model_columns <- function(d, columns, label) {
  missing <- setdiff(columns, names(d))
  if (length(missing)) stop(label, ": missing columns ", paste(missing, collapse = ", "))
}
tfl_model_unique <- function(d, columns, label) {
  tfl_model_columns(d, columns, label)
  if (any(!complete.cases(d[, columns, drop = FALSE]))) stop(label, ": missing analysis key.")
  if (any(duplicated(d[, columns, drop = FALSE]))) stop(label, ": duplicate analysis key (", paste(columns, collapse = ", "), "). Select one prespecified analysis record.")
}
tfl_model_units <- function(d, by = "PARAMCD") {
  tfl_model_columns(d, c(by, "AVALU"), "Analysis units")
  if (any(is.na(d$AVALU) | !nzchar(trimws(d$AVALU)))) stop("Analysis units must be supplied for every selected record.")
  if (nrow(d) && any(d %>% group_by(across(all_of(by))) %>% summarise(n = n_distinct(AVALU), .groups = "drop") %>% pull(n) > 1L)) stop("Mixed units within an analysis parameter; standardize units before analysis.")
}
tfl_model_dose <- function(labels) {
  setting <- tfl_model_setting("dose_map", NULL)
  if (is.null(setting) || !length(setting) || identical(setting, "")) stop("Specify actual dose for each treatment in dose_map; treatment ordering codes are not doses.")
  if (is.character(setting) && is.null(names(setting))) {
    lines <- trimws(unlist(strsplit(paste(setting, collapse = "\n"), "[\n;]")))
    lines <- lines[nzchar(lines)]
    pairs <- strsplit(lines, "=", fixed = TRUE)
    if (!length(pairs) || any(lengths(pairs) != 2L)) stop("dose_map must use one Treatment label=actual dose entry per line.")
    keys <- trimws(vapply(pairs, `[[`, "", 1L))
    values <- suppressWarnings(as.numeric(trimws(vapply(pairs, `[[`, "", 2L))))
    setting <- setNames(values, keys)
  } else setting <- unlist(setting)
  if (is.null(names(setting)) || anyDuplicated(names(setting)) || any(!nzchar(names(setting)))) stop("dose_map needs unique treatment labels.")
  doses <- suppressWarnings(as.numeric(setting)); names(doses) <- names(setting)
  if (any(!is.finite(doses) | doses < 0)) stop("Actual doses must be finite and nonnegative.")
  if (!nzchar(trimws(tfl_model_setting("dose_unit", "")))) stop("Specify the actual dose unit.")
  if (any(!labels %in% names(doses))) stop("dose_map missing treatment(s): ", paste(unique(labels[!labels %in% names(doses)]), collapse = ", "))
  unname(doses[labels])
}
tfl_model_fit <- function(fun) {
  warnings <- character()
  fit <- withCallingHandlers(tryCatch(fun(), error = function(e) stop("Model not estimable: ", conditionMessage(e))), warning = function(w) { warnings <<- c(warnings, conditionMessage(w)); invokeRestart("muffleWarning") })
  status <- if (length(warnings)) paste(unique(warnings), collapse = "; ") else "Estimated"
  if (inherits(fit, "merMod")) {
    messages <- fit@optinfo$conv$lme4$messages
    if (length(messages)) status <- paste(status, paste(messages, collapse = "; "), sep = "; ")
    if (any(grepl("failed to converge|unable to evaluate|degenerate Hessian|nearly unidentifiable|may not have converged", c(messages, warnings), ignore.case = TRUE))) stop("Model not estimable: convergence or identifiability checks failed. ", status)
    if (lme4::isSingular(fit)) status <- paste(status, "Singular random-effects fit", sep = "; ")
  }
  list(fit = fit, status = status)
}
tfl_model_be <- function(adpp, design) {
  for (pkg in c("lmerTest", "emmeans")) if (!requireNamespace(pkg, quietly = TRUE)) stop("Required model dependency: ", pkg)
  parameters <- tfl_model_codes("pk_parameters", "CMAX, AUCLST, AUCIFO")
  confidence <- tfl_model_confidence("be_confidence", .9); bounds <- tfl_model_bounds("be")
  arm <- if (design == "CROSSOVER") "TRTA" else "APERIODC"
  needed <- c("USUBJID", "PKFL", "PARAMCD", "AVAL", "AVALU", "APERIOD", arm)
  if (design == "CROSSOVER") needed <- c(needed, "TRTSEQP")
  tfl_model_columns(adpp, needed, "BE ADPP")
  pp <- adpp %>% filter(PKFL == "Y", PARAMCD %in% parameters)
  tfl_model_unique(pp, c("USUBJID", "PARAMCD", "APERIOD"), "BE ADPP")
  tfl_model_units(pp)
  # Launcher maps the supplied reference/test labels to these canonical labels.
  if (any(!pp[[arm]] %in% c("Reference", "Test"))) stop("BE supports exactly the configured reference and test levels.")
  bind_rows(lapply(parameters, function(parameter) {
    original <- pp %>% filter(PARAMCD == parameter)
    d <- original %>% filter(is.finite(AVAL), AVAL > 0)
    complete <- d %>% group_by(USUBJID) %>% summarise(ok = n() == 2L && n_distinct(.data[[arm]]) == 2L && n_distinct(APERIOD) == 2L, .groups = "drop")
    d <- d %>% filter(USUBJID %in% complete$USUBJID[complete$ok])
    excluded <- n_distinct(original$USUBJID) - n_distinct(d$USUBJID)
    if (n_distinct(d$USUBJID) < 3L || n_distinct(d$APERIOD) != 2L) stop(parameter, ": at least three complete participants and exactly two periods are required; incomplete/nonpositive pairs excluded: ", excluded)
    d <- d %>% mutate(lnval = log(AVAL), subj = factor(USUBJID), trt = factor(.data[[arm]], levels = c("Reference", "Test")), per = factor(APERIOD))
    if (design == "CROSSOVER") {
      d$seq <- factor(d$TRTSEQP)
      seqcheck <- d %>% arrange(APERIOD) %>% group_by(USUBJID, seq) %>% summarise(order = paste(trt, collapse = "/"), .groups = "drop")
      if (nlevels(d$seq) != 2L || any((seqcheck %>% count(seq, order) %>% count(seq))$n != 1L) || !setequal(seqcheck$order, c("Reference/Test", "Test/Reference"))) stop("BE supports a non-replicate randomized 2x2 crossover with two consistent opposite sequences.")
      formula <- lnval ~ seq + per + trt + (1 | subj)
    } else {
      if (any((d %>% distinct(per, trt) %>% count(per))$n != 1L)) stop("Fixed-sequence periods must consistently map to the reference and test conditions.")
      formula <- lnval ~ trt + (1 | subj)
    }
    fitted <- tfl_model_fit(function() lmerTest::lmer(formula, data = d, REML = TRUE))
    em <- emmeans::emmeans(fitted$fit, ~ trt, lmer.df = "satterthwaite", disable.lmerTest = FALSE, lmerTest.limit = Inf)
    ci <- as.data.frame(confint(emmeans::contrast(em, list("Test / Reference" = c(-1, 1))), level = confidence))
    if (any(!is.finite(unlist(ci[1, c("estimate", "SE", "df", "lower.CL", "upper.CL")])))) stop(parameter, ": contrast not estimable.")
    tibble(parameter = parameter, n_paired = n_distinct(d$USUBJID), excluded_participants = excluded, gmr = exp(ci$estimate), lower = exp(ci$lower.CL), upper = exp(ci$upper.CL), confidence = confidence, df = ci$df,
           lower_bound = bounds[1], upper_bound = bounds[2], within_specified_bounds = exp(ci$lower.CL) >= bounds[1] & exp(ci$upper.CL) <= bounds[2], intra_cv_percent = 100 * sqrt(expm1(sigma(fitted$fit)^2)), df_method = "Satterthwaite (lmerTest)", status = fitted$status)
  }))
}
tfl_model_power <- function(d, confidence = .9, bounds = c(.8, 1.25)) {
  tfl_model_unique(d, "USUBJID", "Power-model observations")
  excluded <- sum(!is.finite(d$value) | d$value <= 0 | !is.finite(d$dose) | d$dose <= 0)
  d <- d %>% filter(is.finite(value), value > 0, is.finite(dose), dose > 0)
  ndose <- n_distinct(d$dose)
  empty <- tibble(n = nrow(d), excluded_records = excluded, dose_levels = ndose, dose_ratio = NA_real_, beta = NA_real_, lower = NA_real_, upper = NA_real_, confidence = confidence, critical_lower = NA_real_, critical_upper = NA_real_, within_specified_bounds = NA, exposure_ratio = NA_real_, status = "Not estimable: at least two dose levels and three observations are required")
  if (ndose < 2L || nrow(d) < 3L) return(empty)
  ratio <- max(d$dose) / min(d$dose)
  fit <- lm(log(value) ~ log(dose), data = d)
  if (df.residual(fit) < 1L) return(empty)
  ci <- suppressWarnings(confint(fit, "log(dose)", level = confidence))[1, ]
  estimate <- unname(coef(fit)[2]); critical <- 1 + log(bounds) / log(ratio)
  tibble(n = nrow(d), excluded_records = excluded, dose_levels = ndose, dose_ratio = ratio, beta = estimate, lower = ci[1], upper = ci[2], confidence = confidence, critical_lower = critical[1], critical_upper = critical[2], within_specified_bounds = ci[1] >= critical[1] && ci[2] <= critical[2], exposure_ratio = ratio^estimate, status = if (any(!is.finite(ci))) "Not estimable: nonfinite confidence limits" else if (sigma(fit) < 1e-10) "Estimated; essentially zero residual variance" else "Estimated")
}
tfl_model_dose_proportionality <- function(adpp, mad = FALSE) {
  parameters <- tfl_model_codes(if (mad) "mad_pk_parameters" else "pk_parameters", if (mad) "CMAXSS, AUCTAU" else "CMAX, AUCLST, AUCIFO")
  tfl_model_columns(adpp, c("USUBJID", "PKFL", "TRT01A", "PARAMCD", "AVAL", "AVALU", if (mad) "ADY"), "Dose-proportionality ADPP")
  pp <- adpp %>% filter(PKFL == "Y", PARAMCD %in% parameters)
  if (mad) pp <- pp %>% filter(ADY == tfl_model_number("analysis_day", 14))
  tfl_model_units(pp); tfl_model_unique(pp, c("USUBJID", "PARAMCD"), "Dose-proportionality ADPP")
  pp$dose <- tfl_model_dose(pp$TRT01A)
  confidence <- tfl_model_confidence("dose_confidence", .9); bounds <- tfl_model_bounds("dose")
  bind_rows(lapply(parameters, function(parameter) {
    d <- pp %>% filter(PARAMCD == parameter) %>% transmute(USUBJID, dose, value = AVAL)
    bind_cols(tibble(parameter = parameter, analysis_day = if (mad) tfl_model_number("analysis_day", 14) else NA_real_, dose_unit = tfl_model_setting("dose_unit", "")), tfl_model_power(d, confidence, bounds))
  }))
}
tfl_model_paired <- function(first, last, confidence = .95) {
  if (length(first) != length(last)) stop("Paired arrays have different lengths.")
  ok <- is.finite(first) & first > 0 & is.finite(last) & last > 0
  delta <- log(last[ok]) - log(first[ok]); n <- length(delta)
  mean_delta <- if (n) mean(delta) else NA_real_
  half <- if (n > 1L) qt((1 + confidence)/2, n - 1L) * sd(delta)/sqrt(n) else NA_real_
  tibble(n_paired = n, excluded_pairs = sum(!ok), ratio = exp(mean_delta), lower = exp(mean_delta - half), upper = exp(mean_delta + half), confidence = confidence, status = if (n > 1L) "Estimated" else "Not estimable: fewer than two positive complete pairs")
}
tfl_model_trend <- function(d, confidence = .95) {
  excluded <- sum(!is.finite(d$AVAL) | d$AVAL <= 0)
  d <- d %>% filter(is.finite(AVAL), AVAL > 0)
  tfl_model_unique(d, c("USUBJID", "ADY"), "Trough trend")
  empty <- tibble(n = n_distinct(d$USUBJID), days = n_distinct(d$ADY), excluded_records = excluded, slope = NA_real_, lower = NA_real_, upper = NA_real_, confidence = confidence, status = "Not estimable: need at least three participants, two days, and repeated observations")
  if (empty$n < 3L || empty$days < 2L || nrow(d) <= empty$n) return(empty)
  fitted <- tryCatch(tfl_model_fit(function() lmerTest::lmer(log(AVAL) ~ ADY + (1 | USUBJID), data = d, REML = TRUE)), error = function(e) e)
  if (inherits(fitted, "error")) { empty$status <- conditionMessage(fitted); return(empty) }
  co <- coef(summary(fitted$fit))["ADY", ]; half <- qt((1 + confidence)/2, co["df"]) * co["Std. Error"]
  tibble(n = empty$n, days = empty$days, excluded_records = excluded, slope = unname(co["Estimate"]), lower = unname(co["Estimate"] - half), upper = unname(co["Estimate"] + half), confidence = confidence, status = fitted$status)
}
tfl_model_accumulation <- function(adpp, adpc) {
  tfl_model_columns(adpp, c("USUBJID", "PKFL", "TRT01A", "ADY", "PARAMCD", "AVAL", "AVALU"), "Accumulation ADPP")
  first_day <- tfl_model_number("accumulation_first_day", 1); last_day <- tfl_model_number("accumulation_last_day", 14)
  if (last_day <= first_day) stop("Accumulation final day must follow the first day.")
  confidence <- tfl_model_confidence("accumulation_confidence", .95)
  pairs <- list(Cmax = c(tfl_model_setting("accumulation_cmax_first", "CMAX"), tfl_model_setting("accumulation_cmax_last", "CMAXSS")), AUC = c(tfl_model_setting("accumulation_auc_first", "AUCLST"), tfl_model_setting("accumulation_auc_last", "AUCTAU")))
  pp <- adpp %>% filter(PKFL == "Y", ADY %in% c(first_day, last_day))
  pp$dose <- tfl_model_dose(pp$TRT01A); pp <- pp %>% filter(dose > 0)
  ratios <- bind_rows(lapply(names(pairs), function(label) {
    codes <- pairs[[label]]
    d1 <- pp %>% filter(ADY == first_day, PARAMCD == codes[1])
    dn <- pp %>% filter(ADY == last_day, PARAMCD == codes[2])
    tfl_model_unique(d1, "USUBJID", "Accumulation first occasion"); tfl_model_unique(dn, "USUBJID", "Accumulation final occasion")
    if (!nrow(d1) || !nrow(dn)) stop("No selected ", label, " records for one or both accumulation occasions.")
    tfl_model_units(bind_rows(d1, dn))
    joined <- full_join(d1 %>% select(USUBJID, first_trt = TRT01A, first_unit = AVALU, first = AVAL), dn %>% select(USUBJID, last_trt = TRT01A, last_unit = AVALU, last = AVAL), by = "USUBJID")
    if (any(!is.na(joined$first_unit) & !is.na(joined$last_unit) & joined$first_unit != joined$last_unit)) stop("Accumulation pair units differ.")
    if (any(!is.na(joined$first_trt) & !is.na(joined$last_trt) & joined$first_trt != joined$last_trt)) stop("Accumulation participants change treatment across occasions.")
    joined$trt <- coalesce(joined$first_trt, joined$last_trt)
    result <- joined %>% group_by(trt) %>% group_modify(~ tfl_model_paired(.x$first, .x$last, confidence)) %>% ungroup()
    comparable <- isTRUE(tfl_model_setting("accumulation_auc_comparable", FALSE))
    if (label == "AUC" && !comparable) { result$ratio <- result$lower <- result$upper <- NA_real_; result$status <- "Not calculated: comparable AUC integration intervals have not been confirmed" }
    result %>% mutate(parameter = label, actual_dose = tfl_model_dose(trt), dose_unit = tfl_model_setting("dose_unit", ""), first_code = codes[1], last_code = codes[2], first_day = first_day, last_day = last_day, .before = 1)
  }))
  trough <- tfl_model_trough(adpc, "PKFL", tfl_model_setting("pk_parameter", "CONC"))
  list(ratios = ratios, troughs = trough$summary, slopes = trough$slopes)
}
tfl_model_trough <- function(data, flag, parameter) {
  tfl_model_columns(data, c("USUBJID", flag, "TRT01A", "PARAMCD", "ADY", "ATPTN", "AVAL", "AVALU"), "Trough data")
  first <- tfl_model_number("steady_state_first_day", 5); last <- tfl_model_number("trough_last_day", 14)
  if (last < first) stop("Trough window end precedes start.")
  d <- data %>% filter(.data[[flag]] == "Y", PARAMCD == parameter, ATPTN == 0, ADY >= first, ADY <= last)
  d$dose <- tfl_model_dose(d$TRT01A); d <- d %>% filter(dose > 0)
  tfl_model_unique(d, c("USUBJID", "ADY"), "Selected pre-dose troughs"); tfl_model_units(d)
  if (!nrow(d)) stop("No pre-dose records (ATPTN = 0) in the selected trough window.")
  summary <- d %>% group_by(TRT01A, ADY) %>% summarise(n = sum(is.finite(AVAL)), missing = sum(!is.finite(AVAL)), mean = if (any(is.finite(AVAL))) mean(AVAL[is.finite(AVAL)]) else NA_real_, positive_n = sum(is.finite(AVAL) & AVAL > 0), geometric_mean = if (any(is.finite(AVAL) & AVAL > 0)) exp(mean(log(AVAL[is.finite(AVAL) & AVAL > 0]))) else NA_real_, .groups = "drop")
  slopes <- d %>% group_by(TRT01A) %>% group_modify(~ tfl_model_trend(.x)) %>% ungroup() %>% mutate(window_first_day = first, window_last_day = last, interpretation = "Descriptive log-trough trend; CI containing zero does not demonstrate steady state")
  list(summary = summary, slopes = slopes)
}
tfl_model_pd_data <- function(adpd, dv) {
  tfl_model_columns(adpd, c("USUBJID", "PDFL", "PARAMCD", "PARAM", dv$trtvar, dv$byperiod, "ADY", "AVISIT", "AVISITN", "ATPTN", "AVAL", "AVALU", "CHG", "PCHG"), "PD data")
  d <- adpd %>% filter(PDFL == "Y", PARAMCD == tfl_model_setting("pd_parameter", "PDMARK1"))
  if (!nrow(d)) stop("No records for the selected PD endpoint.")
  tfl_model_unique(d, c("USUBJID", dv$byperiod, "PARAMCD", "ADY", "AVISITN", "ATPTN"), "PD endpoint")
  tfl_model_units(d)
  d$trt <- d[[dv$trtvar]]
  d$period <- if (length(dv$byperiod)) as.character(d[[dv$byperiod[1]]]) else "All"
  d
}
tfl_model_pd_summary <- function(d) {
  d %>% pivot_longer(c(AVAL, CHG, PCHG), names_to = "measure", values_to = "value") %>%
    group_by(trt, period, PARAMCD, PARAM, ADY, AVISIT, AVISITN, ATPTN, measure) %>%
    summarise(unit = if (first(measure) == "PCHG") "%" else first(AVALU), n = sum(is.finite(value)), missing = sum(!is.finite(value)), mean = if (n) mean(value[is.finite(value)]) else NA_real_, sd = if (n > 1L) sd(value[is.finite(value)]) else NA_real_, median = if (n) median(value[is.finite(value)]) else NA_real_, min = if (n) min(value[is.finite(value)]) else NA_real_, max = if (n) max(value[is.finite(value)]) else NA_real_, .groups = "drop")
}
tfl_model_pd_peak <- function(d) {
  day <- tfl_model_number("analysis_day", 14)
  selected <- d %>% filter(ADY == day)
  selected$dose <- tfl_model_dose(selected$trt)
  metric <- selected %>% group_by(USUBJID, dose) %>% summarise(value = if (any(is.finite(AVAL))) max(AVAL[is.finite(AVAL)]) else NA_real_, .groups = "drop")
  bind_cols(tibble(parameter = tfl_model_setting("pd_parameter", "PDMARK1"), analysis_day = day, metric = "Maximum observed value on selected day; exploratory power model", dose_unit = tfl_model_setting("dose_unit", "")), tfl_model_power(metric, tfl_model_confidence("dose_confidence", .9), tfl_model_bounds("dose")))
}
tfl_model_overlay <- function(adpc, adpd, dv) {
  make_profile <- function(d, flag, parameter, label) {
    tfl_model_columns(d, c("USUBJID", flag, "PARAMCD", "ADY", "ATPTN", "AVAL", "AVALU", dv$trtvar, dv$byperiod), label)
    d <- d %>% filter(.data[[flag]] == "Y", PARAMCD == parameter)
    if (!nrow(d)) stop("No records for selected ", label, " parameter.")
    tfl_model_unique(d, c("USUBJID", dv$byperiod, "PARAMCD", "ADY", "ATPTN"), label); tfl_model_units(d)
    d$trt <- d[[dv$trtvar]]; d$period <- if (length(dv$byperiod)) as.character(d[[dv$byperiod[1]]]) else "All"
    d %>% group_by(trt, period, ADY, ATPTN) %>% summarise(n = sum(is.finite(AVAL)), mean = if (n) mean(AVAL[is.finite(AVAL)]) else NA_real_, unit = first(AVALU), .groups = "drop") %>% mutate(series = paste0(label, " (", unit, ")"))
  }
  bind_rows(make_profile(adpc, "PKFL", tfl_model_setting("pk_parameter", "CONC"), "PK concentration"), make_profile(adpd, "PDFL", tfl_model_setting("pd_parameter", "PDMARK1"), "PD response")) %>% mutate(panel = paste(trt, "Period", period, "Day", ADY), time = ATPTN)
}
# Exploratory closed-loop diagnostic. It is not a regulatory C-QTc assessment.
tfl_model_loop_area <- function(x, y) {
  if (length(x) != length(y) || length(x) < 3L || any(!is.finite(c(x, y)))) return(NA_real_)
  next_point <- c(seq_along(x)[-1L], 1L)
  .5 * sum(x * y[next_point] - x[next_point] * y)
}
tfl_model_area_test <- function(active, placebo, confidence = .95) {
  active <- active[is.finite(active)]; placebo <- placebo[is.finite(placebo)]
  n <- length(active); np <- length(placebo)
  result <- tibble(n = n, n_placebo = np, estimate = if (n) mean(active) else NA_real_, se = NA_real_, df = NA_real_, lower = NA_real_, upper = NA_real_, p_one_sided = NA_real_, p_two_sided = NA_real_, confidence = confidence, status = "Not estimable: at least two complete active and placebo profiles required")
  if (n < 2L || np < 2L) return(result)
  va <- var(active)/n; vp <- var(placebo)/np
  if (!is.finite(va + vp) || va + vp <= 0) { result$status <- "Not estimable: zero or nonfinite area variance"; return(result) }
  se <- sqrt(va + vp); df <- (va + vp)^2/(va^2/(n - 1L) + vp^2/(np - 1L))
  half <- qt((1 + confidence)/2, df) * se; statistic <- mean(active)/se
  result$se <- se; result$df <- df; result$lower <- mean(active) - half; result$upper <- mean(active) + half
  result$p_one_sided <- pt(statistic, df, lower.tail = FALSE); result$p_two_sided <- 2 * pt(-abs(statistic), df)
  result$status <- "Exploratory estimate; uncertainty from active and shared placebo profiles"
  result
}
tfl_model_cqtc_data <- function(adpc, adeg, mad = FALSE) {
  days <- if (mad) suppressWarnings(as.numeric(tfl_model_codes("profile_days", "1, 14"))) else 1
  if (any(!is.finite(days) | days < 1 | days != floor(days))) stop("Profile days must be positive integers.")
  tfl_model_columns(adeg, c("USUBJID", "SAFFL", "ANL01FL", "PARAMCD", "TRT01A", "ADY", "ATPTN", "CHG", "AVAL", "AVALU"), "C-QTc ADEG")
  tfl_model_columns(adpc, c("USUBJID", "PKFL", "PARAMCD", "ADY", "ATPTN", "ARRLT", "AVAL", "AVALU"), "C-QTc ADPC")
  eg <- adeg %>% filter(SAFFL == "Y", ANL01FL == "Y", PARAMCD == "QTCF", ADY %in% c(-1, days))
  eg$dose <- tfl_model_dose(eg$TRT01A)
  placebo <- tfl_model_setting("placebo_label", "Placebo")
  if (any((eg$TRT01A == placebo) != (eg$dose == 0))) stop("Only the specified placebo treatment may map to dose zero.")
  tfl_model_unique(eg, c("USUBJID", "ADY", "ATPTN"), "C-QTc analysis ECG")
  tfl_model_units(eg)
  if (nrow(eg) && any(!tolower(eg$AVALU) %in% c("ms", "msec", "millisecond", "milliseconds"))) stop("QTcF must be supplied in milliseconds.")
  profile <- eg %>% filter(ADY %in% days)
  if (any(!is.finite(profile$CHG) | !is.finite(profile$ATPTN))) stop("C-QTc profile CHG and nominal times must be finite; select complete analysis profiles.")
  pc <- adpc %>% filter(PKFL == "Y", PARAMCD == tfl_model_setting("pk_parameter", "CONC"), ADY %in% days)
  tfl_model_unique(pc, c("USUBJID", "ADY", "ATPTN"), "C-QTc concentrations"); tfl_model_units(pc)
  if (any(!is.finite(pc$AVAL) | pc$AVAL < 0 | !is.finite(pc$ARRLT))) stop("C-QTc concentrations must be finite and nonnegative, with finite actual times.")
  if (any((profile %>% distinct(USUBJID, TRT01A) %>% count(USUBJID))$n != 1L)) stop("C-QTc diagnostic supports one treatment per participant.")
  # Every profile must share the complete day-specific nominal grid. This avoids
  # silently treating partial polygons and mismatched placebo profiles as complete.
  for (day in days) {
    d <- profile %>% filter(ADY == day)
    grid <- sort(unique(d$ATPTN))
    if (length(grid) < 3L) stop("C-QTc day ", day, ": at least three nominal times are required.")
    counts <- d %>% count(USUBJID)
    if (any(counts$n != length(grid))) stop("C-QTc day ", day, ": incomplete nominal-time profile; supply the same prespecified grid for every participant.")
    if (n_distinct(d$USUBJID[d$TRT01A == placebo]) < 2L || n_distinct(d$USUBJID[d$dose > 0]) < 3L) stop("C-QTc day ", day, ": at least two placebo and three active participants required.")
  }
  pbo <- profile %>% filter(TRT01A == placebo) %>% group_by(ADY, ATPTN) %>% summarise(pbo = mean(CHG), pbo_variance = var(CHG)/n(), n_placebo = n(), .groups = "drop")
  pdev <- profile %>% filter(TRT01A == placebo) %>% inner_join(pbo, by = c("ADY", "ATPTN")) %>% transmute(USUBJID, ADY, ATPTN, dev = CHG - pbo)
  cq <- profile %>% filter(dose > 0) %>% transmute(USUBJID, trt = TRT01A, dose, ADY, ATPTN, CHG) %>% left_join(pbo, by = c("ADY", "ATPTN")) %>% left_join(pc %>% transmute(USUBJID, ADY, ATPTN, ARRLT, conc = AVAL), by = c("USUBJID", "ADY", "ATPTN"))
  if (any(!is.finite(cq$conc))) stop("Every active ECG profile time requires a matching selected PK concentration.")
  cq <- cq %>% mutate(ddqtcf = CHG - pbo) %>% arrange(USUBJID, ADY, ATPTN)
  for (key in split(seq_len(nrow(cq)), interaction(cq$USUBJID, cq$ADY, drop = TRUE))) {
    if (any(diff(cq$ARRLT[key]) <= 0)) stop("Actual PK times must increase strictly with nominal time within each profile.")
    if (max(cq$conc[key]) <= 0) stop("Each active C-QTc profile must have a positive concentration maximum.")
  }
  cq <- cq %>% group_by(USUBJID, ADY) %>% mutate(x = conc/max(conc)) %>% ungroup()
  list(cq = cq, pdev = pdev, baseline = eg %>% filter(ADY == -1), days = days, placebo = placebo, concentration_unit = unique(pc$AVALU))
}
tfl_model_cqtc <- function(prepared) {
  cq <- prepared$cq
  form <- toupper(tfl_model_setting("cqtc_form", "LINEAR"))
  if (!form %in% c("LINEAR", "EMAX")) stop("C-QTc form must be LINEAR or EMAX.")
  if (n_distinct(cq$conc) < if (form == "EMAX") 4L else 2L) stop("C-QTc direct-effect model has insufficient concentration variation.")
  if (form == "LINEAR") {
    fitted_model <- tfl_model_fit(function() nlme::lme(ddqtcf ~ conc, random = ~ 1 | USUBJID, data = cq, method = "REML", control = nlme::lmeControl(returnObject = FALSE)))
    coefficients <- nlme::fixef(fitted_model$fit)
  } else {
    # Positive EC50 via its logarithm. The stability check rejects a boundary or
    # implausibly weakly identified fit instead of selecting a different model.
    positive <- cq$conc[cq$conc > 0]
    concentration_scale <- median(positive)
    emax_start <- diff(range(cq$ddqtcf))
    if (!is.finite(emax_start) || emax_start <= 0) stop("Emax response has no variation.")
    fitted_model <- tfl_model_fit(function() nlme::nlme(ddqtcf ~ e0 + emax * conc/(exp(log_ec50) + conc), data = cq, fixed = e0 + emax + log_ec50 ~ 1, random = e0 ~ 1 | USUBJID, start = c(e0 = min(cq$ddqtcf), emax = emax_start, log_ec50 = log(concentration_scale)), control = nlme::nlmeControl(maxIter = 200, pnlsMaxIter = 50, msMaxIter = 200, returnObject = FALSE)))
    coefficients <- nlme::fixef(fitted_model$fit)
    ec50 <- exp(coefficients[["log_ec50"]])
    if (!is.finite(ec50) || ec50 < min(positive)/100 || ec50 > max(positive)*100) stop("Emax EC50 is outside the numerical stability range; model is not identifiable on these data.")
    coefficients <- c(coefficients[c("e0", "emax")], ec50 = ec50)
  }
  if (any(!is.finite(coefficients))) stop("Nonfinite direct-effect model coefficients.")
  cq$residual <- as.numeric(residuals(fitted_model$fit, level = 1, type = "response"))
  if (length(cq$residual) != nrow(cq) || any(!is.finite(cq$residual))) stop("Direct-effect residuals are not finite and complete.")
  baseline <- prepared$baseline
  pdev1 <- tibble(USUBJID = character(), ATPTN = numeric(), dev = numeric())
  pseudo <- tibble(USUBJID = character(), ATPTN = numeric(), pseudo = numeric())
  if (nrow(baseline)) {
    baseline <- baseline %>% filter(is.finite(AVAL)) %>% group_by(USUBJID) %>% mutate(centered = AVAL - mean(AVAL)) %>% ungroup()
    pm <- baseline %>% filter(TRT01A == prepared$placebo) %>% group_by(ATPTN) %>% summarise(pm = mean(centered), .groups = "drop")
    pdev1 <- baseline %>% filter(TRT01A == prepared$placebo) %>% inner_join(pm, by = "ATPTN") %>% transmute(USUBJID, ATPTN, dev = centered - pm)
    pseudo <- baseline %>% filter(dose > 0) %>% inner_join(pm, by = "ATPTN") %>% transmute(USUBJID, ATPTN, pseudo = centered - pm)
  }
  records <- cq %>% left_join(pseudo, by = c("USUBJID", "ATPTN")) %>% arrange(USUBJID, ADY, ARRLT)
  part <- records %>% group_by(USUBJID, trt, dose, ADY) %>% summarise(area = tfl_model_loop_area(x, residual), pseudo_area = tfl_model_loop_area(x, pseudo), tmax = ATPTN[which.max(conc)], tpeak = ATPTN[which.max(ddqtcf)], .groups = "drop")
  placebo_areas <- function(xbar, d) {
    d <- d %>% inner_join(xbar, by = "ATPTN") %>% arrange(USUBJID, ATPTN)
    d %>% group_by(USUBJID) %>% summarise(area = if (n() == nrow(xbar)) tfl_model_loop_area(xm, dev) else NA_real_, .groups = "drop") %>% pull(area)
  }
  summarize_row <- function(day, trt = NULL) {
    rc <- records %>% filter(ADY == day); participants <- part %>% filter(ADY == day)
    if (!is.null(trt)) { rc <- rc %>% filter(.data$trt == .env$trt); participants <- participants %>% filter(.data$trt == .env$trt) }
    xbar <- rc %>% group_by(ATPTN) %>% summarise(xm = mean(x), mean_dd = mean(ddqtcf), .groups = "drop")
    result <- tfl_model_area_test(participants$area, placebo_areas(xbar, prepared$pdev %>% filter(ADY == day)))
    complete_pseudo <- participants %>% filter(is.finite(pseudo_area))
    # Use the same subset's x profile for the Day -1 placebo variance term.
    pseudo_xbar <- rc %>% filter(USUBJID %in% complete_pseudo$USUBJID) %>% group_by(ATPTN) %>% summarise(xm = mean(x), .groups = "drop")
    pseudo_test <- tfl_model_area_test(complete_pseudo$pseudo_area, placebo_areas(pseudo_xbar, pdev1))
    bind_cols(tibble(profile_day = day, treatment = trt %||% "All active doses", actual_dose = if (is.null(trt)) NA_real_ else unique(rc$dose), dose_unit = tfl_model_setting("dose_unit", ""), concentration_unit = prepared$concentration_unit, model = form), result,
      tibble(individual_peak_gap_hours = median(participants$tpeak) - median(participants$tmax), mean_peak_gap_hours = xbar$ATPTN[which.max(xbar$mean_dd)] - median(participants$tmax), baseline_n = pseudo_test$n, baseline_area = pseudo_test$estimate, baseline_lower = pseudo_test$lower, baseline_upper = pseudo_test$upper, baseline_p_two_sided = pseudo_test$p_two_sided, baseline_status = pseudo_test$status, fit_status = fitted_model$status))
  }
  summary <- bind_rows(lapply(prepared$days, function(day) bind_rows(lapply(sort(unique(cq$trt[cq$ADY == day])), function(trt) summarize_row(day, trt)), summarize_row(day))))
  list(summary = summary, participants = part, coefficients = tibble(model = form, term = names(coefficients), estimate = unname(coefficients), status = fitted_model$status), records = records)
}
tfl_model_cqtc_profile <- function(prepared) {
  prepared$cq %>% group_by(trt, dose, ADY, ATPTN) %>% summarise(n = n_distinct(USUBJID), concentration = mean(conc), mean = mean(ddqtcf), se = sqrt(var(ddqtcf)/n() + first(pbo_variance)), n_placebo = first(n_placebo), .groups = "drop") %>% arrange(dose, ADY, ATPTN) %>% mutate(day = paste("Day", ADY), concentration_unit = prepared$concentration_unit)
}
