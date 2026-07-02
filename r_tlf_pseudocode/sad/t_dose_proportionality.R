################################################################################
# TABLE     : t_dose_proportionality  (SAD - Single Ascending Dose)
# TITLE     : Assessment of Dose Proportionality of PK Exposure (Power Model)
#             Slope (beta) and 90% Confidence Interval
# POPULATION: PK Parameter Population (PKFL == "Y")
# INPUT     : ADPP (PARAMCD = CMAX, AUCLST, AUCIFO) + dose (ADEX / ADPP dose var)
# NOTE      : PSEUDOCODE. THIS is the file that differs by design (SAD). Power
#             model on the LOG scale: log(parameter) ~ log(dose), so
#             parameter = a * dose^beta. beta = slope. Dose proportionality is
#             concluded when the 90% CI for beta lies entirely inside the
#             critical region [betaL, betaH], with
#                 r      = max(dose) / min(dose)               (dose range ratio)
#                 betaL  = 1 + log(0.80) / log(r)
#                 betaH  = 1 + log(1.25) / log(r)
#             Single dose -> no accumulation, no steady state: each participant
#             contributes ONE exposure value at ONE dose (parallel cohorts).
#             Placebo (dose 0) is excluded from the log-log model. Active drug
#             only; geometric scale throughout.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SAD")                        # cohorts = ascending doses (TRT01A)

## --- exposure values + administered dose, active arms only ------------------
## Dose preferred from ADEX (validated planned/actual dose); fall back to a dose
## variable carried on ADPP if present. Exclude placebo (dose 0) from the model.
dose_lk <- adam$adex %>%
  filter(SAFFL == "Y") %>%
  group_by(USUBJID) %>%
  summarise(dose = max(EXDOSE, na.rm = TRUE), .groups = "drop") %>%   # single SAD dose
  filter(is.finite(dose), dose > 0)

pp <- adam$adpp %>%
  filter(PKFL == "Y", PARAMCD %in% c("CMAX","AUCLST","AUCIFO"), AVAL > 0) %>%
  inner_join(dose_lk, by = "USUBJID") %>%                # active-arm participants w/ dose > 0
  mutate(lnval  = log(AVAL),
         lndose = log(dose))

## --- critical region for beta from the dose-range ratio r = max/min dose ----
r     <- max(dose_lk$dose) / min(dose_lk$dose)
betaL <- 1 + log(0.80) / log(r)
betaH <- 1 + log(1.25) / log(r)

## --- power-model fit per parameter: log(param) ~ log(dose), 90% CI on slope -
dp_one <- function(param) {
  d <- pp %>% filter(PARAMCD == param)
  ## ordinary least squares on the log-log scale; slope = beta (the power exponent)
  m  <- lm(lnval ~ lndose, data = d)
  ci <- confint(m, "lndose", level = 0.90)             # 90% CI for beta
  est <- coef(m)[["lndose"]]
  lo  <- ci[1, 1]; hi <- ci[1, 2]
  tibble(
    param     = param,
    n         = nrow(d),
    n_dose    = dplyr::n_distinct(d$dose),
    beta      = sprintf("%.3f", est),
    ci        = sprintf("%.3f - %.3f", lo, hi),
    ## proportional when the WHOLE 90% CI sits inside [betaL, betaH]
    conclude  = if_else(lo >= betaL & hi <= betaH,
                        "Dose proportional", "Not concluded"),
    ## also report the exposure ratio implied by the slope across the dose range
    exp_ratio = sprintf("%.2f", r^est))
}

dp <- map_dfr(c("CMAX","AUCLST","AUCIFO"), dp_one)

ttl <- tfl_titles(num = "14.4.4.1", type = "Table",
   text = "Assessment of Dose Proportionality (Power Model): Slope and 90% CI",
   pop  = "Pharmacokinetic Parameter Population",
   foot = paste(
     sprintf("Power model ln(parameter) ~ ln(dose); slope = beta. Dose range ratio r = %.2f.", r),
     sprintf("Critical region for beta = [%.3f, %.3f]  (betaL = 1+ln(0.80)/ln(r), betaH = 1+ln(1.25)/ln(r)).",
             betaL, betaH),
     "Dose proportionality concluded when the entire 90% CI for beta lies within the critical region.",
     "Active arms only; placebo (dose 0) excluded. Single dose -> no accumulation."))

## --- assemble: parameters as rows ------------------------------------------
tab <- dp %>% transmute(
  `PK Parameter`           = param,
  `n`                      = as.character(n),
  `# Dose Levels`          = as.character(n_dose),
  `Slope (beta)`           = beta,
  `90% CI (beta)`          = ci,
  `Critical Region`        = sprintf("%.3f - %.3f", betaL, betaH),
  `Conclusion`             = conclude,
  `Exposure Ratio (max/min dose)` = exp_ratio)

print(tab)
