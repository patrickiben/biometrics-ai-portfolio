################################################################################
# TABLE     : t_be_anova  (Crossover - 2x2 or Williams)
# TITLE     : Statistical Comparison of PK Exposure (Test vs Reference)
#             Geometric Mean Ratios and 90% Confidence Intervals
# POPULATION: PK Parameter Population (PKFL == "Y")
# INPUT     : ADPP (PARAMCD = CMAX, AUCLST, AUCIFO)
# NOTE      : PSEUDOCODE. THIS is the file that differs by design. Mixed model on
#             ln-transformed exposure with fixed effects sequence, period,
#             treatment and random participant(sequence). GMR = exp(LSM diff);
#             90% CI = exp(diff +/- t*SE) via emmeans (level = 0.90). BE if CI
#             within 80-125%. Single-/fixed-sequence variant: drop SEQUENCE,
#             ratio vs the reference PERIOD (see single_sequence/t_be_anova.R).
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("CROSSOVER")                 # TRTA + APERIOD + TRTSEQP

pp <- adam$adpp %>%
  filter(PKFL == "Y", PARAMCD %in% c("CMAX","AUCLST","AUCIFO"), AVAL > 0) %>%
  mutate(lnval = log(AVAL),
         subj  = factor(USUBJID),
         trt   = relevel(factor(TRTA), ref = "Reference"),   # Test vs Reference
         seq   = factor(TRTSEQP),
         per   = factor(APERIOD))

be_one <- function(param) {
  d <- pp %>% filter(PARAMCD == param)
  ## mixed model on the log scale: fixed seq + per + trt, random participant(seq)
  m  <- lmer(lnval ~ seq + per + trt + (1 | subj), data = d)
  ## Test vs Reference contrast of LS-means, 90% CI, back-transformed
  em <- emmeans(m, ~ trt)
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
   text = "Geometric Mean Ratios and 90% Confidence Intervals: Test vs Reference",
   pop  = "Pharmacokinetic Parameter Population",
   foot = "Mixed model: ln(parameter) ~ sequence + period + treatment + (1|participant). GMR = exp(LS-mean difference). 90% CI back-transformed. Reference = designated reference treatment.")

tab <- be %>% transmute(`PK Parameter` = param, `GMR (Test/Ref) %` = gmr,
                        `90% CI (%)` = ci, `Within 80-125%` = within, `Intra-participant CV%` = intra_cv)
print(tab)
