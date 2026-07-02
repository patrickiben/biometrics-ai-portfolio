################################################################################
# TABLE     : t_vitals_summary  (Parallel-group)
# TITLE     : Vital Signs - Observed Value and Change from Baseline by Visit
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADVS (PARAMCD in SYSBP, DIABP, PULSE, TEMP, RESP)
# NOTE      : PSEUDOCODE. Continuous summary (n, Mean (SD), Median, Min-Max) of
#             observed value AVAL and change-from-baseline CHG, per scheduled
#             post-baseline AVISIT, columns = treatment arms + Total. Parallel:
#             one treatment per participant; column = dv$trtvar (TRT01A). No within-
#             participant/period structure (no dv$byperiod).
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("PARALLEL")                 # -> trtvar = TRT01A, trtnvar = TRT01AN

## column denominators (N=) per arm + Total (from ADSL one-row-per-participant)
denom <- bign(adam$adsl, trtvar = dv$trtvar, popfl = "SAFFL")

## analysis records: safety, analysis-flagged scheduled timepoints
vs <- adam$advs %>%
  filter(SAFFL == "Y", ANL01FL == "Y",
         PARAMCD %in% c("SYSBP","DIABP","PULSE","TEMP","RESP")) %>%
  mutate(trt    = .data[[dv$trtvar]],
         PARAMCD = factor(PARAMCD,
                          levels = c("SYSBP","DIABP","PULSE","TEMP","RESP")),
         AVISIT  = factor(AVISIT, levels = unique(AVISIT[order(AVISITN)])))

## helper: stack a Total pseudo-arm so descstat() summarises arms + Total
with_total <- function(df) bind_rows(df, mutate(df, trt = "Total"))

## --- observed value AVAL: descriptive stats by arm x param x visit ----------
val <- with_total(vs) %>%
  descstat(var = "AVAL", by = c("PARAMCD","PARAM","AVISIT","AVISITN","trt"), dp = 1L) %>%
  transmute(PARAMCD, PARAM, AVISIT, AVISITN, trt, block = "Observed value",
            `n`         = as.character(n),
            `Mean (SD)` = paste(c_mean, c_sd),
            `Median`    = c_median,
            `Min, Max`  = c_minmax)

## --- change from baseline CHG (baseline visit excluded by CHG NA) -----------
chg <- with_total(vs) %>% filter(!is.na(CHG)) %>%
  descstat(var = "CHG", by = c("PARAMCD","PARAM","AVISIT","AVISITN","trt"), dp = 1L) %>%
  transmute(PARAMCD, PARAM, AVISIT, AVISITN, trt, block = "Change from baseline",
            `n`         = as.character(n),
            `Mean (SD)` = paste(c_mean, c_sd),
            `Median`    = c_median,
            `Min, Max`  = c_minmax)

## --- stack, long over the stat rows, wide over treatment --------------------
tab <- bind_rows(val, chg) %>%
  pivot_longer(c(`n`,`Mean (SD)`,`Median`,`Min, Max`),
               names_to = "stat", values_to = "value") %>%
  mutate(stat = factor(stat, levels = c("n","Mean (SD)","Median","Min, Max")),
         block = factor(block, levels = c("Observed value","Change from baseline"))) %>%
  pivot_wider(names_from = trt, values_from = value) %>%
  arrange(PARAMCD, AVISITN, block, stat)

ttl <- tfl_titles(num = "14.3.7.1", type = "Table",
   text = "Vital Signs - Observed Value and Change from Baseline by Visit",
   pop  = "Safety Population",
   foot = "Baseline = last non-missing assessment prior to first dose; change = post-baseline value - baseline. N = participants in the Safety Population per arm.")

## rtables layout: parameter > visit > value/change block -> statistic rows x arm columns
lyt <- basic_table(title = ttl$titles[3], main_footer = ttl$footnotes) %>%
  split_rows_by("PARAM",  page_by = FALSE) %>%
  split_rows_by("AVISIT", page_by = FALSE) %>%
  split_rows_by("block",  page_by = FALSE) %>%
  analyze("stat", afun = function(x) in_rows(.list = as.list(x)))
# tbl <- build_table(lyt, tab)   ## or gt::gt(tab) for HTML/Quarto
print(tab)
