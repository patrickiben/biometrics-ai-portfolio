################################################################################
# TABLE     : t_baseline_characteristics  (Multiple Ascending Dose)
# TITLE     : Baseline Disease and Clinical Characteristics by Dose Cohort
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADSL  (+ baseline records from ADVS/ADLB if pulled via BASE)
# NOTE      : PSEUDOCODE. Complements t_demographics: baseline clinical state
#             (vitals, eGFR/creatinine clearance, smoking/alcohol, baseline
#             disease severity). Continuous: n, Mean (SD), Median, Min-Max;
#             categorical: n (%). MAD = parallel dose cohorts; columns = DOSE
#             LEVEL (TRT01A) with placebo pooled + Total. Participant-level table.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("MAD")                       # -> trtvar = TRT01A (dose level), trtnvar = TRT01AN

## one row per participant; pool placebo across ascending cohorts into one column
adsl <- adam$adsl %>%
  filter(SAFFL == "Y") %>%
  mutate(
    dose_col = if_else(toupper(TRT01A) == "PLACEBO" | TRT01AN == 0,
                       "Placebo", .data[[dv$trtvar]]),
    dose_ord = if_else(toupper(TRT01A) == "PLACEBO" | TRT01AN == 0,
                       0, .data[[dv$trtnvar]]))

## column denominators (N=) per dose cohort + Total
denom <- bign(adsl %>% mutate(.dc = dose_col), trtvar = ".dc", popfl = "SAFFL")

## --- continuous baseline clinical block -----------------------------------
## Baseline vitals/renal carried on ADSL as ...BL fields (SBPBL/DBPBL/PULSEBL/
## CRCLBL/EGFRBL). If not on ADSL, derive from ADVS/ADLB ABLFL=="Y" via BASE.
cont_block <- function(var, label, dp = 1L, ord) {
  descstat(adsl, var = var, by = "dose_col", dp = dp) %>%
    transmute(trt = dose_col, characteristic = label, ord = ord,
              `n`         = as.character(n),
              `Mean (SD)` = paste(c_mean, c_sd),
              `Median`    = c_median,
              `Min, Max`  = c_minmax) %>%
    pivot_longer(c(`n`,`Mean (SD)`,`Median`,`Min, Max`),
                 names_to = "stat", values_to = "value")
}
cont <- bind_rows(
  cont_block("SBPBL",  "Systolic BP (mmHg)",          1L, 1),
  cont_block("DBPBL",  "Diastolic BP (mmHg)",         1L, 2),
  cont_block("PULSEBL","Pulse Rate (bpm)",            1L, 3),
  cont_block("CRCLBL", "Creatinine Clearance (mL/min)",1L, 4),
  cont_block("EGFRBL", "eGFR (mL/min/1.73m^2)",       1L, 5))

## --- categorical baseline block -------------------------------------------
cat_block <- function(var, label, ord) {
  catfreq(adsl %>% mutate(.dc = dose_col), var = var, by = ".dc", denom = denom) %>%
    transmute(trt = .dc, characteristic = label, ord, stat = cat, value = disp)
}
catg <- bind_rows(
  cat_block("SMOKSTAT", "Smoking Status n (%)",       6),
  cat_block("ALCOHOL",  "Alcohol Use n (%)",          7),
  cat_block("RENALCAT", "Renal Function Group n (%)", 8),   # Normal/Mild/Moderate
  cat_block("DISSEVBL", "Baseline Disease Severity n (%)", 9))

## --- stack, one column per dose cohort, render ----------------------------
tab <- bind_rows(cont, catg) %>%
  pivot_wider(names_from = trt, values_from = value) %>%
  arrange(ord)

ttl <- tfl_titles(num = "14.1.3", type = "Table",
   text = "Baseline Disease and Clinical Characteristics by Dose Cohort",
   pop  = "Safety Population",
   foot = "MAD: columns = ascending dose cohorts (TRT01A) with placebo pooled. Percentages based on Safety Population N per cohort. Baseline = last non-missing value on or before first dose (ABLFL).")

lyt <- basic_table(title = ttl$titles[3], main_footer = ttl$footnotes) %>%
  split_rows_by("characteristic", page_by = FALSE) %>%
  analyze("stat", afun = function(x) in_rows(.list = as.list(x)))
# tbl <- build_table(lyt, tab)   ## or gt::gt(tab)
print(tab)
