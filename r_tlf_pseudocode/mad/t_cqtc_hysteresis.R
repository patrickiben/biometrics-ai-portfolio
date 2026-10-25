################################################################################
# TABLE     : t_cqtc_hysteresis  (Multiple Ascending Dose)
# TITLE     : Assessment of Delay between Concentration and ddQTcF before the
#             C-QTc Analysis: Mean Signed Loop Area on Direct-Effect Model
#             Residuals, by Dose and Profile Day
# POPULATION: C-QTc Analysis Set (PKFL == "Y" and SAFFL == "Y"), active doses;
#             placebo participants (pooled) for the time-matched placebo mean
# INPUT     : ADEG (PARAMCD == "QTCF"; CHG on the profile days, AVAL on Day -1,
#             ADY, ATPTN), ADPC (PARAMCD == "CONC"; AVAL, ARRLT actual time from
#             the most recent dose, ADY, ATPTN)
# NOTE      : PSEUDOCODE. The prespecified hysteresis check (SAP text: see
#             cqtc_hysteresis/index.html), run separately on each full-profile
#             day (Day 1 and the steady-state day, PROFDAYS). Steps:
#             1. ddQTcF = CHG minus the time-matched placebo mean CHG on the same
#                day (placebo pooled); concentrations time-matched on day and
#                nominal time; records ordered by ACTUAL time since the most
#                recent dose (ARRLT) within each participant and day.
#             2. Fit the prespecified direct-effect model with NO time factor on
#                all active doses and profile days: ddQTcF = f(C) + b_i + e, f
#                linear, or Emax if the SAP's linearity check selects it (FORM).
#             3. r = ddQTcF - f-hat(C) - b-hat_i; x = C / the participant's Cmax
#                on that day. At steady state the path starts at the trough.
#             4. A_i = 0.5 * sum_j (x_j r_(j+1) - x_(j+1) r_j), closed path
#                (index m+1 = 1); A_i > 0 = counterclockwise = effect lags.
#             5. Every A_i shares the placebo-mean noise, so the test adds it:
#                h_k = signed area of placebo participant k's CHG minus the
#                placebo mean on that day, against the mean x of the row's
#                active participants at each nominal time. t = mean(A) / SE,
#                SE^2 = var(A)/n + var(h)/n_pbo, Welch-Satterthwaite df;
#                one- and two-sided p, and the 95% CI from the same SE and df.
#                (A one-sample sign-flip test of the A_i ignores the shared term
#                and rejects too often. Use it only if each participant's ddQTcF
#                is corrected by their own placebo period: signflip_test() in
#                cqtc_hysteresis/R/area.R.)
#             6. Report beside it: the tmax gap (median time of peak ddQTcF
#                minus median tmax; and the peak of the mean profile minus
#                median tmax) and the Day -1 pseudo-loop check (Day -1 QTcF,
#                centered and corrected the same way, paired with that day's x,
#                and tested the same way). Rows per day: each active dose, then all.
#             A significant result prompts an effect-compartment model; it does
#             not replace the C-QTc analysis. Mirrors cqtc_hysteresis/R/area.R.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("MAD")                       # TRT01A = dose level; TRT01AN = dose

PCCD     <- "CONC"     # parent analyte PARAMCD in ADPC
PROFDAYS <- c(1, 14)   # full-profile days per the SAP (Day 1 and steady state)
FORM     <- "LINEAR"   # prespecified f: "LINEAR", or "EMAX" if the SAP linearity check selects it

## ---- helpers (as in cqtc_hysteresis/R/area.R) ---------------------------------
loop_area <- function(x, y) {                     # closed-path shoelace area
  j <- c(seq_along(x)[-1], 1L)
  0.5 * sum(x * y[j] - x[j] * y)
}
pbo_t <- function(A, h) {                         # t-test of mean(A); SE adds the placebo-mean part
  va <- var(A) / length(A); vh <- var(h) / length(h); se <- sqrt(va + vh)
  df <- (va + vh)^2 / (va^2 / (length(A) - 1) + vh^2 / (length(h) - 1))   # Welch-Satterthwaite
  t0 <- mean(A) / se
  c(est = mean(A), lcl = mean(A) - qt(0.975, df) * se, ucl = mean(A) + qt(0.975, df) * se,
    p1 = pt(t0, df, lower.tail = FALSE), p2 = 2 * pt(-abs(t0), df))
}
## placebo participants' areas: deviation from the placebo mean (dev) against the mean
## x of the row's active participants at each nominal time (xm), in nominal-time order
pbo_areas <- function(xbar, pd) {
  pd %>% inner_join(xbar, by = "ATPTN") %>% arrange(USUBJID, ATPTN) %>%
    group_by(USUBJID) %>% summarise(h = loop_area(xm, dev), .groups = "drop") %>% pull(h)
}

## ---- profile days: ddQTcF with time-matched concentrations ------------------------
eg <- adam$adeg %>%
  filter(SAFFL == "Y", ANL01FL == "Y", PARAMCD == "QTCF", ADY %in% PROFDAYS, !is.na(CHG)) %>%
  transmute(USUBJID, trt = .data[[dv$trtvar]], dose = .data[[dv$trtnvar]], ADY, ATPTN, CHG)
pbo <- eg %>% filter(dose == 0) %>% group_by(ADY, ATPTN) %>% summarise(pbo = mean(CHG), .groups = "drop")
pdev <- eg %>% filter(dose == 0) %>% inner_join(pbo, by = c("ADY", "ATPTN")) %>%
  transmute(USUBJID, ADY, ATPTN, dev = CHG - pbo)  # placebo deviations from their mean, by day
pc  <- adam$adpc %>%
  filter(PKFL == "Y", PARAMCD == PCCD, ADY %in% PROFDAYS, !is.na(AVAL)) %>%
  transmute(USUBJID, ADY, ATPTN, ARRLT, conc = AVAL)
cq <- eg %>% filter(dose > 0) %>%
  inner_join(pbo, by = c("ADY", "ATPTN")) %>%
  mutate(ddqtcf = CHG - pbo) %>%
  inner_join(pc, by = c("USUBJID", "ADY", "ATPTN")) %>%
  group_by(USUBJID, ADY) %>% mutate(x = conc / max(conc)) %>% ungroup() %>%
  arrange(USUBJID, ADY, ARRLT)                    # time order within the dosing interval

## ---- Day -1: centered QTcF, corrected the same way ---------------------------------
d1 <- adam$adeg %>%
  filter(SAFFL == "Y", PARAMCD == "QTCF", ADY == -1, !is.na(AVAL)) %>%
  group_by(USUBJID) %>% mutate(qc = AVAL - mean(AVAL)) %>% ungroup() %>%
  transmute(USUBJID, dose = .data[[dv$trtnvar]], ATPTN, qc)
pqc <- d1 %>% filter(dose == 0) %>% group_by(ATPTN) %>% summarise(pqc = mean(qc), .groups = "drop")
pdev1 <- d1 %>% filter(dose == 0) %>% inner_join(pqc, by = "ATPTN") %>%
  transmute(USUBJID, ATPTN, dev = qc - pqc)
d1 <- d1 %>% filter(dose > 0) %>% inner_join(pqc, by = "ATPTN") %>%
  transmute(USUBJID, ATPTN, dm1 = qc - pqc)

## ---- prespecified direct-effect model, no time factor, all active doses and days ---
fit <- if (FORM == "LINEAR") {
  nlme::lme(ddqtcf ~ conc, random = ~ 1 | USUBJID, data = cq, method = "REML")
} else {
  nlme::nlme(ddqtcf ~ e0 + emax * conc / (ec50 + conc), data = cq,
             fixed = e0 + emax + ec50 ~ 1, random = e0 ~ 1 | USUBJID,
             start = c(e0 = 0, emax = 20, ec50 = median(cq$conc[cq$conc > 0])))   # starts per SAP
}
cq$resid <- cq$ddqtcf - fitted(fit, level = 1)    # r = ddQTcF - f-hat(C) - b-hat_i

## ---- per-participant, per-day signed areas and tmax quantities -----------------------
part <- cq %>%
  left_join(d1, by = c("USUBJID", "ATPTN")) %>%
  group_by(USUBJID, trt, dose, ADY) %>%
  summarise(A      = loop_area(x, resid),
            A_dm1  = if (all(!is.na(dm1))) loop_area(x, dm1) else NA_real_,
            tmax   = ATPTN[which.max(conc)],
            tpeak  = ATPTN[which.max(ddqtcf)],
            .groups = "drop")

## one row: d = participants, rc = their records in cq on that day
summ <- function(d, rc, label, day) {
  xbar <- rc %>% group_by(ATPTN) %>% summarise(xm = mean(x), .groups = "drop")
  pr   <- rc %>% group_by(ATPTN) %>% summarise(mdd = mean(ddqtcf), .groups = "drop")
  pdd  <- pdev %>% filter(ADY == day)
  p    <- pbo_t(d$A, pbo_areas(xbar, pdd))
  a1   <- d$A_dm1[!is.na(d$A_dm1)]
  tibble(
    `Profile day`                = paste("Day", day),
    `Dose`                       = label,
    `n`                          = as.character(n_distinct(d$USUBJID)),
    `n placebo`                  = as.character(n_distinct(pdd$USUBJID)),
    `Mean area, ms (95% CI)`     = sprintf("%.2f (%.2f, %.2f)", p[["est"]], p[["lcl"]], p[["ucl"]]),
    `p one-sided`                = sprintf("%.4f", p[["p1"]]),
    `p two-sided`                = sprintf("%.4f", p[["p2"]]),
    `tmax gap, h (individual)`   = sprintf("%.1f", median(d$tpeak) - median(d$tmax)),
    `tmax gap, h (mean profile)` = sprintf("%.1f", pr$ATPTN[which.max(pr$mdd)] - median(d$tmax)),
    `Day -1 mean area, ms (p two-sided)` =
      if (length(a1) > 1) sprintf("%.2f (%.4f)", mean(a1), pbo_t(a1, pbo_areas(xbar, pdev1))[["p2"]]) else "NE",
    `Model for f`                = if (FORM == "LINEAR") "Linear" else "Emax")
}
tab <- bind_rows(lapply(PROFDAYS, function(day) {
  pd <- part %>% filter(ADY == day); cd <- cq %>% filter(ADY == day)
  bind_rows(
    lapply(sort(unique(pd$dose)), function(dd) summ(pd %>% filter(dose == dd), cd %>% filter(dose == dd),
                                                    as.character(pd$trt[pd$dose == dd][1]), day)),
    summ(pd, cd, "All active doses", day))
}))

ttl <- tfl_titles(num = "14.3.6.5", type = "Table",
   text = "Assessment of Delay between Concentration and ddQTcF: Mean Signed Loop Area on Direct-Effect Model Residuals, by Dose and Profile Day",
   pop  = "C-QTc Analysis Set",
   foot = paste(
     "Area = signed area of each participant's closed path of (concentration / participant Cmax on that day, residual ddQTcF) in time order over the dosing interval;",
     "positive = counterclockwise = effect lags concentration. Residuals from the prespecified direct-effect model",
     "(no time factor, participant random intercept) fitted to all active doses and profile days.",
     "CI and p: t-test of the mean area whose standard error adds the variance of the time-matched placebo mean that every",
     "active participant's ddQTcF shares (each placebo participant's signed area, about the placebo mean on that day, against the",
     "active participants' mean scaled concentration profile), Welch-Satterthwaite degrees of freedom.",
     "tmax gap: median time of peak ddQTcF (individual) or time of peak mean ddQTcF (mean profile) minus median tmax; > 1 h is flagged in the SAP.",
     "Day -1: Day -1 time-matched QTcF, centered and placebo-corrected as on the profile day, paired with that day's concentrations and tested the same way; no drug, so any area reflects timing alone.",
     "NE = not evaluable. A significant result prompts an effect-compartment model; it does not replace the C-QTc analysis."))

print(tab, n = Inf)
