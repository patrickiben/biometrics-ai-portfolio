################################################################################
# TABLE     : t_ada_impact_pk  (Multiple Ascending Dose)
# TITLE     : Impact of Anti-Drug Antibody Status on Steady-State Plasma PK
#             Exposure and Accumulation by Dose Level
# POPULATION: PK Parameter + ADA-Evaluable Population (PKFL == "Y" and ADIS-
#             evaluable)
# INPUT     : ADPP (steady-state PARAMCD = CMAXSS, AUCTAU/AUCTAUSS, CMINSS, RAC*;
#             single-dose Day 1 PARAMCD = CMAX, AUCTAU for Rac context),
#             ADIS (participant-level treatment-emergent ADA status)
# NOTE      : ANALYSIS TEMPLATE. Cross-classifies STEADY-STATE PK exposure parameters
#             and the ACCUMULATION RATIO by DOSE LEVEL and treatment-emergent ADA
#             status (ADA-positive vs ADA-negative). Geometric stats ON THE LOG
#             scale via pkstats() (geomean = exp(mean(log)), geo CV% =
#             100*sqrt(exp(var(log))-1)) -- never exp(mean(raw)). MAD = parallel
#             cohorts, REPEATED dosing, one dose level per participant -> column =
#             dv$trtvar (TRT01A = dose level; placebo carries no active exposure).
#             The MAD-relevant questions are whether ADA (1) lowers steady-state
#             exposure (Cmax,ss / AUCtau,ss / Cmin,ss) and (2) perturbs the
#             accumulation ratio Rac (Day N / Day 1). Because exposure rises
#             across cohorts, an ADA shift is read WITHIN dose level; an
#             exploratory ADA-stratified STEADY-STATE dose-proportionality power
#             model (slope beta with 90% CI vs the 0.80/1.25 critical region)
#             shows whether the steady-state exposure-dose slope is perturbed by
#             ADA. Descriptive only (subgroup n typically small); no formal
#             ADA x exposure test. Reported PK = validated PK tool per the study's SOPs.
################################################################################
source("../00_setup_helpers.R")
source("../01_analysis_models.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("MAD")                      # column = TRT01A (= dose level)

## --- participant-level treatment-emergent ADA status from ADIS (not re-derived) -
ada_status <- adam$adis %>% filter(ADAFL == "Y") %>%
  group_by(USUBJID) %>%
  summarise(ada_te = flag_any(TEADAFL), .groups = "drop") %>%
  mutate(ADA = if_else(ada_te, "ADA-positive", "ADA-negative", missing = "Unknown"))

## steady-state exposure params + accumulation ratio in ADPP; active doses only
## (placebo has no active exposure / log(0) dose downstream). Rac is precomputed
## by the validated PK tool (PARAMCD = RACMAX / RACTAU); we summarise, not derive.
SS_PARAMS  <- tfl_model_codes("mad_pk_parameters", "CMAXSS, AUCTAU")    # steady-state exposure
RAC_PARAMS <- tfl_model_codes("ada_rac_parameters", "RACMAX, RACAUC")                          # accumulation ratios (pre-derived ADPP)

## --- exposure + Rac parameters; merge ADA status onto each participant's PK params
pp <- check_analysis_units(adam$adpp) %>%
  filter(PKFL == "Y", PARAMCD %in% c(SS_PARAMS, RAC_PARAMS), ADY == tfl_settings("analysis_day", 14)) %>%
  inner_join(ada_status, by = "USUBJID") %>%        # PK x ADA evaluable only
  mutate(trt = .data[[dv$trtvar]], dose = tfl_model_dose(.data[[dv$trtvar]]),
         pgroup = if_else(PARAMCD %in% RAC_PARAMS,
                          "Accumulation ratio", "Steady-state exposure")) %>% filter(dose > 0)
tfl_model_units(pp)

by <- c("pgroup", "trt", "PARAMCD", "PARAM", "ADA")

## --- geometric exposure / Rac stats on the LOG scale (pkstats) -------------
## Rac is a ratio of positive quantities -> geometric summary is appropriate
## (same log-scale treatment as exposure); pkstats() filters AVAL > 0.
gx <- pkstats(pp, var = "AVAL", by = by) %>%
  transmute(pgroup, trt, PARAM, ADA,
            `n`         = as.character(n),
            `Geo Mean`  = sprintf("%.3g", geomean),
            `Geo CV%`   = sprintf("%.1f", geocv),
            `Median`    = sprintf("%.3g", median),
            `Min, Max`  = sprintf("%.3g, %.3g", min, max)) %>%
  pivot_longer(c(`n`,`Geo Mean`,`Geo CV%`,`Median`,`Min, Max`),
               names_to = "stat", values_to = "value")

## --- layout: param-group/parameter/stat rows x (dose level | ADA) columns ---
tab <- gx %>%
  unite("colkey", trt, ADA, sep = " | ", remove = FALSE) %>%
  select(pgroup, PARAM, stat, colkey, value) %>%
  pivot_wider(names_from = colkey, values_from = value)

## --- EXPLORATORY ADA-stratified STEADY-STATE dose-proportionality -----------
## MAD dose-proportionality is assessed AT STEADY STATE; run per ADA stratum on
## the steady-state exposure params only (not on Rac): log(param) ~ log(dose).
## Report slope beta + 90% CI vs the critical region betaL/betaH from the dose
## ratio r = max/min dose (0.80/1.25 acceptance bounds). Flags whether ADA
## perturbs the steady-state exposure-dose relationship. Descriptive support;
## reported model = validated PK tool per the study's SOPs.
dp_by_ada <- pp %>% filter(pgroup == "Steady-state exposure") %>%
  group_by(PARAMCD, PARAM, ADA) %>%
  group_modify(~ tfl_model_power(transmute(.x, USUBJID, dose, value=AVAL),
    confidence=tfl_model_confidence("dose_confidence", .90), bounds=tfl_model_bounds("dose"))) %>% ungroup()

## --- ADA shift in accumulation: Rac geo-mean ratio (ADA+ / ADA-) per dose ---
## within dose level, ratio of geometric-mean Rac for ADA-positive vs negative;
## an exploratory read of whether ADA changes day-on-day accumulation. Log scale.
rac_shift <- pp %>%
  filter(pgroup == "Accumulation ratio", AVAL > 0) %>%
  group_by(trt, PARAMCD, PARAM, ADA) %>%
  summarise(n = n_distinct(USUBJID), geomean = exp(mean(log(AVAL))), .groups = "drop") %>%
  mutate(ADA=factor(ADA, levels=c("ADA-positive","ADA-negative","Unknown"))) %>%
  pivot_wider(names_from = ADA, values_from = c(n, geomean), names_expand=TRUE) %>%
  mutate(`Rac GMR (ADA+/ADA-)` = `geomean_ADA-positive` / `geomean_ADA-negative`)

ttl <- tfl_titles(num="14.5.2.1", text="ADA Status and Configured Final-Day PK by Dose Level", pop="PK Parameter and ADA-Evaluable Population",
  foot=paste("Descriptive subgroup comparisons; no formal ADA-by-exposure test. Final analysis day:",tfl_model_number("analysis_day",14),
    ". Dose unit:",tfl_model_setting("dose_unit", ""),". Power-model confidence:",tfl_model_confidence("dose_confidence",.90),
    "; bounds:",paste(tfl_model_bounds("dose"),collapse=" / "),
    ". Accumulation ratios use supplied ADPP codes:",paste(RAC_PARAMS,collapse=", "),". Unknown ADA flags remain unknown."))
print(tab)
print(dp_by_ada)
print(rac_shift)
