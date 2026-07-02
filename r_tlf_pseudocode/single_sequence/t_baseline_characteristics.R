################################################################################
# TABLE     : t_baseline_characteristics  (Single-/Fixed-Sequence DDI)
# TITLE     : Baseline Disease and Clinical Characteristics
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADSL (participant-level baseline *BL variables; categorical groups)
# NOTE      : PSEUDOCODE. Baseline = pre-first-dose (Period 1 baseline = the
#             single study baseline before the victim-alone period). PARTICIPANT-
#             LEVEL table -> columns = the ONE fixed sequence (dv$seqvar). NO
#             per-period split (baseline is a single pre-treatment state).
#             Continuous baselines come from the ADSL *BL variables (EGFRBL,
#             SYSBPBL, DIABPBL, QTCFBL) -- same source/analyte set as the SAS
#             twin; eGFR and QTcF are retained for the renal/DDI design. The
#             DDI-relevant CYP metabolizer phenotype (CYPPHENO) block is included.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SINGLESEQ")                 # seqvar = TRTSEQP, seqvarn = TRTSEQPN
options(tfl.study = env$study)

adsl <- adam$adsl %>% filter(SAFFL == "Y")      # one row per participant

## column denominators (N=) per fixed sequence + Total (participant-level)
denom <- bign(adsl, trtvar = dv$seqvar, popfl = "SAFFL")

## --- baseline continuous from ADSL *BL variables (same source as SAS) -------
## Use the participant-level ADSL baseline variables, NOT a re-pull of the raw
## BDS domains, so the continuous source strategy matches the SAS twin.
cont_lab <- tribble(
  ~var,       ~label,                              ~dp, ~ord,
  "EGFRBL",   "Baseline eGFR (mL/min/1.73m^2)",    1L,  1,
  "SYSBPBL",  "Baseline Systolic BP (mmHg)",       1L,  2,
  "DIABPBL",  "Baseline Diastolic BP (mmHg)",      1L,  3,
  "QTCFBL",   "Baseline QTcF (msec)",              1L,  4)

cont_block <- function(var, label, dp, ord) {
  adsl %>% descstat(var = var, by = dv$seqvar, dp = dp) %>%
    transmute(seq = .data[[dv$seqvar]], characteristic = label, ord,
              `n`         = as.character(n),
              `Mean (SD)` = paste(c_mean, c_sd),
              `Median`    = c_median,
              `Min, Max`  = c_minmax) %>%
    pivot_longer(c(`n`,`Mean (SD)`,`Median`,`Min, Max`), names_to = "stat", values_to = "value")
}
cont <- pmap_dfr(cont_lab, function(var, label, dp, ord)
  cont_block(var, label, dp, ord))

## --- categorical baseline: renal group, hepatic group, smoking, CYP phenotype
## ADSL baseline grouping variables (no re-derivation; come from ADaM). Variable
## names reconciled to the SAS convention (RENALGR1/HEPATGR1). CYPPHENO added to
## match the SAS twin (DDI-relevant metabolizer phenotype).
cat_block <- function(var, label, ord) {
  catfreq(adsl, var = var, by = dv$seqvar, denom = denom) %>%
    transmute(seq = .data[[dv$seqvar]], characteristic = label, ord, stat = cat, value = disp)
}
catg <- bind_rows(
  cat_block("RENALGR1", "Baseline renal function n (%)",   5),
  cat_block("HEPATGR1", "Baseline hepatic function n (%)", 6),
  cat_block("SMOKSTAT", "Smoking status n (%)",            7),
  cat_block("CYPPHENO", "CYP metabolizer phenotype n (%)", 8))   # DDI-relevant

## --- stack, one column per fixed sequence, render -------------------------
tab <- bind_rows(cont, catg) %>%
  pivot_wider(names_from = seq, values_from = value) %>%
  arrange(ord)

ttl <- tfl_titles(num = "14.1.3", type = "Table",
   text = "Baseline Disease and Clinical Characteristics",
   pop  = "Safety Population",
   foot = paste("Baseline = last assessment prior to first dose (single study",
                "baseline before the Period 1 victim-alone treatment). CYP",
                "phenotype shown given relevance to the drug-drug interaction",
                "assessment. Percentages based on Safety Population N per sequence."))

lyt <- basic_table(title = ttl$titles[3], main_footer = ttl$footnotes) %>%
  split_rows_by("characteristic", page_by = FALSE) %>%
  analyze("stat", afun = function(x) in_rows(.list = as.list(x)))
# tbl <- build_table(lyt, tab)   ## or gt::gt(tab)
print(tab)
