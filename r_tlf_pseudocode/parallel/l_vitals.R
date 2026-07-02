################################################################################
# LISTING   : l_vitals  (Parallel-group)
# TITLE     : Listing of Vital Signs
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADVS
# NOTE      : PSEUDOCODE. One row per vital-sign assessment, ordered by participant,
#             parameter, then visit/timepoint. Shows observed value, baseline,
#             change, and the analysis-range flag. Parallel: one treatment per
#             participant; column = dv$trtvar (TRT01A).
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("PARALLEL")

vs <- adam$advs %>% filter(SAFFL == "Y") %>%
  transmute(
    Treatment   = .data[[dv$trtvar]],
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
  arrange(Treatment, Participant, PARAMCD, AVISITN, ATPTN, ADT)   # sort on numeric keys/date

ttl <- tfl_titles(num = "16.2.8.2", type = "Listing", text = "Listing of Vital Signs",
   pop = "Safety Population",
   foot = "Change = result - baseline. Range Ind per analysis reference range. Anl Flag = record used in by-visit summaries.")

## render: one block per treatment (page break), columns as ordered above
## listings::create_listing(vs, ...) or gt::gt(vs %>% select(-ADT, -PARAMCD, -AVISITN, -ATPTN))
print(vs %>% select(-ADT, -PARAMCD, -AVISITN, -ATPTN))
