################################################################################
# TABLE     : t_ecg_summary  (Crossover - 2x2 or Williams)
# TITLE     : Summary of ECG Parameters and Change from Baseline by Treatment
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADEG (PARAMCD = HR, PR, QRS, QT, QTCF, QTCB, RR)
# NOTE      : PSEUDOCODE. Crossover ECG safety summary BY TREATMENT
#             (dv$trtvar = TRTA), with an OPTIONAL by-PERIOD view. When split by
#             period, the column N comes from a PERIOD-BEARING source: ADEX
#             participants dosed per APERIOD with SAFFL=='Y' -- NEVER one-row ADSL.
#             AVAL and CHG: n, Mean (SD), Median, Min-Max by scheduled visit.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("CROSSOVER")                 # trtvar = TRTA; byperiod = APERIOD/APERIODC

eg <- adam$adeg %>%
  filter(SAFFL == "Y", ANL01FL == "Y",
         PARAMCD %in% c("HR","PR","QRS","QT","QTCF","QTCB","RR")) %>%
  mutate(trt = .data[[dv$trtvar]])

## --- denominators -----------------------------------------------------------
## by-treatment column N (participant-level, Safety pop)
denom_trt <- bign(adam$adsl, trtvar = dv$trtvar, popfl = "SAFFL")

## OPTIONAL by-PERIOD denominator: participants DOSED in each treatment-period,
## from ADEX (period-bearing). Use this if the table is split by APERIOD.
denom_per <- adam$adex %>%
  filter(SAFFL == "Y") %>%
  group_by(trt = .data[[dv$trtvar]], APERIOD = .data[[dv$byperiod[1]]],
           APERIODC = .data[[dv$byperiod[2]]]) %>%
  summarise(N = n_distinct(USUBJID), .groups = "drop")

## --- per parameter x visit: AVAL block then CHG block ----------------------
param_lvls <- c(HR="Heart Rate (bpm)", PR="PR Interval (ms)", QRS="QRS Duration (ms)",
                QT="QT Interval (ms)", QTCF="QTcF (ms)", QTCB="QTcB (ms)", RR="RR Interval (ms)")

summ_block <- function(pcd, which = c("AVAL","CHG"), dp = 1L) {
  which <- match.arg(which)
  d  <- eg %>% filter(PARAMCD == pcd)
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
  pivot_wider(names_from = trt, values_from = value) %>%
  arrange(PARAM, AVISITN, block, match(stat, c("n","Mean (SD)","Median","Min, Max")))

ttl <- tfl_titles(num = "14.3.8.1", type = "Table",
   text = "Summary of ECG Parameters and Change from Baseline by Treatment",
   pop  = "Safety Population",
   foot = "Baseline is the period-specific pre-dose value; change = post-dose - period baseline. QTcF/QTcB are machine/over-read corrected. If split by period, column N = participants dosed per period (ADEX).")

## rtables: PARAM -> block -> visit rows x treatment columns
lyt <- basic_table(title = ttl$titles[3], main_footer = ttl$footnotes) %>%
  split_rows_by("PARAM", page_by = TRUE) %>%
  split_rows_by("block") %>%
  split_rows_by("AVISIT") %>%
  analyze("stat", afun = function(x) in_rows(.list = as.list(x)))
# tbl <- build_table(lyt, tab)
print(tab)
