################################################################################
# TABLE     : t_vitals_summary  (Crossover - 2x2 or Williams)
# TITLE     : Summary of Vital Signs and Change from Baseline by Treatment
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADVS (PARAMCD = SYSBP, DIABP, PULSE, TEMP, RESP)
# NOTE      : PSEUDOCODE. Crossover safety summary BY TREATMENT (dv$trtvar = TRTA);
#             baseline is the PERIOD baseline (ABLFL / per-period BASE), so each
#             participant contributes once per period to the matching treatment column.
#             Within-period: AVAL and CHG (n, Mean (SD), Median, Min-Max) by
#             scheduled visit. Columns = treatments + Total. Optional by-period
#             stratification shown via dv$byperiod (commented split).
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("CROSSOVER")                 # trtvar = TRTA; byperiod = APERIOD/APERIODC

## analysis records: post-baseline scheduled assessments, on-treatment
vs <- adam$advs %>%
  filter(SAFFL == "Y", ANL01FL == "Y",
         PARAMCD %in% c("SYSBP","DIABP","PULSE","TEMP","RESP")) %>%
  ## crossover: treatment column = TRTA (the treatment given in that period);
  ## CHG/BASE are the PERIOD-specific change/baseline carried on ADVS.
  mutate(trt = .data[[dv$trtvar]])

## column denominators (N=) per treatment + Total (participant-level, Safety pop)
denom <- bign(adam$adsl, trtvar = dv$trtvar, popfl = "SAFFL")

## --- per parameter x visit: AVAL block then CHG block ----------------------
param_lvls <- c(SYSBP="Systolic BP (mmHg)", DIABP="Diastolic BP (mmHg)",
                PULSE="Pulse (bpm)", TEMP="Temperature (C)", RESP="Resp. rate (br/min)")

summ_block <- function(pcd, which = c("AVAL","CHG"), dp = 1L) {
  which <- match.arg(which)
  d  <- vs %>% filter(PARAMCD == pcd)
  by <- c("trt", "AVISITN", "AVISIT")
  descstat(d, var = which, by = by, dp = dp) %>%
    transmute(PARAM = param_lvls[[pcd]], AVISITN, AVISIT, trt,
              block = if_else(which == "AVAL", "Observed value", "Change from baseline"),
              `n`           = as.character(n),
              `Mean (SD)`   = paste(c_mean, c_sd),
              `Median`      = c_median,
              `Min, Max`    = c_minmax) %>%
    pivot_longer(c(`n`,`Mean (SD)`,`Median`,`Min, Max`),
                 names_to = "stat", values_to = "value")
}

tab <- map_dfr(names(param_lvls), function(pcd)
                 bind_rows(summ_block(pcd, "AVAL"), summ_block(pcd, "CHG"))) %>%
  ## one column per treatment (+ Total handled by a duplicate "Total" pass if needed)
  pivot_wider(names_from = trt, values_from = value) %>%
  arrange(PARAM, AVISITN, block, match(stat, c("n","Mean (SD)","Median","Min, Max")))

## --- OPTIONAL: also split by treatment-period (within-participant ordering) -----
## When a by-period view is requested, add dv$byperiod[1] (APERIOD) to `by`:
##   by_p <- c("trt", dv$byperiod[1], "AVISITN", "AVISIT")
## Per-period denominators then come from ADEX (participants dosed per APERIOD,
## SAFFL=="Y"), NOT ADSL -- see t_ecg_summary.R for the ADEX denominator pattern.

ttl <- tfl_titles(num = "14.3.7.1", type = "Table",
   text = "Summary of Vital Signs and Change from Baseline by Treatment",
   pop  = "Safety Population",
   foot = "Baseline is the period-specific pre-dose value; change = post-dose value - period baseline. A participant contributes to each treatment column for the period in which that treatment was given.")

## rtables: PARAM -> block -> visit rows x treatment columns
lyt <- basic_table(title = ttl$titles[3], main_footer = ttl$footnotes) %>%
  split_rows_by("PARAM", page_by = TRUE) %>%
  split_rows_by("block") %>%
  split_rows_by("AVISIT") %>%
  analyze("stat", afun = function(x) in_rows(.list = as.list(x)))
# tbl <- build_table(lyt, tab)
print(tab)
