################################################################################
# TABLE     : t_lab_summary  (Multiple Ascending Dose)
# TITLE     : Summary of Laboratory Values and Change from Baseline by Dose Level
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADLB (PARAMCD/PARAM, AVAL, BASE, CHG, AVISIT/AVISITN, ADY, ANL01FL)
# NOTE      : PSEUDOCODE. MAD = parallel dose cohorts with REPEATED dosing; the
#             column variable is the actual treatment = DOSE LEVEL
#             (dv$trtvar = TRT01A), with placebo commonly pooled across cohorts.
#             Because dosing is repeated, scheduled visits span the full dosing
#             period (e.g. Day 1, Day 7, Day 14 ... last dose / steady state) plus
#             follow-up; the summary is presented over ALL on-treatment visits so
#             a trend across dosing days is visible. Analysis is between-cohort and
#             DESCRIPTIVE only (no within-participant paired inferential stats here).
#             Per parameter x scheduled visit: n, Mean (SD), Median, Min-Max for
#             observed value (AVAL) AND change from baseline (CHG). Columns =
#             dose levels (+ pooled placebo) + Total.
#             [Companion PK: steady-state PK summarised in t_pk_param_summary;
#              accumulation in t_accumulation; dose-proportionality at steady
#              state in t_dose_proportionality (MAD).]
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("MAD")                      # column = TRT01A/TRT01AN (dose level)

## one analysis record per participant/param/visit (ANL01FL keeps the chosen reading);
## MAD scheduled visits include multiple on-treatment dosing days -> trend visible
lb <- adam$adlb %>%
  filter(SAFFL == "Y", ANL01FL == "Y",
         PARAMCD %in% c("ALT","AST","BILI","ALP","CREAT","BUN","GLUC",
                        "K","NA","HGB","WBC","PLAT","NEUT")) %>%
  mutate(trt = .data[[dv$trtvar]])             # dose-level column (placebo pooled upstream)

## column denominators (N=) per dose level + Total, from one-row-per-participant ADSL
## (participant-level safety summary -> ADSL is the correct denominator source;
##  per-PERIOD/per-dosing-day exposure denominators, where needed elsewhere,
##  come from ADEX, never from ADSL.)
denom <- bign(adam$adsl, trtvar = dv$trtvar, popfl = "SAFFL")

## --- descriptive block: reuse descstat() for AVAL then CHG -----------------
## by = param, visit (ordered by AVISITN across all dosing days), dose level.
## Baseline visit CHG omitted.
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

## --- stack: parameter -> visit (dosing-day order) -> measure -> stat rows ----
## NB: dose columns render in ascending dose order (TRT01AN), placebo first;
##     visit rows render in chronological order via AVISITN so the across-day
##     (repeated-dose) trend reads top to bottom.
tab <- bind_rows(aval, chg) %>%
  arrange(PARAM, AVISITN, factor(measure, c("Observed Value","Change from Baseline")), stat) %>%
  select(PARAM, AVISIT, measure, stat, trt, value) %>%
  pivot_wider(names_from = trt, values_from = value)

ttl <- tfl_titles(num = "14.3.4.1", type = "Table",
   text = "Summary of Laboratory Values and Change from Baseline by Dose Level",
   pop  = "Safety Population",
   foot = paste("Descriptive statistics by scheduled visit across the repeated-dosing",
                "period (MAD); cohorts analysed between-cohort and descriptively only.",
                "Columns ordered by ascending dose (placebo pooled). SI units.",
                "Baseline = last value on/before first dose; change = post - baseline."))

## rtables layout: PARAM -> AVISIT -> measure split, statistic rows x dose columns
lyt <- basic_table(title = ttl$titles[3], main_footer = ttl$footnotes) %>%
  split_rows_by("PARAM",   page_by = TRUE) %>%
  split_rows_by("AVISIT")  %>%
  split_rows_by("measure") %>%
  analyze("stat", afun = function(x) in_rows(.list = as.list(x)))
# tbl <- build_table(lyt, tab)   ## or gt::gt(tab)
print(tab)
