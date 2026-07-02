################################################################################
# TABLE     : t_ada_impact_pk  (Single Ascending Dose)
# TITLE     : Impact of Anti-Drug Antibody Status on Plasma PK Exposure by Dose
#             Level
# POPULATION: PK Parameter + ADA-Evaluable Population (PKFL == "Y" and ADIS-
#             evaluable)
# INPUT     : ADPP (PARAMCD = CMAX, AUCLST, AUCIFO, ...), ADIS (participant-level
#             treatment-emergent ADA status)
# NOTE      : PSEUDOCODE. Cross-classifies PK exposure parameters by DOSE LEVEL
#             and treatment-emergent ADA status (ADA-positive vs ADA-negative).
#             ADA status flag = ADAEMFL from ADIS (identical variable to the SAS
#             twin). Reports the SAME descriptive statistic set as SAS: arithmetic
#             n / Mean / SD / CV% AND geometric Geo Mean / Geo CV% (on the LOG
#             scale: exp(mean(log)), 100*sqrt(exp(var(log))-1) -- never
#             exp(mean(raw))) / Median / Min, Max. Tmax (if present) = Median
#             (Min, Max) only. DESCRIPTIVE subgroup comparison only -- NO
#             inferential model (kept parallel to SAS; no ADA-stratified power
#             model). SAD = parallel cohorts, one dose per participant -> column =
#             dv$trtvar (TRT01A = dose level; placebo carries no active exposure).
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SAD")                      # column = TRT01A (= dose level)

## --- participant-level treatment-emergent ADA status from ADIS (not re-derived) -
## ADAEMFL = treatment-emergent ADA flag (same ADIS variable as the SAS twin)
ada_status <- adam$adis %>% filter(ADAFL == "Y") %>%
  group_by(USUBJID) %>%
  summarise(ada_te = any(toupper(ADAEMFL) == "Y", na.rm = TRUE), .groups = "drop") %>%
  mutate(ADA = if_else(ada_te, "ADA-positive", "ADA-negative"))

## --- exposure parameters; merge ADA status onto each participant's PK params ----
## active doses only (placebo has no active exposure)
pp <- adam$adpp %>%
  filter(PKFL == "Y", PARAMCD %in% c("CMAX","AUCLST","AUCIFO"), .data[[dv$trtnvar]] > 0) %>%
  inner_join(ada_status, by = "USUBJID") %>%        # PK x ADA evaluable only
  mutate(trt = .data[[dv$trtvar]], dose = .data[[dv$trtnvar]])

by <- c("trt", "PARAMCD", "PARAM", "ADA")

## --- full PK statistic set (arithmetic + geometric) on each dose x ADA cell ----
## pkstats() returns n, mean, sd, cv (arithmetic) and geomean, geocv (log scale),
## plus median/min/max -- the same block the SAS PROC MEANS step builds.
sx <- pkstats(pp, var = "AVAL", by = by) %>%
  transmute(trt, PARAM, ADA,
            `n`          = as.character(n),
            `Mean (SD)`  = paste0(sprintf("%.3g", mean), " (", sprintf("%.3g", sd), ")"),
            `CV%`        = sprintf("%.1f", cv),
            `Geo Mean`   = sprintf("%.3g", geomean),
            `Geo CV%`    = sprintf("%.1f", geocv),
            `Median`     = sprintf("%.3g", median),
            `Min, Max`   = sprintf("%.3g, %.3g", min, max)) %>%
  pivot_longer(c(`n`,`Mean (SD)`,`CV%`,`Geo Mean`,`Geo CV%`,`Median`,`Min, Max`),
               names_to = "stat", values_to = "value")

## --- layout: parameter/stat rows x (dose level | ADA status) columns -------
tab <- sx %>%
  unite("colkey", trt, ADA, sep = " | ", remove = FALSE) %>%
  select(PARAM, stat, colkey, value) %>%
  pivot_wider(names_from = colkey, values_from = value)

ttl <- tfl_titles(num = "14.5.2.1", type = "Table",
   text = "Impact of Anti-Drug Antibody Status on Plasma PK Exposure by Dose Level",
   pop  = "PK Parameter and ADA-Evaluable Population",
   foot = paste("Single-dose exposure parameters summarized by ADA status (positive/negative)",
                "within each dose level. CV% arithmetic; Geo CV% = 100*sqrt(exp(var(log))-1).",
                "ADA status = treatment-emergent (ADIS ADAEMFL). Descriptive subgroup comparison;",
                "SAD: single dose, no accumulation. No formal ADA x exposure statistical test."))

## rtables/gt rendering; parameter blocks, dose-level x ADA-status columns
print(tab)
