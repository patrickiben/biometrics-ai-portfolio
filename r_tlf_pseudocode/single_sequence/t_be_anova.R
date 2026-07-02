################################################################################
# TABLE     : t_be_anova  (Single-/fixed-sequence DDI)
# TITLE     : Statistical Comparison of Victim-Drug PK Exposure
#             (Test Period vs Reference Period) -- Geometric Mean Ratios and
#             90% Confidence Intervals
# POPULATION: PK Parameter Population (PKFL == "Y")
# INPUT     : ADPP (PARAMCD = CMAX, AUCLST, AUCIFO)
# NOTE      : PSEUDOCODE. THIS is the file that differs by design. Single-/fixed-
#             sequence DDI: Period 1 = victim alone (reference), Period 2 = victim
#             + perpetrator (test). Because the order is FIXED (no randomized
#             sequence), the model has NO sequence term -- mixed model on
#             ln-transformed exposure with fixed PERIOD effect and random participant:
#                 ln(parameter) ~ period + (1 | participant)
#             The ratio is Test PERIOD vs Reference PERIOD (the DDI ratio):
#             GMR = exp(LSM diff); 90% CI = exp(diff +/- t*SE) via emmeans
#             (level = 0.90). Report against the 80-125% no-effect bounds (the
#             absence of a sequence term means period and any time-trend are
#             confounded -- caveat in the footnote; period effect screened in
#             t_pk_param_by_period.R). Compare with crossover/t_be_anova.R, which
#             DOES include sequence + period + treatment.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SINGLESEQ")                 # period via dv$byperiod; NO sequence

## --- ln-transformed exposure, period as the comparison factor -------------
## Reference = Period 1 (victim alone); Test = Period 2 (victim + perpetrator).
## relevel so the contrast is Test - Reference (DDI direction). Map APERIODC
## labels to the canonical Reference/Test order; adjust labels to the study SAP.
pp <- adam$adpp %>%
  filter(PKFL == "Y", PARAMCD %in% c("CMAX","AUCLST","AUCIFO"), AVAL > 0) %>%
  mutate(lnval = log(AVAL),
         subj  = factor(USUBJID),
         ## reference period from the fixed-sequence design = victim alone
         per   = relevel(factor(.data[[dv$byperiod[2]]]), ref = "Reference"))

be_one <- function(param) {
  d <- pp %>% filter(PARAMCD == param)
  ## mixed model on the log scale: fixed PERIOD only, random participant.
  ## NO sequence term (single-/fixed-sequence design).
  m  <- lmer(lnval ~ per + (1 | subj), data = d)
  ## Test period vs Reference period contrast of LS-means, 90% CI, back-transformed
  em <- emmeans(m, ~ per)
  ct <- contrast(em, method = list("Test - Reference" = c(-1, 1)))  # order per factor levels
  ci <- confint(ct, level = 0.90)
  intra <- sigma(m)^2                                # residual var (log scale)
  tibble(
    param    = param,
    gmr      = sprintf("%.2f", 100 * exp(ci$estimate)),
    ci       = sprintf("%.2f - %.2f", 100 * exp(ci$lower.CL), 100 * exp(ci$upper.CL)),
    within   = if_else(100*exp(ci$lower.CL) >= 80 & 100*exp(ci$upper.CL) <= 125, "Yes", "No"),
    intra_cv = sprintf("%.1f", 100 * sqrt(exp(intra) - 1)))
}

be <- map_dfr(c("CMAX","AUCLST","AUCIFO"), be_one)

ttl <- tfl_titles(num = "14.4.3.1", type = "Table",
   text = "Geometric Mean Ratios and 90% Confidence Intervals: Test Period vs Reference Period",
   pop  = "Pharmacokinetic Parameter Population",
   foot = paste("Mixed model: ln(parameter) ~ period + (1|participant); NO sequence term",
                "(fixed-sequence DDI design). GMR = exp(LS-mean difference) of Test period",
                "(victim + perpetrator) vs Reference period (victim alone). 90% CI back-transformed.",
                "Assessed against the 80-125% no-interaction interval. Because dosing order is fixed,",
                "period and any time trend are confounded; period effect screened in t_pk_param_by_period.R."))

tab <- be %>% transmute(`PK Parameter` = param, `GMR (Test/Ref) %` = gmr,
                        `90% CI (%)` = ci, `Within 80-125%` = within, `Intra-participant CV%` = intra_cv)
print(tab)
