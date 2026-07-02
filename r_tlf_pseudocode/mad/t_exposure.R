################################################################################
# TABLE     : t_exposure  (Multiple Ascending Dose)
# TITLE     : Extent of Study Drug Exposure by Dose Cohort
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADEX  (one analysis record per participant; analysis vars AVAL/TRTDURD/NDOSES)
# NOTE      : PSEUDOCODE. MAD = parallel dose cohorts, REPEATED daily dosing over
#             a multi-day regimen (e.g. Day 1 ... Day N). Column = DOSE LEVEL
#             (TRT01A), placebo pooled + Total. Per-participant exposure summarized
#             from ADaM-derived analysis vars (total cumulative dose = AVAL,
#             treatment duration = TRTDURD, # doses = NDOSES); compliance n (%).
#             Do NOT re-derive from raw EX (no sum(EXDOSE), no *DTC arithmetic).
#             Denominator = participants dosed per cohort from ADEX (SAFFL=="Y"),
#             NOT one-row-per-participant ADSL.
#
#             MAD-SPECIFIC PK (separate scripts, by ADaM domain):
#               - t_accumulation.R          : ADPP -> Rac = geomean of within-
#                                             participant Day N / Day 1 (Cmax, AUCtau);
#                                             paired on the LOG scale.
#               - t_steady_state.R          : ADPC pre-dose troughs (ATPT="Pre-
#                                             dose") across dosing days -> trough
#                                             trend; optional lmer log-linear slope
#                                             with 95% CI (steady state if CI
#                                             includes 0).
#               - t_dose_proportionality.R  : ADPP at steady state (Day N AUCtau,
#                                             Cmax,ss) -> power model lm(log(AVAL)~
#                                             log(dose)); slope ~ 1 => proportional.
#             This exposure table feeds those analyses the per-cohort dosed N and
#             documents the regimen each PK day was sampled under.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("MAD")                       # -> trtvar = TRT01A (dose level), trtnvar = TRT01AN

## ADEX = analysis-derived exposure source: one analysis record per participant
## carrying the per-participant analysis vars. MAD has no within-participant period
## split (one dose level per participant). House rule: summarise ADaM-derived
## analysis vars (total dose = AVAL, duration = TRTDURD, # doses = NDOSES);
## do NOT re-derive from raw EX (no sum(EXDOSE), no *DTC arithmetic).
adex <- adam$adex %>%
  filter(SAFFL == "Y") %>%
  mutate(
    dose_col = if_else(toupper(.data[[dv$trtvar]]) == "PLACEBO" | .data[[dv$trtnvar]] == 0,
                       "Placebo", .data[[dv$trtvar]]),
    dose_ord = if_else(toupper(.data[[dv$trtvar]]) == "PLACEBO" | .data[[dv$trtnvar]] == 0,
                       0, .data[[dv$trtnvar]]),
    trt = dose_col)

## --- treated-participant denominators per cohort + Total (from ADEX) ----------
## House rule: dosed-N comes from the period/dosing-bearing source (ADEX).
denom <- adex %>%
  group_by(trt) %>%
  summarise(N = n_distinct(USUBJID), .groups = "drop") %>%
  bind_rows(tibble(trt = "Total", N = n_distinct(adex$USUBJID)))

## --- continuous exposure block (ADaM analysis vars) -----------------------
cont_block <- function(var, label, dp = 1L, ord) {
  descstat(adex, var = var, by = "trt", dp = dp) %>%
    transmute(trt, characteristic = label, ord = ord,
              `n`         = as.character(n),
              `Mean (SD)` = paste(c_mean, c_sd),
              `Median`    = c_median,
              `Min, Max`  = c_minmax) %>%
    pivot_longer(c(`n`,`Mean (SD)`,`Median`,`Min, Max`),
                 names_to = "stat", values_to = "value")
}
cont <- bind_rows(
  cont_block("AVAL",    "Total Cumulative Dose (mg)",   1L, 1),
  cont_block("TRTDURD", "Duration of Exposure (days)",  0L, 2),
  cont_block("NDOSES",  "Number of Administrations",    0L, 3))

## --- categorical: planned dose level n (%) (TRT01A = MAD dose cohort) ------
dose_cat <- catfreq(adex, var = "trt", by = "trt", denom = denom) %>%
  transmute(trt, characteristic = "Dose Level n (%)", ord = 4,
            stat = cat, value = disp)

## --- categorical: regimen-completion / compliance bands n (%) -------------
## MAD participants must complete the full multi-day regimen for steady-state PK.
## EXCMPLPC = ADaM-derived overall % of planned doses taken (one per participant).
comp <- adex %>%
  group_by(USUBJID, trt = dose_col) %>%
  summarise(cmpl = mean(EXCMPLPC, na.rm = TRUE), .groups = "drop") %>%
  mutate(comp_cat = case_when(
           is.nan(cmpl)               ~ "Missing",
           cmpl >= 80 & cmpl <= 120   ~ "Compliant (80-120%)",
           TRUE                       ~ "Non-compliant")) %>%
  group_by(trt, characteristic = "Dosing Compliance n (%)", stat = comp_cat) %>%
  summarise(n = n_distinct(USUBJID), .groups = "drop") %>%
  bind_rows(.,
    {  ## add Total column for each compliance category
      group_by(., stat) %>% summarise(n = sum(n), .groups = "drop") %>%
        mutate(trt = "Total", characteristic = "Dosing Compliance n (%)")
    }) %>%
  left_join(denom, by = "trt") %>%
  mutate(value = n_pct(n, N), ord = 5L) %>%
  select(trt, characteristic, ord, stat, value)

## --- stack rows x dose-cohort columns, render ------------------------------
tab <- bind_rows(cont, dose_cat, comp) %>%
  pivot_wider(names_from = trt, values_from = value) %>%
  arrange(ord)

ttl <- tfl_titles(num = "14.1.4", type = "Table",
   text = "Extent of Study Drug Exposure by Dose Cohort",
   pop  = "Safety Population",
   foot = paste("MAD: repeated daily dosing; columns = ascending dose cohorts (TRT01A) with placebo pooled.",
                "Denominator = participants dosed per cohort (ADEX, SAFFL=='Y').",
                "Exposure from ADaM-derived analysis vars: total cumulative dose = AVAL,",
                "duration = TRTDURD (days), number of administrations = NDOSES. Compliance = administered / planned doses.",
                "Accumulation (Rac), steady-state trough trend and steady-state dose-proportionality",
                "are reported in t_accumulation.R / t_steady_state.R / t_dose_proportionality.R (ADPP/ADPC)."))

lyt <- basic_table(title = ttl$titles[3], main_footer = ttl$footnotes) %>%
  split_rows_by("characteristic", page_by = FALSE) %>%
  analyze("stat", afun = function(x) in_rows(.list = as.list(x)))
# tbl <- build_table(lyt, tab)   ## or gt::gt(tab)
print(tab)
