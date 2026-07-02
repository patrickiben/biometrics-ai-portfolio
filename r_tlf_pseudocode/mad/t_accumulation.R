################################################################################
# TABLE     : t_accumulation  (MAD - Multiple Ascending Dose)
# TITLE     : Accumulation Ratio and Attainment of Steady State by Dose Cohort
# POPULATION: PK Parameter Population (PKFL == "Y"); steady-state troughs from
#             ADPC (PK Concentration Population, PKFL == "Y")
# INPUT     : ADPP (PARAMCD = CMAX/CMAXSS, AUCLST/AUCTAU at Day 1 vs Day N) for Rac;
#             ADPC (ATPT = "Pre-dose" troughs across dosing days) for steady state
# NOTE      : PSEUDOCODE. THIS is a file that differs by design (MAD). Two parts:
#
#   (A) ACCUMULATION RATIO  Rac = geometric mean of the WITHIN-PARTICIPANT ratio
#       Day N / Day 1, paired ON THE LOG SCALE:
#           Rac = exp( mean_i [ ln(P_DayN,i) - ln(P_Day1,i) ] )
#       computed per dose cohort for Cmax (CMAXSS/CMAX) and AUC over tau
#       (AUCTAU/AUCLST). 95% CI from the SD of the paired log-differences
#       (t-distribution), back-transformed. Participants must have BOTH occasions.
#       (No accumulation -> Rac ~ 1; Rac references the dosing interval tau.)
#
#   (B) STEADY-STATE ATTAINMENT  pre-dose trough (Ctrough/Cmin) trend across
#       dosing days. Visual/numeric trend + an OPTIONAL log-linear mixed model
#       of ln(trough) on dosing day with random participant intercept; steady state
#       is supported when the 95% CI for the day slope INCLUDES 0 (no systematic
#       rise once plateau reached). Slope tested over the pre-specified plateau
#       window per SAP. Column = dose cohort (TRT01A); placebo excluded.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("MAD")                       # column = TRT01A (= dose cohort)

## ============================================================================
## PART A -- ACCUMULATION RATIO  Rac (geomean of within-participant Day N / Day 1)
## ============================================================================
## Pair single-dose (Day 1) and steady-state (Day N) parameters per participant.
## Cmax:  Day 1 = CMAX,    Day N = CMAXSS
## AUC :  Day 1 = AUCLST,  Day N = AUCTAU   (both over the dosing interval tau)
pp <- adam$adpp %>% filter(PKFL == "Y", AVAL > 0)

rac_one <- function(cd_day1, cd_dayN, label) {
  d1 <- pp %>% filter(PARAMCD == cd_day1) %>%
    transmute(USUBJID, trt = .data[[dv$trtvar]], trtn = .data[[dv$trtnvar]],
              ln_d1 = log(AVAL))
  dN <- pp %>% filter(PARAMCD == cd_dayN) %>%
    transmute(USUBJID, ln_dN = log(AVAL))
  ## paired participants only (BOTH occasions present)
  paired <- inner_join(d1, dN, by = "USUBJID") %>%
    mutate(ln_ratio = ln_dN - ln_d1)                 # log within-participant Day N / Day 1
  paired %>%
    group_by(trt, trtn) %>%
    summarise(
      n        = n(),
      mlogr    = mean(ln_ratio),
      sdlogr   = sd(ln_ratio),
      .groups  = "drop") %>%
    mutate(
      param = label,
      rac   = exp(mlogr),                                          # geometric mean ratio
      se    = sdlogr / sqrt(n),
      tcrit = qt(0.975, df = pmax(n - 1, 1)),
      lo    = exp(mlogr - tcrit * se),                            # back-transformed 95% CI
      hi    = exp(mlogr + tcrit * se))
}

rac <- bind_rows(
  rac_one("CMAX",   "CMAXSS", "Rac (Cmax)"),
  rac_one("AUCLST", "AUCTAU", "Rac (AUCtau)")) %>%
  arrange(param, trtn)

rac_tab <- rac %>% transmute(
  `PK Parameter`        = param,
  `Dose Cohort`         = trt,
  `n (paired)`          = as.character(n),
  `Rac (Geo Mean)`      = sprintf("%.2f", rac),
  `95% CI`              = sprintf("%.2f - %.2f", lo, hi))

## ============================================================================
## PART B -- STEADY-STATE ATTAINMENT (pre-dose trough trend across dosing days)
## ============================================================================
## Pre-dose troughs from ADPC: ATPT = "Pre-dose" (one per dosing day, x > 0).
trough <- adam$adpc %>%
  filter(PKFL == "Y",
         toupper(coalesce(ATPT, "")) %in% c("PRE-DOSE","PREDOSE","TROUGH","0H PRE-DOSE"),
         AVAL > 0) %>%
  transmute(USUBJID, trt = .data[[dv$trtvar]], trtn = .data[[dv$trtnvar]],
            day = ADY, ln_tr = log(AVAL))

## --- descriptive trough trend per cohort x dosing day (geometric) ----------
trough_desc <- trough %>%
  group_by(trt, trtn, day) %>%
  summarise(n        = n(),
            geomean  = exp(mean(ln_tr)),
            geocv    = 100 * sqrt(exp(stats::var(ln_tr)) - 1),
            .groups  = "drop") %>%
  arrange(trtn, day) %>%
  transmute(`Dose Cohort` = trt, `Dosing Day` = day,
            `n` = as.character(n),
            `Trough Geo Mean` = sprintf("%.3g", geomean),
            `Trough Geo CV%`  = sprintf("%.1f", geocv))

## --- OPTIONAL log-linear mixed model: ln(trough) ~ day + (1|participant) -------
## Steady state supported when the 95% CI for the DAY slope includes 0 (no
## systematic rise once plateau reached). Fit within the pre-specified plateau
## window per SAP, per cohort. (lme4::lmer on the log scale.)
ss_slope_one <- function(d) {
  d <- d %>% mutate(subj = factor(USUBJID))
  if (n_distinct(d$day) < 2 || n_distinct(d$subj) < 2)
    return(tibble(slope = NA_real_, lo = NA_real_, hi = NA_real_, includes0 = NA))
  m  <- lmer(ln_tr ~ day + (1 | subj), data = d)
  est <- fixef(m)[["day"]]
  ci  <- tryCatch(confint(m, parm = "day", method = "Wald", level = 0.95),
                  error = function(e) matrix(c(NA, NA), nrow = 1))
  lo  <- ci[1, 1]; hi <- ci[1, 2]
  tibble(slope = est, lo = lo, hi = hi,
         includes0 = !is.na(lo) & !is.na(hi) & lo <= 0 & hi >= 0)
}
ss_slope <- trough %>%
  group_by(trt, trtn) %>%
  group_modify(~ ss_slope_one(.x)) %>%
  ungroup() %>%
  arrange(trtn) %>%
  transmute(`Dose Cohort` = trt,
            `Trough Slope (ln/day)` = sprintf("%.4f", slope),
            `95% CI (slope)`        = sprintf("%.4f - %.4f", lo, hi),
            `Steady State (CI incl. 0)` = if_else(includes0, "Yes", "No",
                                                  missing = "Not estimable"))

ttl <- tfl_titles(num = "14.4.4.1", type = "Table",
   text = "Accumulation Ratio and Attainment of Steady State by Dose Cohort",
   pop  = "Pharmacokinetic Parameter / Concentration Population",
   foot = paste(
     "Rac = geometric mean of within-participant Day N / Day 1 paired on the log scale;",
     "Rac = exp(mean[ln(P_DayN) - ln(P_Day1)]); 95% CI from SD of paired log-differences",
     "(t-dist), back-transformed. Paired participants only (both occasions).",
     "Steady state: pre-dose trough trend across dosing days; optional log-linear",
     "mixed model ln(trough) ~ day + (1|participant); steady state supported when the",
     "95% CI for the day slope includes 0 over the plateau window per SAP.",
     "Column = dose cohort (TRT01A); placebo excluded."))

## render three blocks: (A) Rac table, (B) trough-trend descriptive, (B) slope CI
print(rac_tab)
print(trough_desc)
print(ss_slope)
