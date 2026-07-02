################################################################################
# LISTING   : l_vitals  (Single-/Fixed-Sequence DDI)
# TITLE     : Listing of Vital Signs
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADVS
# NOTE      : PSEUDOCODE. One row per vital-sign assessment, ordered by participant,
#             PERIOD, parameter, then visit/timepoint. Shows observed value,
#             period baseline, change, and the analysis-range flag. Single-fixed-
#             sequence DDI: a Period column (dv$byperiod = APERIODC) replaces the
#             treatment-arm column; the treatment given in that period (dv$trtvar
#             = TRTA) is shown for traceability. Period 1 = reference/victim
#             alone, Period 2 = test/victim + perpetrator.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SINGLESEQ")                 # byperiod = APERIOD/APERIODC; trtvar = TRTA
perN <- dv$byperiod[1]; perC <- dv$byperiod[2]

vs <- adam$advs %>% filter(SAFFL == "Y") %>%
  transmute(
    Period      = .data[[perC]],                     # Period 1 ref / Period 2 test
    APERIODN    = .data[[perN]],
    Treatment   = .data[[dv$trtvar]],                # treatment given in this period
    Participant     = str_extract(USUBJID, "[^-]+$"),    # short site-participant id
    Parameter   = PARAM,
    PARAMCD,
    Visit       = AVISIT,
    AVISITN,
    Timepoint   = ATPT,
    ATPTN,
    `Result`    = AVAL,
    `Unit`      = AVALU,
    `Baseline`  = BASE,                              # period-specific baseline
    `Change`    = CHG,
    `Ref Range` = if_else(!is.na(ANRLO) & !is.na(ANRHI),
                          sprintf("%g - %g", ANRLO, ANRHI), NA_character_),
    `Range Ind` = ANRIND,                            # LOW / NORMAL / HIGH
    `Anl Flag`  = ANL01FL,
    ADT) %>%
  arrange(Participant, APERIODN, PARAMCD, AVISITN, ATPTN, ADT)   # sort on numeric keys/date

ttl <- tfl_titles(num = "16.2.7.2", type = "Listing", text = "Listing of Vital Signs",
   pop = "Safety Population",
   foot = paste("Single-fixed-sequence DDI. Period 1 = reference (victim alone),",
                "Period 2 = test (victim + perpetrator). Baseline = period-specific",
                "pre-dose value; change = result - baseline. Range Ind per analysis",
                "reference range. Anl Flag = record used in by-period summaries."))

## render: one block per Period (page break), columns as ordered above
## listings::create_listing(vs, ...) or gt::gt(vs %>% select(-ADT, -PARAMCD, -AVISITN, -ATPTN, -APERIODN))
print(vs %>% select(-ADT, -PARAMCD, -AVISITN, -ATPTN, -APERIODN))
