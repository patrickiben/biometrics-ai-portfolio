################################################################################
# TABLE     : t_lab_summary  (Single Ascending Dose)
# TITLE     : Summary of Laboratory Values and Change from Baseline by Dose Level
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADLB (PARAMCD/PARAM, AVAL, BASE, CHG, AVISIT/AVISITN, ANL01FL)
# NOTE      : PSEUDOCODE. SAD = parallel dose cohorts; the column variable is the
#             actual treatment = DOSE LEVEL (dv$trtvar = TRT01A), with placebo
#             commonly pooled across cohorts. Single dose -> no steady-state /
#             accumulation; analysis is between-cohort and DESCRIPTIVE only (no
#             within-participant paired stats). Per parameter x scheduled visit:
#             n, Mean (SD), Median, Min-Max for observed value (AVAL) AND change
#             from baseline (CHG). Columns = dose levels (+ pooled placebo) + Total.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SAD")                      # column = TRT01A/TRT01AN (dose level)

## one analysis record per participant/param/visit (ANL01FL keeps the chosen reading)
lb <- adam$adlb %>%
  filter(SAFFL == "Y", ANL01FL == "Y",
         PARAMCD %in% c("ALT","AST","BILI","ALP","CREAT","BUN","GLUC",
                        "K","NA","HGB","WBC","PLAT","NEUT")) %>%
  mutate(trt = .data[[dv$trtvar]])             # dose-level column (placebo pooled upstream)

## column denominators (N=) per dose level + Total, from one-row-per-participant ADSL
## (participant-level safety table -> ADSL is the correct denominator source for SAD)
denom <- bign(adam$adsl, trtvar = dv$trtvar, popfl = "SAFFL")

## --- descriptive block: reuse descstat() for AVAL then CHG -----------------
## by = param, visit (ordered by AVISITN), dose level. Baseline visit CHG omitted.
lab_block <- function(var, statset_label) {
  descstat(lb, var = var, by = c("PARAMCD","PARAM","AVISITN","AVISIT", dv$trtvar)) %>%
    transmute(PARAMCD, PARAM, AVISITN, AVISIT, trt = .data[[dv$trtvar]],
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

## --- stack: parameter -> visit -> measure -> statistic rows x dose columns ---
## NB: dose columns should render in ascending dose order (TRT01AN), placebo first.
tab <- bind_rows(aval, chg) %>%
  arrange(PARAM, AVISITN, factor(measure, c("Observed Value","Change from Baseline")), stat) %>%
  select(PARAM, AVISIT, measure, stat, trt, value) %>%
  pivot_wider(names_from = trt, values_from = value)

ttl <- tfl_titles(num = "14.3.4.1", type = "Table",
   text = "Summary of Laboratory Values and Change from Baseline by Dose Level",
   pop  = "Safety Population",
   foot = paste("Descriptive statistics by scheduled visit; SAD dose cohorts are",
                "analysed between-cohort and descriptively only (single dose -> no",
                "accumulation). Columns ordered by ascending dose (placebo pooled).",
                "SI units. Baseline = last value on/before dose; change = post - baseline."))

## rtables layout: PARAM -> AVISIT -> measure split, statistic rows x dose columns
lyt <- basic_table(title = ttl$titles[3], main_footer = ttl$footnotes) %>%
  split_rows_by("PARAM",   page_by = TRUE) %>%
  split_rows_by("AVISIT")  %>%
  split_rows_by("measure") %>%
  analyze("stat", afun = function(x) in_rows(.list = as.list(x)))
# tbl <- build_table(lyt, tab)   ## or gt::gt(tab)
print(tab)
