################################################################################
# TABLE     : t_pd_summary  (Multiple Ascending Dose)
# TITLE     : Summary of Pharmacodynamic / Biomarker Endpoints by Dose Level,
#             Day and Visit
# POPULATION: PD-Evaluable Population (PDFL == "Y")
# INPUT     : ADPD (PARAMCD = PD biomarker codes; AVAL, CHG, PCHG, BASE,
#             AVISIT/AVISITN, ADY, ATPT/ATPTN)
# NOTE      : PSEUDOCODE. Continuous descriptive stats by DOSE LEVEL x
#             treatment-day x visit: n, Mean (SD), Median, Min-Max for AVAL, CHG
#             and %CHG. MAD = parallel cohorts, REPEATED dosing, one dose level
#             per participant -> column = dv$trtvar (TRT01A = dose level); placebo
#             often pooled across cohorts. Repeated dosing -> the PD time course
#             spans multiple dosing DAYS, so a PD steady-state read is meaningful:
#             the pre-dose (trough) PD value is tracked across days, and an
#             optional log-linear trough-vs-day slope (lmer, 95% CI incl. 0) flags
#             whether the PD effect has plateaued. Per-DAY/per-VISIT denominators
#             come from a period-/visit-bearing source (ADPD: PD-evaluable
#             participants with a value), NEVER one-row-per-participant ADSL. An optional
#             dose-response of a steady-state PD metric (e.g. Day N peak/trough
#             %inhibition) is shown via a log-log power model. Descriptive,
#             hypothesis-generating only; reported numbers come from the validated
#             PK/PD tool per SOP.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("MAD")                      # column = TRT01A (= dose level)

## one PD parameter per run (parameterize PARAMCD; loop/purrr in production)
PDCD <- "INHIB"                                # e.g. target % inhibition / biomarker
pd <- adam$adpd %>%
  filter(PDFL == "Y", PARAMCD == PDCD) %>%
  mutate(visit = factor(AVISIT, levels = unique(AVISIT[order(AVISITN)])))

by <- c(dv$trtvar, "PARAM", "visit")

## --- per-visit denominators from a period-/visit-bearing source (ADPD) ------
## participants PD-evaluable WITH a value at each dose level x visit (NOT ADSL)
denom_v <- pd %>%
  filter(!is.na(AVAL)) %>%
  group_by(trt = .data[[dv$trtvar]], visit) %>%
  summarise(N = n_distinct(USUBJID), .groups = "drop")

## --- descriptive stats for AVAL, CHG, %CHG ---------------------------------
stat_block <- function(var, label, dp = 2L) {
  descstat(pd, var = var, by = by, dp = dp) %>%
    transmute(trt = .data[[dv$trtvar]], PARAM, visit, measure = label,
              `n`         = as.character(n),
              `Mean (SD)` = paste(c_mean, c_sd),
              `Median`    = c_median,
              `Min, Max`  = c_minmax) %>%
    pivot_longer(c(`n`,`Mean (SD)`,`Median`,`Min, Max`),
                 names_to = "stat", values_to = "value")
}

body <- bind_rows(
  stat_block("AVAL", "Observed value",        2L),
  stat_block("CHG",  "Change from baseline",  2L),
  stat_block("PCHG", "% change from baseline",1L))

## --- header N= per dose level x visit (from ADPD denom, not ADSL) -----------
hdr <- denom_v %>% mutate(coln = sprintf("%s (N=%d)", trt, N))

## --- stack: measure/stat rows x dose-visit columns -------------------------
tab <- body %>%
  unite("colkey", trt, visit, sep = " | ", remove = FALSE) %>%
  select(PARAM, measure, stat, colkey, value) %>%
  pivot_wider(names_from = colkey, values_from = value)

## --- MAD-SPECIFIC: PD steady-state read on the PRE-DOSE (trough) value ------
## With repeated dosing the trough PD value across dosing days shows whether the
## effect has plateaued. Identify pre-dose records (ATPTN <= 0 or a trough flag),
## summarise the trough by day, then fit a log-linear trough-vs-day slope per
## active dose level (lmer with participant random intercept). A 95% CI that INCLUDES
## 0 supports PD steady state (no further day-on-day change). Active arms only
## (placebo trough is uninformative for a plateau read). Descriptive support.
trough <- pd %>%
  filter(!is.na(AVAL), .data[[dv$trtnvar]] > 0,
         (!is.na(ATPTN) & ATPTN <= 0) | toupper(coalesce(ATPT, "")) == "PRE-DOSE")

trough_by_day <- trough %>%
  group_by(trt = .data[[dv$trtvar]], ADY) %>%
  summarise(n = n_distinct(USUBJID),
            geomean = if (all(AVAL > 0)) exp(mean(log(AVAL))) else NA_real_,
            mean = mean(AVAL, na.rm = TRUE), .groups = "drop") %>%
  arrange(trt, ADY)

## per-active-dose log-linear trough slope vs day (mixed model; CI incl. 0 = SS)
ss_slope <- trough %>%
  filter(AVAL > 0, ADY > 0) %>%
  group_by(trt = .data[[dv$trtvar]]) %>%
  filter(n_distinct(ADY) >= 2L, n_distinct(USUBJID) >= 3L) %>%
  group_modify(~{
    m  <- tryCatch(lme4::lmer(log(AVAL) ~ ADY + (1 | USUBJID), data = .x),
                   error = function(e) NULL)
    if (is.null(m)) return(tibble(slope = NA_real_, lcl95 = NA_real_,
                                  ucl95 = NA_real_, ss_attained = NA))
    est <- summary(m)$coefficients["ADY", "Estimate"]
    ci  <- tryCatch(confint(m, parm = "ADY", method = "Wald", level = 0.95),
                    error = function(e) matrix(c(NA, NA), 1))
    tibble(slope = est, lcl95 = ci[1], ucl95 = ci[2],
           ss_attained = !is.na(ci[1]) && ci[1] <= 0 && ci[2] >= 0)  # CI includes 0
  }) %>% ungroup()

## --- OPTIONAL dose-response of a STEADY-STATE PD metric (power model) -------
## Pair the PD summary with a dose-response read of a per-participant steady-state
## metric (e.g. last-day peak / trough %inhibition). Drop placebo (log(0) dose)
## and non-positive metric; mirror the dose-proportionality power model on active
## arms only. Descriptive support; the reported PD/dose model comes from the
## validated PK/PD tool per SOP.
ss_day <- suppressWarnings(max(pd$ADY[pd[[dv$trtnvar]] > 0], na.rm = TRUE))
metric_subj <- pd %>%
  filter(!is.na(AVAL), .data[[dv$trtnvar]] > 0) %>%
  group_by(USUBJID, dose = .data[[dv$trtnvar]]) %>%
  summarise(metric = max(AVAL, na.rm = TRUE), .groups = "drop") %>%   # peak per participant
  filter(dose > 0, metric > 0)

dr_fit <- if (n_distinct(metric_subj$dose) >= 2L && nrow(metric_subj) >= 3L) {
  m <- lm(log(metric) ~ log(dose), data = metric_subj)
  ci <- confint(m, "log(dose)", level = 0.90)
  tibble(beta = unname(coef(m)["log(dose)"]), lcl90 = ci[1], ucl90 = ci[2])
} else tibble(beta = NA_real_, lcl90 = NA_real_, ucl90 = NA_real_)

ttl <- tfl_titles(num = "14.4.6.1", type = "Table",
   text = "Summary of Pharmacodynamic Endpoints by Dose Level, Day and Visit",
   pop  = "Pharmacodynamic-Evaluable Population",
   foot = paste("Descriptive only; no formal between-cohort test at this level.",
                "Per-visit N from PD-evaluable participants with a value (ADPD), not ADSL.",
                "Multiple ascending dose: columns = dose level (placebo pooled);",
                "PD time course spans multiple dosing days. CHG/%CHG relative to ADaM",
                "BASE. Parameter:", PDCD,
                "PD steady-state read = log-linear pre-dose (trough) value vs day per",
                "active dose (lmer, participant random intercept); 95% CI of the day slope",
                "that INCLUDES 0 supports a PD plateau.",
                sprintf("Optional log-log PD/dose slope (active arms) = %.3f (90%% CI %.3f, %.3f).",
                        dr_fit$beta, dr_fit$lcl90, dr_fit$ucl90)))

## rtables layout: measure (block) -> statistic rows x dose-level x visit columns
lyt <- basic_table(title = ttl$titles[3], main_footer = ttl$footnotes) %>%
  split_rows_by("measure", page_by = FALSE) %>%
  analyze("stat", afun = function(x) in_rows(.list = as.list(x)))
# tbl <- build_table(lyt, tab)        ## or gt::gt(tab)
print(tab)
print(trough_by_day)        # MAD: pre-dose (trough) PD by day
print(ss_slope)             # MAD: PD steady-state slope vs day (95% CI incl. 0)
