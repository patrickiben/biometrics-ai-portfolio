################################################################################
# TABLE     : t_pd_summary  (Parallel-group)
# TITLE     : Summary of Pharmacodynamic / Biomarker Endpoints by Treatment and
#             Visit
# POPULATION: PD-Evaluable Population (PDFL == "Y")
# INPUT     : ADPD (PARAMCD = PD biomarker codes; AVAL, CHG, PCHG, BASE,
#             AVISIT/AVISITN, ATPT/ATPTN)
# NOTE      : PSEUDOCODE. Continuous descriptive stats by treatment x visit:
#             n, Mean (SD), Median, Min-Max for AVAL, CHG and %CHG. Parallel-
#             group: one treatment per participant -> column = dv$trtvar (TRT01A,
#             = dose level for ascending-dose layouts). Per-VISIT denominators
#             come from ADPD (PD-evaluable participants with a value at the visit),
#             NEVER one-row-per-participant ADSL.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("PARALLEL")                 # column = TRT01A (= dose)

## one PD parameter per run (parameterize PARAMCD; loop/purrr in production)
PDCD <- "INHIB"                                # e.g. target % inhibition / biomarker
pd <- adam$adpd %>%
  filter(PDFL == "Y", PARAMCD == PDCD) %>%
  mutate(visit = factor(AVISIT, levels = unique(AVISIT[order(AVISITN)])))

by <- c(dv$trtvar, "PARAM", "visit")

## --- per-visit denominators from a period-/visit-bearing source (ADPD) ------
## participants PD-evaluable WITH a value at each treatment x visit (NOT ADSL)
denom_v <- pd %>%
  filter(!is.na(AVAL)) %>%
  group_by(trt = .data[[dv$trtvar]], visit) %>%
  summarise(N = n_distinct(USUBJID), .groups = "drop")

## --- descriptive stats for AVAL, CHG, %CHG ---------------------------------
stat_block <- function(var, label, dp = 2L) {
  descstat(pd, var = var, by = by, dp = dp) %>%
    transmute(trt = .data[[dv$trtvar]], PARAM, visit, measure = label,
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

## --- header N= per treatment x visit (from ADPD denom, not ADSL) -----------
hdr <- denom_v %>% mutate(coln = sprintf("%s (N=%d)", trt, N))

## --- stack: measure/stat rows x treatment-visit columns --------------------
tab <- body %>%
  unite("colkey", trt, visit, sep = " | ", remove = FALSE) %>%
  select(PARAM, measure, stat, colkey, value) %>%
  pivot_wider(names_from = colkey, values_from = value)

ttl <- tfl_titles(num = "14.4.6.1", type = "Table",
   text = "Summary of Pharmacodynamic Endpoints by Treatment and Visit",
   pop  = "Pharmacodynamic-Evaluable Population",
   foot = paste("Descriptive only; no formal between-group test at this level.",
                "Per-visit N from PD-evaluable participants with a value (ADPD).",
                "CHG/%CHG relative to ADaM BASE. Parameter:", PDCD))

## rtables layout: measure (block) -> statistic rows x treatment-visit columns
lyt <- basic_table(title = ttl$titles[3], main_footer = ttl$footnotes) %>%
  split_rows_by("measure", page_by = FALSE) %>%
  analyze("stat", afun = function(x) in_rows(.list = as.list(x)))
# tbl <- build_table(lyt, tab)        ## or gt::gt(tab)
print(tab)
