################################################################################
# TABLE     : t_ada_impact_pk  (Multiple Ascending Dose)
# TITLE     : Impact of Anti-Drug Antibody Status on Steady-State Plasma PK
#             Exposure and Accumulation by Dose Level
# POPULATION: PK Parameter + ADA-Evaluable Population (PKFL == "Y" and ADIS-
#             evaluable)
# INPUT     : ADPP (steady-state PARAMCD = CMAXSS, AUCTAU/AUCTAUSS, CMINSS, RAC*;
#             single-dose Day 1 PARAMCD = CMAX, AUCTAU for Rac context),
#             ADIS (participant-level treatment-emergent ADA status)
# NOTE      : PSEUDOCODE. Cross-classifies STEADY-STATE PK exposure parameters
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
#             ADA x exposure test. Reported PK = validated PK tool per SOP.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("MAD")                      # column = TRT01A (= dose level)

## --- participant-level treatment-emergent ADA status from ADIS (not re-derived) -
ada_status <- adam$adis %>% filter(ADAFL == "Y") %>%
  group_by(USUBJID) %>%
  summarise(ada_te = any(toupper(TEADAFL) == "Y", na.rm = TRUE), .groups = "drop") %>%
  mutate(ADA = if_else(ada_te, "ADA-positive", "ADA-negative"))

## steady-state exposure params + accumulation ratio in ADPP; active doses only
## (placebo has no active exposure / log(0) dose downstream). Rac is precomputed
## by the validated PK tool (PARAMCD = RACMAX / RACTAU); we summarise, not derive.
SS_PARAMS  <- c("CMAXSS", "AUCTAU", "CMINSS", "CTROUGH")    # steady-state exposure
RAC_PARAMS <- c("RACMAX", "RACAUC")                          # accumulation ratios (pre-derived ADPP)

## --- exposure + Rac parameters; merge ADA status onto each participant's PK params
pp <- adam$adpp %>%
  filter(PKFL == "Y", PARAMCD %in% c(SS_PARAMS, RAC_PARAMS),
         .data[[dv$trtnvar]] > 0) %>%
  inner_join(ada_status, by = "USUBJID") %>%        # PK x ADA evaluable only
  mutate(trt = .data[[dv$trtvar]], dose = .data[[dv$trtnvar]],
         pgroup = if_else(PARAMCD %in% RAC_PARAMS,
                          "Accumulation ratio", "Steady-state exposure"))

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
## reported model = validated PK tool per SOP.
dp_by_ada <- pp %>%
  filter(pgroup == "Steady-state exposure", dose > 0, AVAL > 0) %>%
  group_by(PARAMCD, PARAM, ADA) %>%
  filter(n_distinct(dose) >= 2L, n() >= 3L) %>%
  group_modify(~{
    r  <- max(.x$dose) / min(.x$dose)
    m  <- lm(log(AVAL) ~ log(dose), data = .x)
    ci <- confint(m, "log(dose)", level = 0.90)
    tibble(beta  = unname(coef(m)["log(dose)"]),
           lcl90 = ci[1], ucl90 = ci[2],
           betaL = 1 + log(0.80) / log(r),       # critical-region lower bound
           betaH = 1 + log(1.25) / log(r),       # critical-region upper bound
           within = ci[1] >= (1 + log(0.80)/log(r)) & ci[2] <= (1 + log(1.25)/log(r)))
  }) %>% ungroup()

## --- ADA shift in accumulation: Rac geo-mean ratio (ADA+ / ADA-) per dose ---
## within dose level, ratio of geometric-mean Rac for ADA-positive vs negative;
## an exploratory read of whether ADA changes day-on-day accumulation. Log scale.
rac_shift <- pp %>%
  filter(pgroup == "Accumulation ratio", AVAL > 0) %>%
  group_by(trt, PARAMCD, PARAM, ADA) %>%
  summarise(n = n_distinct(USUBJID), geomean = exp(mean(log(AVAL))), .groups = "drop") %>%
  pivot_wider(names_from = ADA, values_from = c(n, geomean)) %>%
  mutate(`Rac GMR (ADA+/ADA-)` = `geomean_ADA-positive` / `geomean_ADA-negative`)

ttl <- tfl_titles(num = "14.5.2.1", type = "Table",
   text = "Impact of Anti-Drug Antibody Status on Steady-State PK Exposure and Accumulation by Dose Level",
   pop  = "PK Parameter and ADA-Evaluable Population",
   foot = paste("Geometric mean / Geo CV% on the log scale (exp(mean(log)),",
                "100*sqrt(exp(var(log))-1)). ADA status = treatment-emergent (ADIS).",
                "Multiple ascending dose: columns = dose level x ADA status (active doses);",
                "steady-state exposure (Cmax,ss / AUCtau,ss / Cmin,ss) and accumulation",
                "ratio Rac (Day N / Day 1, precomputed by the validated PK tool).",
                "Exploratory STEADY-STATE dose-proportionality power model",
                "log(param)~log(dose) per ADA stratum; slope beta vs critical region",
                "betaL=1+log(0.80)/log(r), betaH=1+log(1.25)/log(r), r=max/min dose.",
                "Rac GMR = geo-mean accumulation-ratio ratio (ADA+ / ADA-) within dose.",
                "Subgroup n may be small -- interpret with caution. No formal ADA x",
                "exposure statistical test."))

## rtables/gt rendering; param-group blocks (steady-state exposure, accumulation
## ratio), dose-level x ADA-status columns; dose-proportionality power-model
## slopes (dp_by_ada) and Rac GMR (rac_shift) appended as footnote blocks
print(tab)
print(dp_by_ada)    # MAD: ADA-stratified steady-state dose-proportionality slope
print(rac_shift)    # MAD: ADA shift in accumulation ratio (GMR ADA+/ADA-)
