################################################################################
# TABLE     : t_vitals_summary  (Single-/Fixed-Sequence DDI)
# TITLE     : Vital Signs - Observed Value and Change from Baseline by Period
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADVS (PARAMCD in SYSBP, DIABP, PULSE, TEMP, RESP)
# NOTE      : PSEUDOCODE. PERIOD table -> columns = dv$byperiod (APERIODC):
#             Period 1 = reference (victim alone), Period 2 = test (victim +
#             perpetrator). Within each period, descriptive summary (n, Mean (SD),
#             Median, Min-Max) of observed value AVAL and change-from-baseline CHG
#             per scheduled post-baseline AVISIT. NO randomized sequence column.
#             Per-PERIOD denominators come from ADEX (participants dosed per APERIOD,
#             SAFFL == "Y") -- NEVER one-row-per-participant ADSL. CHG/BASE are the
#             PERIOD-specific baseline carried on ADVS.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SINGLESEQ")                 # byperiod = c("APERIOD","APERIODC")
options(tfl.study = env$study)
perN <- dv$byperiod[1]; perC <- dv$byperiod[2]  # numeric + character period

## --- per-PERIOD denominators FROM ADEX (participants dosed in each period) -------
## House rule: per-period N comes from a period-bearing source (ADEX), not ADSL.
perdenom <- adam$adex %>% filter(SAFFL == "Y") %>%
  group_by(per = .data[[perC]]) %>%
  summarise(N = n_distinct(USUBJID), .groups = "drop")

## analysis records: safety, analysis-flagged scheduled timepoints
vs <- adam$advs %>%
  filter(SAFFL == "Y", ANL01FL == "Y",
         PARAMCD %in% c("SYSBP","DIABP","PULSE","TEMP","RESP")) %>%
  mutate(per     = .data[[perC]],                     # period = analysis column
         PARAMCD = factor(PARAMCD,
                          levels = c("SYSBP","DIABP","PULSE","TEMP","RESP")),
         AVISIT  = factor(AVISIT, levels = unique(AVISIT[order(AVISITN)])))

## --- observed value AVAL: descriptive stats by period x param x visit --------
val <- vs %>%
  descstat(var = "AVAL", by = c("PARAMCD","PARAM","AVISIT","AVISITN","per"), dp = 1L) %>%
  transmute(PARAMCD, PARAM, AVISIT, AVISITN, per, block = "Observed value",
            `n`         = as.character(n),
            `Mean (SD)` = paste(c_mean, c_sd),
            `Median`    = c_median,
            `Min, Max`  = c_minmax)

## --- change from baseline CHG (period baseline; baseline visit NA on CHG) ----
chg <- vs %>% filter(!is.na(CHG)) %>%
  descstat(var = "CHG", by = c("PARAMCD","PARAM","AVISIT","AVISITN","per"), dp = 1L) %>%
  transmute(PARAMCD, PARAM, AVISIT, AVISITN, per, block = "Change from baseline",
            `n`         = as.character(n),
            `Mean (SD)` = paste(c_mean, c_sd),
            `Median`    = c_median,
            `Min, Max`  = c_minmax)

## --- stack, long over the stat rows, wide over PERIOD ------------------------
tab <- bind_rows(val, chg) %>%
  pivot_longer(c(`n`,`Mean (SD)`,`Median`,`Min, Max`),
               names_to = "stat", values_to = "value") %>%
  mutate(stat  = factor(stat, levels = c("n","Mean (SD)","Median","Min, Max")),
         block = factor(block, levels = c("Observed value","Change from baseline"))) %>%
  pivot_wider(names_from = per, values_from = value) %>%
  arrange(PARAMCD, AVISITN, block, stat)

ttl <- tfl_titles(num = "14.3.7.1", type = "Table",
   text = "Vital Signs - Observed Value and Change from Baseline by Period",
   pop  = "Safety Population",
   foot = paste("Single-fixed-sequence DDI: Period 1 = reference (victim alone),",
                "Period 2 = test (victim + perpetrator). Baseline = period-specific",
                "pre-dose value; change = post-dose value - period baseline.",
                "Per-period N = participants dosed in each period (ADEX, SAFFL = Y)."))

## rtables layout: parameter > visit > value/change block -> stat rows x PERIOD columns
lyt <- basic_table(title = ttl$titles[3], main_footer = ttl$footnotes) %>%
  split_rows_by("PARAM",  page_by = FALSE) %>%
  split_rows_by("AVISIT", page_by = FALSE) %>%
  split_rows_by("block",  page_by = FALSE) %>%
  analyze("stat", afun = function(x) in_rows(.list = as.list(x)))
# tbl <- build_table(lyt, tab)   ## or gt::gt(tab) for HTML/Quarto
print(tab)
