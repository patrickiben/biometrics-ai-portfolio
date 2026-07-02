################################################################################
# LISTING   : l_vitals  (Single Ascending Dose)
# TITLE     : Listing of Vital Signs
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADVS
# NOTE      : PSEUDOCODE. One row per vital-sign assessment, ordered by dose
#             cohort, participant, parameter, then visit/timepoint. Shows observed
#             value, baseline, change, and the analysis-range flag. SAD: one
#             treatment per participant; cohort column = dv$trtvar (TRT01A = dose
#             level), listing ordered ascending by TRT01AN so cohorts read low ->
#             high. Single dose -> no period column.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SAD")

vs <- adam$advs %>% filter(SAFFL == "Y") %>%
  transmute(
    DoseN       = .data[[dv$trtnvar]],               # numeric dose for sort
    `Dose`      = .data[[dv$trtvar]],                # TRT01A = dose cohort label
    Participant     = str_extract(USUBJID, "[^-]+$"),    # short site-participant id
    Parameter   = PARAM,
    PARAMCD,
    Visit       = AVISIT,
    AVISITN,
    Timepoint   = ATPT,
    ATPTN,
    `Result`    = AVAL,
    `Unit`      = AVALU,
    `Baseline`  = BASE,
    `Change`    = CHG,
    `Ref Range` = if_else(!is.na(ANRLO) & !is.na(ANRHI),
                          sprintf("%g - %g", ANRLO, ANRHI), NA_character_),
    `Range Ind` = ANRIND,                            # LOW / NORMAL / HIGH
    `Anl Flag`  = ANL01FL,
    ADT) %>%
  arrange(DoseN, Participant, PARAMCD, AVISITN, ATPTN, ADT)   # ascending dose, then numeric keys/date

ttl <- tfl_titles(num = "16.2.7.4", type = "Listing", text = "Listing of Vital Signs",
   pop = "Safety Population",
   foot = "Sorted by ascending SAD dose cohort. Change = result - baseline. Range Ind per analysis reference range. Anl Flag = record used in by-visit summaries.")

## render: one block per dose cohort (page break), columns as ordered above
## listings::create_listing(vs, ...) or gt::gt(vs %>% select(-ADT, -PARAMCD, -AVISITN, -ATPTN, -DoseN))
print(vs %>% select(-ADT, -PARAMCD, -AVISITN, -ATPTN, -DoseN))
