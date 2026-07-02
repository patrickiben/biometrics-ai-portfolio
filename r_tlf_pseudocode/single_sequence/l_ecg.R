################################################################################
# LISTING   : l_ecg  (Single-/Fixed-Sequence DDI)
# TITLE     : Listing of Electrocardiogram (ECG) Results
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADEG
# NOTE      : PSEUDOCODE. One row per ECG assessment, ordered by participant, PERIOD,
#             parameter, then visit/timepoint. Shows observed value, period
#             baseline, change, range indicator, and the overall ECG
#             interpretation. Single-fixed-sequence DDI: a Period column
#             (dv$byperiod = APERIODC) replaces the treatment-arm column; the
#             treatment given in that period (dv$trtvar = TRTA) is shown for
#             traceability. Period 1 = reference/victim alone, Period 2 =
#             test/victim + perpetrator.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SINGLESEQ")                 # byperiod = APERIOD/APERIODC; trtvar = TRTA
perN <- dv$byperiod[1]; perC <- dv$byperiod[2]

eg <- adam$adeg %>% filter(SAFFL == "Y") %>%
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
    `Range Ind` = ANRIND,                            # LOW / NORMAL / HIGH
    `Interpretation` = if ("EGINTP" %in% names(adam$adeg)) EGINTP else NA_character_,  # overall read
    `Anl Flag`  = ANL01FL,
    ADT) %>%
  arrange(Participant, APERIODN, PARAMCD, AVISITN, ATPTN, ADT)   # sort on numeric keys/date

ttl <- tfl_titles(num = "16.2.8.1", type = "Listing",
   text = "Listing of Electrocardiogram (ECG) Results",
   pop = "Safety Population",
   foot = paste("Single-fixed-sequence DDI. Period 1 = reference (victim alone),",
                "Period 2 = test (victim + perpetrator). Baseline = period-specific",
                "pre-dose value; change = result - baseline. QTcF = Fridericia-",
                "corrected QT. Interpretation = investigator overall ECG read.",
                "Anl Flag = record used in by-period summaries."))

## render: one block per Period (page break), columns as ordered above
## listings::create_listing(eg, ...) or gt::gt(eg %>% select(-ADT, -PARAMCD, -AVISITN, -ATPTN, -APERIODN))
print(eg %>% select(-ADT, -PARAMCD, -AVISITN, -ATPTN, -APERIODN))
