################################################################################
# LISTING   : l_ecg  (Single Ascending Dose)
# TITLE     : Listing of Electrocardiogram (ECG) Results
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADEG
# NOTE      : PSEUDOCODE. One row per ECG assessment, ordered by dose cohort,
#             participant, parameter, then visit/timepoint. Shows observed value,
#             baseline, change, range indicator, and the overall ECG
#             interpretation. SAD: one treatment per participant; cohort column =
#             dv$trtvar (TRT01A = dose level), listing ordered ascending by
#             TRT01AN so cohorts read low -> high. Single dose -> no period column.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SAD")

eg <- adam$adeg %>% filter(SAFFL == "Y") %>%
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
    `Range Ind` = ANRIND,                            # LOW / NORMAL / HIGH
    `Interpretation` = if ("EGINTP" %in% names(adam$adeg)) EGINTP else NA_character_,  # overall read
    `Anl Flag`  = ANL01FL,
    ADT) %>%
  arrange(DoseN, Participant, PARAMCD, AVISITN, ATPTN, ADT)   # ascending dose, then numeric keys/date

ttl <- tfl_titles(num = "16.2.7.3", type = "Listing",
   text = "Listing of Electrocardiogram (ECG) Results",
   pop = "Safety Population",
   foot = "Sorted by ascending SAD dose cohort. Change = result - baseline. QTcF = Fridericia-corrected QT. Interpretation = investigator overall ECG read. Anl Flag = record used in by-visit summaries.")

## render: one block per dose cohort (page break), columns as ordered above
## listings::create_listing(eg, ...) or gt::gt(eg %>% select(-ADT, -PARAMCD, -AVISITN, -ATPTN, -DoseN))
print(eg %>% select(-ADT, -PARAMCD, -AVISITN, -ATPTN, -DoseN))
