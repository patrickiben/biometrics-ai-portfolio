################################################################################
# TABLE     : t_ecg_summary  (Multiple Ascending Dose)
# TITLE     : ECG Parameters - Observed Value and Change from Baseline by Dosing
#             Day/Visit
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADEG (PARAMCD in HR, PR, QRS, QT, QTCF, QTCB, RR)
# NOTE      : PSEUDOCODE. Continuous summary (n, Mean (SD), Median, Min-Max) of
#             observed value AVAL and change-from-baseline CHG, per scheduled
#             post-baseline AVISIT, columns = dose-level cohorts + Total. QTcF is
#             the primary corrected interval; QTcB shown as secondary. MAD =
#             parallel dose cohorts with REPEATED dosing: column = dv$trtvar
#             (TRT01A = dose level; placebo pooled). Visit axis spans the multi-
#             day dosing period so any QTc drift over repeat dosing is visible.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("MAD")                      # -> trtvar = TRT01A, trtnvar = TRT01AN

denom <- bign(adam$adsl, trtvar = dv$trtvar, popfl = "SAFFL")

## analysis records: safety, analysis-flagged scheduled timepoints
eg <- adam$adeg %>%
  filter(SAFFL == "Y", ANL01FL == "Y",
         PARAMCD %in% c("HR","PR","QRS","QT","QTCF","QTCB","RR")) %>%
  mutate(trt     = .data[[dv$trtvar]],          # dose-level column (placebo pooled)
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
         block = factor(block, levels = c("Observed value","Change from baseline"))) %>%
  pivot_wider(names_from = trt, values_from = value) %>%
  arrange(PARAMCD, AVISITN, block, stat)

ttl <- tfl_titles(num = "14.3.6.1", type = "Table",
   text = "ECG Parameters - Observed Value and Change from Baseline by Dosing Day/Visit",
   pop  = "Safety Population",
   foot = paste("QTcF = Fridericia-corrected QT (primary); QTcB = Bazett-corrected",
                "(secondary). MAD: columns = dose cohort (ascending dose; placebo",
                "pooled). Baseline = last value prior to first dose (Day 1). Visits",
                "span the repeat-dosing period. N = participants in the Safety Population",
                "per cohort."))

lyt <- basic_table(title = ttl$titles[3], main_footer = ttl$footnotes) %>%
  split_rows_by("PARAM",  page_by = FALSE) %>%
  split_rows_by("AVISIT", page_by = FALSE) %>%
  split_rows_by("block",  page_by = FALSE) %>%
  analyze("stat", afun = function(x) in_rows(.list = as.list(x)))
# tbl <- build_table(lyt, tab)   ## or gt::gt(tab)
print(tab)
