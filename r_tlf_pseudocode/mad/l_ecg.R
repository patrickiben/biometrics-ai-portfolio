################################################################################
# LISTING   : l_ecg  (Multiple Ascending Dose)
# TITLE     : Listing of Electrocardiogram (ECG) Results
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADEG
# NOTE      : PSEUDOCODE. One row per ECG assessment, ordered by dose cohort,
#             participant, parameter, then visit/timepoint. Shows observed value,
#             baseline, change, range indicator, and the overall ECG
#             interpretation. MAD = parallel dose cohorts with repeated dosing:
#             one treatment per participant; column = dv$trtvar (TRT01A = dose level).
#             The dosing-day (AVISIT) ordering carries the repeat-dose timeline.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("MAD")

eg <- adam$adeg %>% filter(SAFFL == "Y") %>%
  transmute(
    `Dose Cohort`    = .data[[dv$trtvar]],            # TRT01A = dose level
    Participant          = str_extract(USUBJID, "[^-]+$"),# short site-participant id
    Parameter        = PARAM,
    PARAMCD,
    Visit            = AVISIT,                         # Day 1 ... Day N ... follow-up
    AVISITN,
    Timepoint        = ATPT,
    ATPTN,
    `Result`         = AVAL,
    `Unit`           = AVALU,
    `Baseline`       = BASE,
    `Change`         = CHG,
    `Range Ind`      = ANRIND,                         # LOW / NORMAL / HIGH
    `Interpretation` = if ("EGINTP" %in% names(adam$adeg)) EGINTP else NA_character_,  # overall read
    `Anl Flag`       = ANL01FL,
    ADT) %>%
  arrange(`Dose Cohort`, Participant, PARAMCD, AVISITN, ATPTN, ADT)  # sort on numeric keys/date

ttl <- tfl_titles(num = "16.2.7.3", type = "Listing",
   text = "Listing of Electrocardiogram (ECG) Results",
   pop = "Safety Population",
   foot = paste("Change = result - baseline (baseline = last pre-first-dose value).",
                "QTcF = Fridericia-corrected QT. Interpretation = investigator overall",
                "ECG read. Anl Flag = record used in by-visit summaries. Visits span the",
                "repeat-dosing period."))

## render: one block per dose cohort (page break), columns as ordered above
## listings::create_listing(eg, ...) or gt::gt(eg %>% select(-ADT, -PARAMCD, -AVISITN, -ATPTN))
print(eg %>% select(-ADT, -PARAMCD, -AVISITN, -ATPTN))
