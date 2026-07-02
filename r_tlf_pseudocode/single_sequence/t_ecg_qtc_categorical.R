################################################################################
# TABLE     : t_ecg_qtc_categorical  (Single-/Fixed-Sequence DDI)
# TITLE     : Categorical Summary of QTcF: Maximum Post-Baseline Value and
#             Maximum Change from Baseline by Period
# POPULATION: Safety Population (SAFFL == "Y"), post-baseline
# INPUT     : ADEG (PARAMCD == "QTCF"; AVAL, CHG, post-baseline)
# NOTE      : PSEUDOCODE. Counts = PARTICIPANTS (n_distinct USUBJID), NOT records.
#             ICH E14 thresholds -- absolute QTcF: >450, >480, >500 ms; change
#             from baseline: >30, >60 ms. Categories are CUMULATIVE (NOT mutually
#             exclusive) per the E14 convention and the SAS twin: a participant may
#             appear in more than one category. PERIOD table (dv$byperiod =
#             APERIODC): Period 1 = reference (victim alone), Period 2 = test
#             (victim + perpetrator); a participant may appear under both periods
#             (once per period received). % denominator = participants DOSED in
#             that PERIOD from ADEX (SAFFL == "Y", per APERIOD) -- period-bearing
#             source, NEVER one-row-per-participant ADSL. Matches the SAS twin and
#             the t_ecg_summary sister table.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
options(tfl.study = env$study)
dv  <- design_vars("SINGLESEQ")                 # byperiod = c("APERIOD","APERIODC")
perC <- dv$byperiod[2]

## --- per-PERIOD denominator FROM ADEX (participants dosed in each period) --------
## Exactly as the SAS twin (_bign from adam.adex where SAFFL='Y') and the
## t_ecg_summary sister. House rule: per-period N comes from a period-bearing
## source (ADEX), NOT from adeg evaluable records and NOT from ADSL.
perdenom <- adam$adex %>% filter(SAFFL == "Y") %>%
  group_by(per = .data[[perC]]) %>%
  summarise(N = n_distinct(USUBJID), .groups = "drop")

## analysis records: safety, analysis-flagged, post-baseline (AVISITN > 0), QTcF
## -- same selection as the SAS twin (SAFFL='Y' and ANL01FL='Y' and AVISITN>0).
eg <- adam$adeg %>%
  filter(SAFFL == "Y", PARAMCD == "QTCF", ANL01FL == "Y", AVISITN > 0) %>%   # post-baseline
  mutate(per = .data[[perC]])

## --- per participant x period: worst (max) absolute QTcF and max CHG ------------
worst <- eg %>%
  group_by(USUBJID, per) %>%
  summarise(maxQT  = if (all(is.na(AVAL))) NA_real_ else max(AVAL, na.rm = TRUE),
            maxCHG = if (all(is.na(CHG)))  NA_real_ else max(CHG,  na.rm = TRUE),
            .groups = "drop")

## --- absolute QTcF: CUMULATIVE threshold indicators (not mutually exclusive) -
## per participant-period worst value; a participant may satisfy >1 threshold.
abs_flag <- worst %>%
  filter(!is.na(maxQT)) %>%
  mutate(`> 450 ms` = maxQT > 450,
         `> 480 ms` = maxQT > 480,
         `> 500 ms` = maxQT > 500) %>%
  pivot_longer(c(`> 450 ms`,`> 480 ms`,`> 500 ms`),
               names_to = "cat", values_to = "flag") %>%
  group_by(per, cat) %>%
  summarise(n = n_distinct(USUBJID[flag]), .groups = "drop") %>%
  mutate(block = "Maximum post-baseline QTcF")

## --- change from baseline: CUMULATIVE threshold indicators ------------------
chg_flag <- worst %>%
  filter(!is.na(maxCHG)) %>%
  mutate(`> 30 ms` = maxCHG > 30,
         `> 60 ms` = maxCHG > 60) %>%
  pivot_longer(c(`> 30 ms`,`> 60 ms`),
               names_to = "cat", values_to = "flag") %>%
  group_by(per, cat) %>%
  summarise(n = n_distinct(USUBJID[flag]), .groups = "drop") %>%
  mutate(block = "Maximum increase from baseline in QTcF")

## fixed category order within each block for display (matches SAS row set)
cat_order <- c("> 450 ms","> 480 ms","> 500 ms",
               "> 30 ms","> 60 ms")

rep <- bind_rows(abs_flag, chg_flag) %>%
  left_join(perdenom, by = "per") %>%
  mutate(value = n_pct(n, N),                         # participants, % of period denom
         cat = factor(cat, levels = cat_order)) %>%
  arrange(block, cat) %>%
  select(block, cat, per, value) %>%
  pivot_wider(names_from = per, values_from = value)

ttl <- tfl_titles(num = "14.3.8.2", type = "Table",
   text = "Categorical Summary of QTcF (Maximum Value and Maximum Change) by Period",
   pop  = "Safety Population",
   foot = paste("Single-fixed-sequence DDI: Period 1 = reference (victim alone),",
                "Period 2 = test (victim + perpetrator). ICH E14 thresholds.",
                "Categories are cumulative; a participant may appear in more than one",
                "category. % = participants with >=1 evaluable post-baseline QTcF in",
                "that period. A participant may contribute to both period columns."))

## rtables: block -> category rows x PERIOD columns
lyt <- basic_table(title = ttl$titles[3], main_footer = ttl$footnotes) %>%
  split_rows_by("block", page_by = FALSE) %>%
  analyze("cat", afun = function(x) in_rows(.list = as.list(x)))
# tbl <- build_table(lyt, rep)
print(rep)
