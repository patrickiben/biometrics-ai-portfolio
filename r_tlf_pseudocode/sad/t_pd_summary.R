################################################################################
# TABLE     : t_pd_summary  (Single Ascending Dose)
# TITLE     : Summary of Pharmacodynamic / Biomarker Endpoints by Dose Level and
#             Visit
# POPULATION: PD-Evaluable Population (PDFL == "Y")
# INPUT     : ADPD (PARAMCD = PD biomarker codes; AVAL, CHG, PCHG, BASE,
#             AVISIT/AVISITN, ATPT/ATPTN)
# NOTE      : PSEUDOCODE. Continuous descriptive stats by DOSE LEVEL x visit:
#             n, Mean (SD), Median, Min-Max for AVAL, CHG and %CHG. SAD =
#             parallel cohorts, one dose per participant -> column = dv$trtvar
#             (TRT01A = dose level), placebo often pooled across cohorts. Single
#             dose -> no accumulation; visits span the single-dose PD time
#             course. ALL PD PARAMCD are summarized (looped, like the SAS twin),
#             not a single parameter. Header N= per dose column comes from the
#             ADSL PDFL flag via bign() -- the SAME header-N source as the SAS
#             twin. Descriptive only; no inferential PD/dose model (kept parallel
#             to the SAS twin).
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SAD")                      # column = TRT01A (= dose level)

## all PD parameters (loop over every PARAMCD in ADPD, like the SAS twin)
pd <- adam$adpd %>%
  filter(PDFL == "Y") %>%
  mutate(visit = factor(AVISIT, levels = unique(AVISIT[order(AVISITN)])))

by <- c(dv$trtvar, "PARAM", "PARAMCD", "visit")

## --- header denominators: N per dose column from ADSL PDFL (bign), as SAS ---
denom <- bign(adam$adsl, trtvar = dv$trtvar, popfl = "PDFL")  # PD-population N per dose

## --- descriptive stats for AVAL, CHG, %CHG ---------------------------------
stat_block <- function(var, label, dp = 2L) {
  descstat(pd, var = var, by = by, dp = dp) %>%
    transmute(trt = .data[[dv$trtvar]], PARAM, PARAMCD, visit, measure = label,
              `n`         = as.character(n),
              `Mean (SD)` = paste(c_mean, c_sd),
              `Median`    = c_median,
              `Min, Max`  = c_minmax) %>%
    pivot_longer(c(`n`,`Mean (SD)`,`Median`,`Min, Max`),
                 names_to = "stat", values_to = "value")
}

body <- bind_rows(
  stat_block("AVAL", "Observed value",        2L),
  stat_block("CHG",  "Change from baseline",  2L),
  stat_block("PCHG", "% change from baseline",1L))

## --- stack: parameter/measure/stat rows x dose-visit columns ----------------
tab <- body %>%
  unite("colkey", trt, visit, sep = " | ", remove = FALSE) %>%
  select(PARAM, measure, stat, colkey, value) %>%
  pivot_wider(names_from = colkey, values_from = value)

ttl <- tfl_titles(num = "14.4.6.1", type = "Table",
   text = "Summary of Pharmacodynamic Endpoints by Dose Level and Visit",
   pop  = "Pharmacodynamic-Evaluable Population",
   foot = paste("Descriptive only; no formal between-cohort test.",
                "Header N (per dose) = PD population from ADSL PDFL.",
                "Single ascending dose: columns = dose level (placebo pooled).",
                "CHG/%CHG relative to ADaM BASE. All PD PARAMCD summarized."))

## rtables layout: measure (block) -> statistic rows x dose-level x visit columns
lyt <- basic_table(title = ttl$titles[3], main_footer = ttl$footnotes) %>%
  split_rows_by("measure", page_by = FALSE) %>%
  analyze("stat", afun = function(x) in_rows(.list = as.list(x)))
# tbl <- build_table(lyt, tab)        ## or gt::gt(tab)
print(tab)
