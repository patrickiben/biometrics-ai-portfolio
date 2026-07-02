################################################################################
# TABLE     : t_exposure  (Parallel-group)
# TITLE     : Extent of Study Drug Exposure
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADEX  (BDS: AVAL keyed by PARAMCD, one record per exposure param)
# NOTE      : PSEUDOCODE. Parallel-group: one treatment per participant, treatment
#             = TRT01A (= dose level for ascending-dose layouts). ADEX is the
#             long/BDS exposure dataset; per-participant exposure read from AVAL by
#             PARAMCD (DURD=duration days, TDOSE=cumulative dose, NDOSE=number of
#             doses, DOSINT=dose intensity %), matching the SAS twin. Do NOT
#             re-derive from raw EX (no sum(EXDOSE), no *DTC arithmetic).
#             Denominator = treated participants per arm (SAFFL=="Y").
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("PARALLEL")                 # -> trtvar = TRT01A, trtnvar = TRT01AN

## ADEX = analysis-derived exposure source (BDS: AVAL keyed by PARAMCD). Parallel
## has no period split. House rule: summarise the ADaM-derived AVAL per PARAMCD;
## do NOT re-derive from raw EX (no sum(EXDOSE), no *DTC arithmetic).
adex <- adam$adex %>%
  filter(SAFFL == "Y") %>%
  mutate(trt = .data[[dv$trtvar]])

## --- treated-participant denominators per arm + Total -------------------------
denom <- bign(adam$adsl, trtvar = dv$trtvar, popfl = "SAFFL")

## --- continuous exposure block: AVAL summarized per PARAMCD x arm -----------
## Subset ADEX to one exposure PARAMCD, then descstat on AVAL.
cont_block <- function(pcd, label, dp = 1L, ord) {
  descstat(adex %>% filter(PARAMCD == pcd), var = "AVAL", by = "trt", dp = dp) %>%
    transmute(trt, characteristic = label, ord = ord,
              `n`         = as.character(n),
              `Mean (SD)` = paste(c_mean, c_sd),
              `Median`    = c_median,
              `Min, Max`  = c_minmax) %>%
    pivot_longer(c(`n`,`Mean (SD)`,`Median`,`Min, Max`),
                 names_to = "stat", values_to = "value")
}
cont <- bind_rows(
  cont_block("DURD",   "Duration of exposure (days)", 1L, 1),
  cont_block("TDOSE",  "Cumulative dose (mg)",        1L, 2),
  cont_block("NDOSE",  "Number of doses received",    0L, 3),
  cont_block("DOSINT", "Dose intensity (%)",          1L, 4))

## --- categorical: exposure-duration thresholds n (%) (cumulative, matches SAS) -
## Distinct participants meeting each cumulative duration threshold (>=1/7/14 d).
dur_thresh <- function(min_days, label, ord) {
  sub <- adex %>% filter(PARAMCD == "DURD", AVAL >= min_days)
  per <- sub %>% group_by(trt) %>%
    summarise(nsubj = n_distinct(USUBJID), .groups = "drop")
  bind_rows(per, tibble(trt = "Total", nsubj = n_distinct(sub$USUBJID))) %>%
    right_join(denom, by = "trt") %>%
    mutate(nsubj = coalesce(nsubj, 0L),
           characteristic = "Exposure duration n (%)", ord = ord,
           stat = label, value = sprintf("%d (%.1f%%)", nsubj, 100 * nsubj / N)) %>%
    select(trt, characteristic, ord, stat, value)
}
dur_cat <- bind_rows(
  dur_thresh(1,  ">= 1 day",   5),
  dur_thresh(7,  ">= 7 days",  6),
  dur_thresh(14, ">= 14 days", 7))

## --- stack rows x treatment columns, render --------------------------------
tab <- bind_rows(cont, dur_cat) %>%
  pivot_wider(names_from = trt, values_from = value) %>%
  arrange(ord)

ttl <- tfl_titles(num = "14.1.4", type = "Table",
   text = "Extent of Study Drug Exposure",
   pop  = "Safety Population",
   foot = "Column = assigned treatment/dose level (TRT01A). Cumulative dose (TDOSE), duration (DURD, days), number of doses (NDOSE) and dose intensity (DOSINT, %) from ADEX AVAL by PARAMCD. Percentages based on Safety Population N per arm.")

lyt <- basic_table(title = ttl$titles[3], main_footer = ttl$footnotes) %>%
  split_rows_by("characteristic", page_by = FALSE) %>%
  analyze("stat", afun = function(x) in_rows(.list = as.list(x)))
# tbl <- build_table(lyt, tab)   ## or gt::gt(tab)
print(tab)
