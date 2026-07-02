################################################################################
# TABLE     : t_lab_summary  (Crossover - 2x2 or Williams)
# TITLE     : Summary of Laboratory Values and Changes from Baseline
#             by Treatment and Period
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADLB (PARAMCD = lab analytes; AVAL, CHG, BASE, AVISIT, ANRIND)
# NOTE      : PSEUDOCODE. Continuous lab summary: n, Mean (SD), Median, Min-Max
#             for AVAL and CHG by analyte x visit. Crossover: within-participant, so
#             columns are by ACTUAL treatment (dv$trtvar = TRTA); period shown as
#             a row split (dv$byperiod = APERIOD/APERIODC) so the same participant
#             appears under each treatment they received. Denominators per
#             treatment column come from bign() on the Safety Population.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("CROSSOVER")                 # trtvar = TRTA ; byperiod = APERIOD/APERIODC

## --- analytes / units of interest (driven off ADLB PARAMCD) ----------------
analytes <- c("ALT","AST","BILI","ALP","CREAT","BUN","GLUC","HGB","WBC","PLAT","K","NA")

lb <- adam$adlb %>%
  filter(SAFFL == "Y", PARAMCD %in% analytes, !is.na(AVAL)) %>%
  mutate(trt    = .data[[dv$trtvar]],
         period = .data[[dv$byperiod[2]]],          # APERIODC label (Period 1/2/...)
         visit  = AVISIT)

## column denominators (N=) per treatment + Total, Safety Population
## (participant-level N; the same participant is counted under each treatment received)
denom <- bign(adam$adsl %>%
                ## expand ADSL to one row per participant x treatment via ADLB linkage
                semi_join(lb, by = "USUBJID") %>%
                left_join(distinct(lb, USUBJID, !!sym(dv$trtvar)), by = "USUBJID"),
              trtvar = dv$trtvar, popfl = "SAFFL")

## --- descriptive block: AVAL and CHG, by analyte x period x visit x trt -----
sum_block <- function(var, var_label, dp = 1L) {
  descstat(lb, var = var, by = c("PARAM","period","visit","trt"), dp = dp) %>%
    transmute(PARAM, period, visit, trt, measure = var_label,
              `n`              = as.character(n),
              `Mean (SD)`      = paste(c_mean, c_sd),
              `Median`         = c_median,
              `Min, Max`       = c_minmax) %>%
    pivot_longer(c(`n`,`Mean (SD)`,`Median`,`Min, Max`),
                 names_to = "stat", values_to = "value")
}

tab_long <- bind_rows(
  sum_block("AVAL", "Observed Value", dp = 1L),
  sum_block("CHG",  "Change from Baseline", dp = 1L)
)

## one column per treatment; rows = analyte > period > visit > measure > stat
tab <- tab_long %>%
  pivot_wider(names_from = trt, values_from = value) %>%
  arrange(PARAM, period, visit, measure, stat)

ttl <- tfl_titles(num = "14.3.4.1", type = "Table",
   text = "Summary of Laboratory Values and Changes from Baseline by Treatment and Period",
   pop  = "Safety Population",
   foot = "Crossover design: columns are by actual treatment received; periods shown within each analyte. Each participant contributes to every treatment received. SI/conventional units per ADLB. Source: ADLB.")

## rtables layout (regulatory): analyte > period > visit > measure, treatment cols
lyt <- basic_table(title = ttl$titles[3], main_footer = ttl$footnotes) %>%
  split_rows_by("PARAM",   page_by = TRUE) %>%
  split_rows_by("period",  page_by = FALSE) %>%
  split_rows_by("visit",   page_by = FALSE) %>%
  split_rows_by("measure", page_by = FALSE) %>%
  analyze("stat", afun = function(x) in_rows(.list = as.list(x)))
# tbl <- build_table(lyt, tab)   ## or gt::gt(tab) for HTML/Quarto rendering
print(tab)
