################################################################################
# TABLE     : t_pd_summary  (Crossover - 2x2 or Williams)
# TITLE     : Summary of Pharmacodynamic Biomarker by Treatment, Period and
#             Nominal Time
# POPULATION: Pharmacodynamic Population (PDFL == "Y" on ADPD)
# INPUT     : ADPD (PARAMCD = PD biomarker, AVAL; AVISIT/ATPT; APERIOD; TRTA)
# NOTE      : PSEUDOCODE. Within-participant crossover -> summarise by TRTA (the
#             actual treatment received in each period). n, Mean (SD), CV%,
#             Median, Min, Max per treatment x nominal time. Crossover safety/PD
#             denominators are PER-PERIOD and PD-evaluable, so N comes from ADPD
#             (participants with a PD record per APERIOD), NEVER from one-row ADSL.
#             Optional secondary by-period column (dv$byperiod) for carry-over
#             inspection. Biomarker summarised on the reported (arithmetic) scale
#             unless the SAP designates log -> then mirror pkstats() geo logic.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("CROSSOVER")                 # TRTA + APERIOD + TRTSEQP

## --- PD-evaluable analysis set, one biomarker (parameterize PARAMCD) --------
PARAM_CD <- "PDMARKER"                          # e.g. effect biomarker, % inhibition
pd <- adam$adpd %>%
  filter(PDFL == "Y", PARAMCD == PARAM_CD) %>%
  mutate(trt = .data[[dv$trtvar]])              # column = actual treatment in period

## --- per-PERIOD, per-treatment N from a period-bearing source (ADPD) --------
## crossover: each participant contributes to each treatment they received; the
## column denominator is distinct PD-evaluable participants PER treatment, taken
## from ADPD itself (NOT ADSL, which is one row/participant and has no period).
denom <- pd %>%
  group_by(trt) %>%
  summarise(N = n_distinct(USUBJID), .groups = "drop") %>%
  bind_rows(tibble(trt = "Total", N = n_distinct(pd$USUBJID))) %>%
  rename(!!dv$trtvar := trt)

## --- descriptive stats by treatment x nominal time (post-baseline AVAL) -----
by  <- c(dv$trtvar, "AVISITN", "AVISIT", "ATPTN", "ATPT")
sm  <- descstat(pd, var = "AVAL", by = by, dp = 1L) %>%
  transmute(across(all_of(by)),
            stat_block = sprintf(
              "n=%d  %s %s  CV%%=%.1f  Med %s  Min,Max %s",
              n, c_mean, c_sd, 100 * sd / mean, c_median, c_minmax))

## --- assemble: rows = time within treatment; one stat block cell ------------
## rtables layout: split columns by treatment, split rows by nominal time,
## analyze() the AVAL stats (n / Mean (SD) / CV% / Median / Min, Max).
lyt <- basic_table(title = NULL) %>%
  split_cols_by(dv$trtvar) %>%
  split_rows_by("AVISIT", split_label = "Visit") %>%
  split_rows_by("ATPT",   split_label = "Nominal Time") %>%
  analyze("AVAL", afun = function(x) {
    in_rows(
      "n"           = rcell(sum(!is.na(x)),                    format = "xx"),
      "Mean (SD)"   = rcell(c(mean(x, na.rm = TRUE), sd(x, na.rm = TRUE)), format = "xx.x (xx.xx)"),
      "CV%"         = rcell(100 * sd(x, na.rm = TRUE) / mean(x, na.rm = TRUE), format = "xx.x"),
      "Median"      = rcell(median(x, na.rm = TRUE),           format = "xx.x"),
      "Min, Max"    = rcell(c(min(x, na.rm = TRUE), max(x, na.rm = TRUE)), format = "xx.x, xx.x"))
  })

ttl <- tfl_titles(num = "14.2.6.1", type = "Table",
   text = sprintf("Summary of Pharmacodynamic Biomarker (%s) by Treatment and Nominal Time", PARAM_CD),
   pop  = "Pharmacodynamic Population",
   foot = paste("Within-participant crossover: column = actual treatment received in each period (TRTA).",
                "N = PD-evaluable participants per treatment from ADPD (per-period source, not ADSL).",
                "Geometric statistics used only if the SAP designates a log-scale biomarker."))

tab <- build_table(lyt, pd, col_counts = setNames(denom$N, denom[[dv$trtvar]]))
## main_title(tab) <- ttl$titles ; subtitles/footnotes per house banner
print(tab)
print(sm)
