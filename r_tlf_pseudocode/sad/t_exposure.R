################################################################################
# TABLE     : t_exposure  (Single Ascending Dose)
# TITLE     : Extent of Study Drug Exposure by Dose Cohort
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADEX  (dosing records; SAD = a single administration per participant)
# NOTE      : PSEUDOCODE. SAD = parallel dose cohorts; column = DOSE LEVEL
#             (TRT01A). SINGLE DOSE -> exactly one administration per participant,
#             so "exposure" = the single administered dose; NO cumulative-dose
#             or duration-of-repeated-dosing concept (that is MAD). Per-cohort
#             denominator = participants DOSED from ADEX (SAFFL=="Y"), NOT one-row-
#             per-participant ADSL. Reports administered dose, dose-normalized
#             (mg/kg) summary, and compliance/actual-vs-planned dose n (%).
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SAD")                       # -> trtvar = TRT01A (dose level), trtnvar = TRT01AN

## ADEX = dosing-bearing source. SAD has a single administration per participant, so
## the exposure denominator is "participants dosed" derived from ADEX itself, and
## the column is the administered dose level (TRT01A). Placebo pooled.
adex <- adam$adex %>%
  filter(SAFFL == "Y") %>%
  mutate(
    dose_col = if_else(toupper(.data[[dv$trtvar]]) == "PLACEBO" | .data[[dv$trtnvar]] == 0,
                       "Placebo", .data[[dv$trtvar]]),
    dose_ord = if_else(toupper(.data[[dv$trtvar]]) == "PLACEBO" | .data[[dv$trtnvar]] == 0,
                       0, .data[[dv$trtnvar]]))

## --- per-participant single-dose roll-up --------------------------------------
## SAD: one dosing record per participant. Guard against >1 record by summing, but
## the expected n_admin == 1. EXDOSE = administered dose; WEIGHTBL for mg/kg.
exp_subj <- adex %>%
  group_by(USUBJID, trt = dose_col) %>%
  summarise(
    admin_dose = sum(EXDOSE, na.rm = TRUE),                  # single administered dose (mg)
    n_admin    = sum(!is.na(EXDOSE) & EXDOSE > 0),           # expected = 1 for SAD
    wt         = dplyr::first(WEIGHTBL),                     # baseline weight (kg)
    .groups = "drop") %>%
  mutate(dose_mgkg = if_else(!is.na(wt) & wt > 0, admin_dose / wt, NA_real_))

## --- dosed-participant denominators per cohort + Total (from ADEX) ------------
denom <- exp_subj %>%
  group_by(trt) %>%
  summarise(N = n_distinct(USUBJID), .groups = "drop") %>%
  bind_rows(tibble(trt = "Total", N = n_distinct(exp_subj$USUBJID)))

## --- continuous exposure block (single-dose) ------------------------------
cont_block <- function(var, label, dp = 1L, ord) {
  descstat(exp_subj, var = var, by = "trt", dp = dp) %>%
    transmute(trt, characteristic = label, ord = ord,
              `n`         = as.character(n),
              `Mean (SD)` = paste(c_mean, c_sd),
              `Median`    = c_median,
              `Min, Max`  = c_minmax) %>%
    pivot_longer(c(`n`,`Mean (SD)`,`Median`,`Min, Max`),
                 names_to = "stat", values_to = "value")
}
cont <- bind_rows(
  cont_block("admin_dose", "Administered Dose (mg)",        1L, 1),
  cont_block("dose_mgkg",  "Dose-Normalized (mg/kg)",       2L, 2),
  cont_block("n_admin",    "Number of Administrations",     0L, 3))   # = 1 (SAD)

## --- categorical: dose level n (%) (TRT01A = dose cohort) -----------------
dose_cat <- catfreq(exp_subj, var = "trt", by = "trt", denom = denom) %>%
  transmute(trt, characteristic = "Dose Level n (%)", ord = 4,
            stat = cat, value = disp)

## --- categorical: compliance (administered within tolerance of planned) n (%) -
## Compare administered (EXDOSE) to PLANNED dose (EXPLDOS); compliant = within a
## +/-5% tolerance and not flagged as adjusted (EXADJ blank) -- mirrors the SAS
## dose-deviation rows (Within 5% of planned / Dose deviation > 5%). No tautology.
tol <- 0.05
comp <- adex %>%
  group_by(USUBJID, trt = dose_col) %>%
  summarise(
    dose_dev = {
      a <- sum(EXDOSE,   na.rm = TRUE)             # administered
      p <- sum(EXPLDOS,  na.rm = TRUE)             # planned
      if (is.na(p) || p == 0) NA_real_ else abs(a - p) / p
    },
    adjusted = any(coalesce(toupper(EXADJ), "") != ""),
    .groups = "drop") %>%
  mutate(compcat = if_else(!is.na(dose_dev) & dose_dev <= tol & !adjusted,
                           "Within 5% of planned", "Dose deviation > 5%"))
comp_cat <- catfreq(comp, var = "compcat", by = "trt", denom = denom) %>%
  transmute(trt, characteristic = "Dosing Compliance n (%)", ord = 5,
            stat = as.character(cat), value = disp)

## --- stack rows x dose-cohort columns, render ------------------------------
tab <- bind_rows(cont, dose_cat, comp_cat) %>%
  pivot_wider(names_from = trt, values_from = value) %>%
  arrange(ord)

ttl <- tfl_titles(num = "14.1.4", type = "Table",
   text = "Extent of Study Drug Exposure by Dose Cohort",
   pop  = "Safety Population",
   foot = "SAD single dose: one administration per participant. Denominator = participants dosed per cohort (ADEX, SAFFL=='Y'). Dose-normalized = administered dose / baseline weight. No cumulative-dose/duration concept (single dose).")

lyt <- basic_table(title = ttl$titles[3], main_footer = ttl$footnotes) %>%
  split_rows_by("characteristic", page_by = FALSE) %>%
  analyze("stat", afun = function(x) in_rows(.list = as.list(x)))
# tbl <- build_table(lyt, tab)   ## or gt::gt(tab)
print(tab)
