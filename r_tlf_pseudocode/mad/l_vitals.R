################################################################################
# LISTING   : l_vitals  (Multiple Ascending Dose)
# TITLE     : Listing of Vital Signs
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADVS
# NOTE      : PSEUDOCODE. One row per vital-sign assessment, ordered by dose
#             cohort, participant, parameter, then visit/timepoint. Shows observed
#             value, baseline, change, and the analysis-range flag. MAD =
#             parallel dose cohorts with repeated dosing: one treatment per
#             participant; column = dv$trtvar (TRT01A = dose level). The dosing-day
#             (AVISIT) ordering carries the repeat-dose timeline within participant.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("MAD")

vs <- adam$advs %>% filter(SAFFL == "Y") %>%
  transmute(
    `Dose Cohort` = .data[[dv$trtvar]],              # TRT01A = dose level
    Participant       = str_extract(USUBJID, "[^-]+$"),  # short site-participant id
    Parameter     = PARAM,
    PARAMCD,
    Visit         = AVISIT,                           # Day 1 ... Day N ... follow-up
    AVISITN,
    Timepoint     = ATPT,
    ATPTN,
    `Result`      = AVAL,
    `Unit`        = AVALU,
    `Baseline`    = BASE,
    `Change`      = CHG,
    `Ref Range`   = if_else(!is.na(ANRLO) & !is.na(ANRHI),
                            sprintf("%g - %g", ANRLO, ANRHI), NA_character_),
    `Range Ind`   = ANRIND,                           # LOW / NORMAL / HIGH
    `Anl Flag`    = ANL01FL,
    ADT) %>%
  arrange(`Dose Cohort`, Participant, PARAMCD, AVISITN, ATPTN, ADT)  # sort on numeric keys/date

ttl <- tfl_titles(num = "16.2.7.4", type = "Listing", text = "Listing of Vital Signs",
   pop = "Safety Population",
   foot = paste("Change = result - baseline (baseline = last pre-first-dose value).",
                "Range Ind per analysis reference range. Anl Flag = record used in",
                "by-visit summaries. Visits span the repeat-dosing period."))

## render: one block per dose cohort (page break), columns as ordered above
## listings::create_listing(vs, ...) or gt::gt(vs %>% select(-ADT, -PARAMCD, -AVISITN, -ATPTN))
print(vs %>% select(-ADT, -PARAMCD, -AVISITN, -ATPTN))
