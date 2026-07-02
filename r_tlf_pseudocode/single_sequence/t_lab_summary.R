################################################################################
# TABLE     : t_lab_summary  (Single-/Fixed-Sequence DDI)
# TITLE     : Summary of Laboratory Values and Change from Baseline by Period
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADLB (PARAMCD/PARAM, AVAL, BASE, CHG, AVISIT/AVISITN, APERIOD/
#             APERIODC, ANL01FL)
# NOTE      : PSEUDOCODE. PERIOD table -> split by dv$byperiod (APERIOD/APERIODC):
#             Period 1 = reference (victim alone), Period 2 = test (victim +
#             perpetrator). Per parameter x scheduled visit x PERIOD: n, Mean (SD),
#             Median, Min-Max for the observed value (AVAL) AND change from
#             baseline (CHG). Per-PERIOD denominators (N=) come from ADEX
#             (participants dosed per APERIOD, SAFFL == "Y") -- NEVER from one-row-per-
#             participant ADSL. Descriptive only; within-participant PK ratio (test period
#             vs reference period, 90% CI) is in single_sequence/t_be_anova.R.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SINGLESEQ")                 # byperiod = c("APERIOD","APERIODC")
options(tfl.study = env$study)
perC <- dv$byperiod[2]                           # character period label column

## one analysis record per participant/param/visit/period (ANL01FL keeps the reading)
lb <- adam$adlb %>%
  filter(SAFFL == "Y", ANL01FL == "Y",
         PARAMCD %in% c("ALT","AST","BILI","ALP","CREAT","BUN","GLUC",
                        "K","NA","HGB","WBC","PLAT","NEUT")) %>%
  mutate(per = .data[[perC]])

## --- per-PERIOD denominators FROM ADEX (participants dosed in each period) -------
## House rule: per-period N comes from a period-bearing source (ADEX), not ADSL.
perdenom <- adam$adex %>%
  filter(SAFFL == "Y") %>%
  group_by(trt = .data[[perC]]) %>%
  summarise(N = n_distinct(USUBJID), .groups = "drop")

## --- descriptive block: reuse descstat() for AVAL then CHG -----------------
## by = param, visit (ordered by AVISITN), PERIOD. Baseline visit CHG omitted.
lab_block <- function(var, statset_label) {
  descstat(lb, var = var, by = c("PARAMCD","PARAM","AVISITN","AVISIT", perC)) %>%
    transmute(PARAMCD, PARAM, AVISITN, AVISIT, per = .data[[perC]],
              measure = statset_label,
              `n`         = as.character(n),
              `Mean (SD)` = paste(c_mean, c_sd),
              `Median`    = c_median,
              `Min, Max`  = c_minmax) %>%
    pivot_longer(c(`n`,`Mean (SD)`,`Median`,`Min, Max`),
                 names_to = "stat", values_to = "value")
}

aval <- lab_block("AVAL", "Observed Value")
chg  <- lab_block("CHG",  "Change from Baseline") %>%
  filter(AVISITN > 0)                                   # no CHG at baseline visit

## --- stack: parameter -> visit -> measure -> statistic rows x PERIOD cols ----
tab <- bind_rows(aval, chg) %>%
  arrange(PARAM, AVISITN, factor(measure, c("Observed Value","Change from Baseline")), stat) %>%
  select(PARAM, AVISIT, measure, stat, per, value) %>%
  pivot_wider(names_from = per, values_from = value)

ttl <- tfl_titles(num = "14.3.4.1", type = "Table",
   text = "Summary of Laboratory Values and Change from Baseline by Period",
   pop  = "Safety Population",
   foot = paste("Single-fixed-sequence DDI: Period 1 = reference (victim alone),",
                "Period 2 = test (victim + perpetrator). Descriptive statistics by",
                "scheduled visit within period. Per-period denominators = participants",
                "dosed in each period (ADEX, SAFFL = Y). SI units. Baseline = last",
                "value on/before first dose; change = post-baseline - baseline."))

## rtables layout: PARAM -> AVISIT -> measure split, statistic rows x PERIOD cols
lyt <- basic_table(title = ttl$titles[3], main_footer = ttl$footnotes) %>%
  split_rows_by("PARAM",   page_by = TRUE) %>%
  split_rows_by("AVISIT")  %>%
  split_rows_by("measure") %>%
  analyze("stat", afun = function(x) in_rows(.list = as.list(x)))
# tbl <- build_table(lyt, tab)   ## or gt::gt(tab)
print(tab)
