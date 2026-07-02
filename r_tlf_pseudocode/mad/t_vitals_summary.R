################################################################################
# TABLE     : t_vitals_summary  (Multiple Ascending Dose)
# TITLE     : Vital Signs - Observed Value and Change from Baseline by Dosing
#             Day/Visit
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADVS (PARAMCD in SYSBP, DIABP, PULSE, TEMP, RESP)
# NOTE      : PSEUDOCODE. Continuous summary (n, Mean (SD), Median, Min-Max) of
#             observed value AVAL and change-from-baseline CHG, per scheduled
#             post-baseline AVISIT, columns = dose-level cohorts + Total. MAD =
#             parallel dose cohorts with REPEATED dosing: column = dv$trtvar
#             (TRT01A = dose level), one treatment per participant (placebo pooled
#             upstream per SAP). Visit axis spans the multi-day dosing period
#             (e.g. Day 1, Day 7, Day 14) so on-treatment trends across
#             repeat-dose days are visible. Baseline = pre-first-dose (Day 1).
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("MAD")                      # -> trtvar = TRT01A, trtnvar = TRT01AN

## column denominators (N=) per dose cohort + Total. Participant-level safety table:
## one treatment per participant (MAD parallel cohorts) -> ADSL is the correct denom.
denom <- bign(adam$adsl, trtvar = dv$trtvar, popfl = "SAFFL")

## analysis records: safety, analysis-flagged scheduled timepoints across the
## multi-day dosing period (AVISITN orders Day 1 ... Day N ... follow-up).
vs <- adam$advs %>%
  filter(SAFFL == "Y", ANL01FL == "Y",
         PARAMCD %in% c("SYSBP","DIABP","PULSE","TEMP","RESP")) %>%
  mutate(trt     = .data[[dv$trtvar]],          # dose-level column (placebo pooled)
         PARAMCD = factor(PARAMCD,
                          levels = c("SYSBP","DIABP","PULSE","TEMP","RESP")),
         AVISIT  = factor(AVISIT, levels = unique(AVISIT[order(AVISITN)])))

## helper: stack a Total pseudo-cohort so descstat() summarises cohorts + Total
with_total <- function(df) bind_rows(df, mutate(df, trt = "Total"))

## --- observed value AVAL: descriptive stats by cohort x param x visit --------
val <- with_total(vs) %>%
  descstat(var = "AVAL", by = c("PARAMCD","PARAM","AVISIT","AVISITN","trt"), dp = 1L) %>%
  transmute(PARAMCD, PARAM, AVISIT, AVISITN, trt, block = "Observed value",
            `n`         = as.character(n),
            `Mean (SD)` = paste(c_mean, c_sd),
            `Median`    = c_median,
            `Min, Max`  = c_minmax)

## --- change from baseline CHG (baseline visit excluded by CHG NA) ------------
chg <- with_total(vs) %>% filter(!is.na(CHG)) %>%
  descstat(var = "CHG", by = c("PARAMCD","PARAM","AVISIT","AVISITN","trt"), dp = 1L) %>%
  transmute(PARAMCD, PARAM, AVISIT, AVISITN, trt, block = "Change from baseline",
            `n`         = as.character(n),
            `Mean (SD)` = paste(c_mean, c_sd),
            `Median`    = c_median,
            `Min, Max`  = c_minmax)

## --- stack, long over the stat rows, wide over dose cohort -------------------
## NB: cohort columns should render in ascending dose order (TRT01AN), placebo first.
tab <- bind_rows(val, chg) %>%
  pivot_longer(c(`n`,`Mean (SD)`,`Median`,`Min, Max`),
               names_to = "stat", values_to = "value") %>%
  mutate(stat  = factor(stat, levels = c("n","Mean (SD)","Median","Min, Max")),
         block = factor(block, levels = c("Observed value","Change from baseline"))) %>%
  pivot_wider(names_from = trt, values_from = value) %>%
  arrange(PARAMCD, AVISITN, block, stat)

ttl <- tfl_titles(num = "14.3.7.1", type = "Table",
   text = "Vital Signs - Observed Value and Change from Baseline by Dosing Day/Visit",
   pop  = "Safety Population",
   foot = paste("MAD: columns = dose cohort (ascending dose; placebo pooled).",
                "Baseline = last value prior to first dose (Day 1); change = post-",
                "baseline value - baseline. Visits span the repeat-dosing period.",
                "N = participants in the Safety Population per cohort."))

## rtables layout: parameter > visit > value/change block -> statistic rows x cohort cols
lyt <- basic_table(title = ttl$titles[3], main_footer = ttl$footnotes) %>%
  split_rows_by("PARAM",  page_by = FALSE) %>%
  split_rows_by("AVISIT", page_by = FALSE) %>%
  split_rows_by("block",  page_by = FALSE) %>%
  analyze("stat", afun = function(x) in_rows(.list = as.list(x)))
# tbl <- build_table(lyt, tab)   ## or gt::gt(tab) for HTML/Quarto
print(tab)
