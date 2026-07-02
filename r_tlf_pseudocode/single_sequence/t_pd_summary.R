################################################################################
# TABLE     : t_pd_summary  (Single-/Fixed-Sequence DDI)
# TITLE     : Summary of Pharmacodynamic / Biomarker Endpoints by Period and
#             Visit
# POPULATION: PD-Evaluable Population (PDFL == "Y")
# INPUT     : ADPD (PARAMCD = PD biomarker codes; AVAL, CHG, PCHG, BASE,
#             AVISIT/AVISITN, ATPT/ATPTN, APERIOD/APERIODC)
# NOTE      : PSEUDOCODE. Continuous descriptive stats by PERIOD x visit:
#             n, Mean (SD), Median, Min-Max for AVAL, CHG and %CHG. PERIOD table
#             -> split by dv$byperiod (APERIOD/APERIODC): Period 1 = reference
#             (victim alone), Period 2 = test (victim + perpetrator). NO
#             randomized sequence. Per-PERIOD x visit denominators come from a
#             period-bearing source (ADPD: PD-evaluable participants with a value at
#             that period x visit), NEVER one-row-per-participant ADSL.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SINGLESEQ")                 # byperiod = c("APERIOD","APERIODC")
options(tfl.study = env$study)
perN <- dv$byperiod[1]; perC <- dv$byperiod[2]  # numeric + character period

## ALL PD parameters (match SAS all-PARAMCD coverage; loop over the param list)
pd <- adam$adpd %>%
  filter(PDFL == "Y") %>%
  mutate(visit = factor(AVISIT, levels = unique(AVISIT[order(AVISITN)])),
         per   = .data[[perC]])               # Period 1 ref / Period 2 test+perp

by <- c("per", "PARAM", "PARAMCD", "visit")

## --- per-PERIOD x visit denominators from a period-bearing source (ADPD) -----
## participants PD-evaluable WITH a value at each period x visit (NOT ADSL). Because
## a participant contributes to BOTH periods, denominators are taken per period.
denom_v <- pd %>%
  filter(!is.na(AVAL)) %>%
  group_by(per, visit) %>%
  summarise(N = n_distinct(USUBJID), .groups = "drop")

## --- descriptive stats for AVAL, CHG, %CHG (over ALL PARAMCD) ---------------
stat_block <- function(var, label, dp = 2L) {
  descstat(pd, var = var, by = by, dp = dp) %>%
    transmute(per, PARAM, PARAMCD, visit, measure = label,
              `n`         = as.character(n),
              `Mean (SD)` = paste(c_mean, c_sd),
              `Median`    = c_median,
              `Min, Max`  = c_minmax) %>%
    pivot_longer(c(`n`,`Mean (SD)`,`Median`,`Min, Max`),
                 names_to = "stat", values_to = "value")
}

body <- bind_rows(
  stat_block("AVAL", "Observed value",        2L),
  stat_block("CHG",  "Change from baseline",  2L),
  stat_block("PCHG", "% change from baseline",1L))

## --- header N= per period x visit (from ADPD denom, not ADSL) --------------
hdr <- denom_v %>% mutate(coln = sprintf("%s | %s (N=%d)", per, visit, N))

## --- stack: param/measure/stat rows x period-visit columns -----------------
tab <- body %>%
  arrange(PARAMCD) %>%
  unite("colkey", per, visit, sep = " | ", remove = FALSE) %>%
  select(PARAM, PARAMCD, measure, stat, colkey, value) %>%
  pivot_wider(names_from = colkey, values_from = value)

ttl <- tfl_titles(num = "14.4.6.1", type = "Table",
   text = "Summary of Pharmacodynamic Endpoints by Period and Visit",
   pop  = "Pharmacodynamic-Evaluable Population",
   foot = paste("Single-fixed-sequence DDI: Period 1 = reference (victim alone),",
                "Period 2 = test (victim + perpetrator). Descriptive only; no",
                "formal test at this level. Per-period x visit N from PD-evaluable",
                "participants with a value (ADPD), not ADSL. CHG/%CHG relative to",
                "ADaM BASE. All PD parameters (PARAMCD)."))

## rtables layout: PD parameter (block) -> measure (block) -> statistic rows
##                 x period-visit columns
lyt <- basic_table(title = ttl$titles[3], main_footer = ttl$footnotes) %>%
  split_rows_by("PARAM", page_by = FALSE) %>%
  split_rows_by("measure", page_by = FALSE) %>%
  analyze("stat", afun = function(x) in_rows(.list = as.list(x)))
# tbl <- build_table(lyt, tab)        ## or gt::gt(tab)
print(tab)
