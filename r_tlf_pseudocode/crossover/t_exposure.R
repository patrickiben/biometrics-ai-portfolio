################################################################################
# TABLE     : t_exposure  (Crossover - 2x2 / Williams)
# TITLE     : Extent of Study Drug Exposure by Treatment and Period
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADEX  (one analysis record per participant per APERIOD; AVAL/TRTDURD/NDOSES)
# NOTE      : PSEUDOCODE. PERIOD-BEARING table. In a crossover each participant is
#             exposed to a different TREATMENT in each PERIOD, so exposure is
#             summarized by TRTA (the actual treatment received that period) and
#             optionally by APERIOD. Exposure from ADaM-derived analysis vars
#             (total dose = AVAL, duration = TRTDURD, # doses = NDOSES); do NOT
#             re-derive from raw EX (no sum(EXDOSE), no *DTC arithmetic).
#             Denominators come from ADEX (participants dosed per period where
#             SAFFL=="Y"), NOT one-row-per-participant ADSL. Counts of participants =
#             distinct USUBJID; dose/duration stats are continuous.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("CROSSOVER")   # trtvar = TRTA, byperiod = APERIOD/APERIODC

## ADEX: one analysis record per participant*period carrying the per-period analysis
## vars. House rule: summarise ADaM-derived analysis vars (total dose = AVAL,
## duration = TRTDURD, # doses = NDOSES); do NOT re-derive from raw EX
## (no sum(EXDOSE), no *DTC arithmetic).
ex <- adam$adex %>% filter(SAFFL == "Y") %>%
  mutate(trt = .data[[dv$trtvar]], per = .data[[dv$byperiod[2]]])   # TRTA / APERIODC

## --- period denominators: participants DOSED per treatment (and per period) -----
## period-bearing source = ADEX, never ADSL.
denom_trt <- ex %>% group_by(trt) %>%
  summarise(N = n_distinct(USUBJID), .groups = "drop") %>%
  bind_rows(tibble(trt = "Total", N = n_distinct(ex$USUBJID)))

## --- participants exposed (n) per treatment -------------------------------------
n_exposed <- ex %>% group_by(trt) %>%
  summarise(nsubj = n_distinct(USUBJID), .groups = "drop") %>%
  left_join(denom_trt, by = "trt") %>%
  transmute(trt, characteristic = "Participants dosed", ord = 1,
            stat = "n (%)", value = n_pct(nsubj, N))

## --- continuous exposure: total dose & duration, by TREATMENT ---------------
cont_block <- function(var, label, dp, ord) {
  descstat(ex, var = var, by = "trt", dp = dp) %>%
    transmute(trt, characteristic = label, ord,
              `n`         = as.character(n),
              `Mean (SD)` = paste(c_mean, c_sd),
              `Median`    = c_median,
              `Min, Max`  = c_minmax) %>%
    pivot_longer(c(`n`,`Mean (SD)`,`Median`,`Min, Max`), names_to = "stat", values_to = "value")
}
cont <- bind_rows(
  cont_block("AVAL",    "Total dose (mg)",          1L, 2),
  cont_block("TRTDURD", "Duration of exposure (d)", 0L, 3),
  cont_block("NDOSES",  "Number of doses",          0L, 4))

tab <- bind_rows(n_exposed, cont) %>%
  select(characteristic, ord, stat, trt, value) %>%
  pivot_wider(names_from = trt, values_from = value) %>%
  arrange(ord)

## --- optional companion: participants dosed BY PERIOD (period-bearing denoms) ----
## demonstrates dv$byperiod usage; ADEX gives per-period N directly.
by_period <- ex %>% group_by(per) %>%
  summarise(nsubj = n_distinct(USUBJID), .groups = "drop") %>%
  transmute(per, `Participants dosed in period` = as.character(nsubj))

ttl <- tfl_titles(num = "14.1.4", type = "Table",
   text = "Extent of Study Drug Exposure by Treatment",
   pop  = "Safety Population",
   foot = "Each participant contributes exposure under EACH treatment received (within-participant crossover). Exposure from ADaM-derived analysis vars: total dose = AVAL, duration = TRTDURD (days), # doses = NDOSES. Denominators = participants dosed per treatment (ADEX), not ADSL.")

print(tab)
print(by_period)   # companion per-period exposure counts (dv$byperiod)
