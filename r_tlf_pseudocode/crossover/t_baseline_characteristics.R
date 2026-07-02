################################################################################
# TABLE     : t_baseline_characteristics  (Crossover - 2x2 / Williams)
# TITLE     : Baseline Disease and Clinical Characteristics
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADSL  (study-entry baseline)  + ADVS/ADLB BASE (PERIOD-1 baselines)
# NOTE      : PSEUDOCODE. PARTICIPANT-LEVEL table. STUDY-entry baselines (smoking,
#             child-bearing potential, baseline vitals/labs measured once at
#             screening) are fixed within participant -> columns = treatment SEQUENCE
#             (dv$seqvar = TRTSEQP) + Total. CAUTION: crossover trials also carry
#             a PERIOD-specific pre-dose baseline (BASE at ABLFL=="Y" within each
#             APERIOD); those belong in the by-period efficacy/PD/safety change
#             tables keyed on dv$byperiod, NOT here. This table is study-entry
#             characteristics only.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("CROSSOVER")   # seqvar = TRTSEQP (participant-level), byperiod for the caveat above

adsl <- adam$adsl %>% filter(SAFFL == "Y")     # one row per participant

denom <- bign(adsl, trtvar = dv$seqvar, popfl = "SAFFL")

## --- continuous study-entry characteristics (screening, fixed within participant)
cont_block <- function(var, label, dp = 1L, ord) {
  descstat(adsl, var = var, by = dv$seqvar, dp = dp) %>%
    transmute(trt = .data[[dv$seqvar]], characteristic = label, ord = ord,
              `n`         = as.character(n),
              `Mean (SD)` = paste(c_mean, c_sd),
              `Median`    = c_median,
              `Min, Max`  = c_minmax) %>%
    pivot_longer(c(`n`,`Mean (SD)`,`Median`,`Min, Max`), names_to = "stat", values_to = "value")
}
cont <- bind_rows(
  cont_block("HRBL",   "Baseline heart rate (bpm)",  0L, 1),  # screening vital
  cont_block("SYSBPBL","Baseline systolic BP (mmHg)",0L, 2),
  cont_block("CREATBL","Baseline creatinine (mg/dL)",2L, 3),
  cont_block("CRCLBL", "Baseline creat. clearance (mL/min)", 1L, 4))

## --- categorical study-entry characteristics -------------------------------
cat_block <- function(var, label, ord) {
  catfreq(adsl, var = var, by = dv$seqvar, denom = denom) %>%
    transmute(trt = .data[[dv$seqvar]], characteristic = label, ord, stat = cat, value = disp)
}
catg <- bind_rows(
  cat_block("SMOKSTAT", "Smoking status n (%)",            5),
  cat_block("CHILDPOT", "Child-bearing potential n (%)",   6),
  cat_block("BMICAT",   "Baseline BMI category n (%)",     7),
  cat_block("RENALCAT", "Baseline renal function n (%)",   8))

tab <- bind_rows(cont, catg) %>%
  pivot_wider(names_from = trt, values_from = value) %>%
  arrange(ord)

ttl <- tfl_titles(num = "14.1.3", type = "Table",
   text = "Baseline Disease and Clinical Characteristics",
   pop  = "Safety Population",
   foot = "Study-entry (screening) characteristics, fixed within participant; columns = randomized sequence (TRTSEQP). Period-specific pre-dose baselines are reported in the by-period change tables.")

lyt <- basic_table(title = ttl$titles[3], main_footer = ttl$footnotes) %>%
  split_rows_by("characteristic", page_by = FALSE) %>%
  analyze("stat", afun = function(x) in_rows(.list = as.list(x)))
# tbl <- build_table(lyt, tab)
print(tab)
