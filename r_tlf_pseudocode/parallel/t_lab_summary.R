################################################################################
# TABLE     : t_lab_summary  (Parallel-group)
# TITLE     : Summary of Laboratory Values and Change from Baseline by Treatment
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADLB (PARAMCD/PARAM, AVAL, BASE, CHG, AVISIT/AVISITN, ANL01FL)
# NOTE      : PSEUDOCODE. Per parameter x scheduled visit: n, Mean (SD), Median,
#             Min-Max for the observed value (AVAL) AND change from baseline
#             (CHG). Columns = treatment arms (= dose level) + Total. Between-
#             group, parallel: descriptive only, no within-participant paired stats.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("PARALLEL")                 # column = TRT01A/TRT01AN (dose)

## one analysis record per participant/param/visit (ANL01FL keeps the chosen reading)
lb <- adam$adlb %>%
  filter(SAFFL == "Y", ANL01FL == "Y",
         PARAMCD %in% c("ALT","AST","BILI","ALP","CREAT","BUN","GLUC",
                        "K","NA","HGB","WBC","PLAT","NEUT")) %>%
  mutate(trt = .data[[dv$trtvar]])

## column denominators (N=) per arm + Total, from one-row-per-participant ADSL
denom <- bign(adam$adsl, trtvar = dv$trtvar, popfl = "SAFFL")

## --- descriptive block: reuse descstat() for AVAL then CHG -----------------
## by = param, visit (ordered by AVISITN), treatment. Baseline visit CHG omitted.
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

## --- stack: parameter -> visit -> measure -> statistic rows x arm columns ---
tab <- bind_rows(aval, chg) %>%
  arrange(PARAM, AVISITN, factor(measure, c("Observed Value","Change from Baseline")), stat) %>%
  select(PARAM, AVISIT, measure, stat, trt, value) %>%
  pivot_wider(names_from = trt, values_from = value)

ttl <- tfl_titles(num = "14.3.4.1", type = "Table",
   text = "Summary of Laboratory Values and Change from Baseline by Treatment",
   pop  = "Safety Population",
   foot = paste("Descriptive statistics by scheduled visit; parallel-group analysis is",
                "between-arm and descriptive only. SI units. Baseline = last value",
                "on/before first dose; change = post-baseline - baseline."))

## rtables layout: PARAM -> AVISIT -> measure split, statistic rows x arm columns
lyt <- basic_table(title = ttl$titles[3], main_footer = ttl$footnotes) %>%
  split_rows_by("PARAM",   page_by = TRUE) %>%
  split_rows_by("AVISIT")  %>%
  split_rows_by("measure") %>%
  analyze("stat", afun = function(x) in_rows(.list = as.list(x)))
# tbl <- build_table(lyt, tab)   ## or gt::gt(tab)
print(tab)
