################################################################################
# TABLE     : t_ecg_summary  (Single Ascending Dose)
# TITLE     : ECG Parameters - Observed Value and Change from Baseline by Visit
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADEG (PARAMCD in HR, PR, QRS, QT, QTCF, QTCB, RR)
# NOTE      : PSEUDOCODE. Continuous summary (n, Mean (SD), Median, Min-Max) of
#             observed value AVAL and change-from-baseline CHG, per scheduled
#             post-baseline AVISIT. QTcF is the primary corrected interval; QTcB
#             secondary. SAD: parallel dose cohorts, one treatment per participant ->
#             column = dv$trtvar (TRT01A = DOSE LEVEL), ordered low -> high by
#             TRT01AN (placebo pooled first) to read any dose-related QT signal
#             across cohorts. Single dose -> no period structure (no dv$byperiod).
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SAD")                       # -> trtvar = TRT01A, trtnvar = TRT01AN

denom <- bign(adam$adsl, trtvar = dv$trtvar, popfl = "SAFFL")

## dose-cohort column order: placebo first, then ascending by TRT01AN ----------
dose_order <- adam$adsl %>% filter(SAFFL == "Y") %>%
  distinct(trt = .data[[dv$trtvar]], trtn = .data[[dv$trtnvar]]) %>%
  arrange(trtn) %>% pull(trt)

## analysis records: safety, analysis-flagged scheduled timepoints
eg <- adam$adeg %>%
  filter(SAFFL == "Y", ANL01FL == "Y",
         PARAMCD %in% c("HR","PR","QRS","QT","QTCF","QTCB","RR")) %>%
  mutate(trt     = .data[[dv$trtvar]],
         PARAMCD = factor(PARAMCD,
                          levels = c("HR","PR","QRS","QT","QTCF","QTCB","RR")),
         AVISIT  = factor(AVISIT, levels = unique(AVISIT[order(AVISITN)])))

with_total <- function(df) bind_rows(df, mutate(df, trt = "Total"))

## --- observed value AVAL -----------------------------------------------------
val <- with_total(eg) %>%
  descstat(var = "AVAL", by = c("PARAMCD","PARAM","AVISIT","AVISITN","trt"), dp = 1L) %>%
  transmute(PARAMCD, PARAM, AVISIT, AVISITN, trt, block = "Observed value",
            `n`         = as.character(n),
            `Mean (SD)` = paste(c_mean, c_sd),
            `Median`    = c_median,
            `Min, Max`  = c_minmax)

## --- change from baseline CHG ------------------------------------------------
chg <- with_total(eg) %>% filter(!is.na(CHG)) %>%
  descstat(var = "CHG", by = c("PARAMCD","PARAM","AVISIT","AVISITN","trt"), dp = 1L) %>%
  transmute(PARAMCD, PARAM, AVISIT, AVISITN, trt, block = "Change from baseline",
            `n`         = as.character(n),
            `Mean (SD)` = paste(c_mean, c_sd),
            `Median`    = c_median,
            `Min, Max`  = c_minmax)

tab <- bind_rows(val, chg) %>%
  pivot_longer(c(`n`,`Mean (SD)`,`Median`,`Min, Max`),
               names_to = "stat", values_to = "value") %>%
  mutate(stat  = factor(stat, levels = c("n","Mean (SD)","Median","Min, Max")),
         block = factor(block, levels = c("Observed value","Change from baseline")),
         trt   = factor(trt, levels = c(dose_order, "Total"))) %>%
  pivot_wider(names_from = trt, values_from = value) %>%
  arrange(PARAMCD, AVISITN, block, stat)

ttl <- tfl_titles(num = "14.3.5.1", type = "Table",
   text = "ECG Parameters - Observed Value and Change from Baseline by Visit",
   pop  = "Safety Population",
   foot = "Columns are ascending SAD dose cohorts (placebo pooled first). QTcF = Fridericia-corrected QT (primary); QTcB = Bazett-corrected (secondary). Baseline = last value prior to single dose. N = participants in the Safety Population per cohort.")

lyt <- basic_table(title = ttl$titles[3], main_footer = ttl$footnotes) %>%
  split_rows_by("PARAM",  page_by = FALSE) %>%
  split_rows_by("AVISIT", page_by = FALSE) %>%
  split_rows_by("block",  page_by = FALSE) %>%
  analyze("stat", afun = function(x) in_rows(.list = as.list(x)))
# tbl <- build_table(lyt, tab)   ## or gt::gt(tab)
print(tab)
