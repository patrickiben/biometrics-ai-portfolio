################################################################################
# LISTING   : l_pd  (Single-/Fixed-Sequence DDI)
# TITLE     : Listing of Pharmacodynamic / Biomarker Results
# POPULATION: PD-Evaluable Population (PDFL == "Y")
# INPUT     : ADPD
# NOTE      : PSEUDOCODE. One row per PD record, ordered by PERIOD, participant,
#             parameter, then nominal time. Shows observed value, baseline,
#             change and % change. Single-/fixed-sequence DDI: a participant is
#             followed across BOTH periods -> a PERIOD column (dv$byperiod,
#             APERIODC: Period 1 = reference / victim alone, Period 2 = test /
#             victim + perpetrator) is shown and is the leading sort key.
#             Listings show all evaluable records (sort on numeric keys, not
#             display text).
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SINGLESEQ")                 # byperiod = c("APERIOD","APERIODC")
options(tfl.study = env$study)
perN <- dv$byperiod[1]; perC <- dv$byperiod[2]  # numeric + character period

pd <- adam$adpd %>% filter(PDFL == "Y") %>%
  transmute(
    Period      = .data[[perC]],                     # Period 1 ref / Period 2 test+perp
    Participant     = str_extract(USUBJID, "[^-]+$"),    # short site-participant id
    Parameter   = PARAM,
    Visit       = AVISIT,
    `Time`      = ATPT,
    `Result`    = AVAL,
    `Baseline`  = BASE,
    `Change`    = CHG,
    `% Change`  = PCHG,
    Unit        = AVALU,
    `Analysis Flag` = ANL01FL,                       # record-level analysis flag
    .pern = .data[[perN]], AVISITN, ATPTN) %>%       # numeric sort keys (dropped at render)
  arrange(.pern, Participant, Parameter, AVISITN, ATPTN)

ttl <- tfl_titles(num = "16.2.9.1", type = "Listing",
   text = "Listing of Pharmacodynamic Results",
   pop  = "Pharmacodynamic-Evaluable Population",
   foot = paste("Single-fixed-sequence DDI: Period 1 = reference (victim alone),",
                "Period 2 = test (victim + perpetrator). Change and % change",
                "relative to ADaM BASE. Sorted on numeric period/visit/time keys.",
                "'.' = not done/missing."))

## render: one block per period (page break), numeric keys dropped
## listings::create_listing(pd, ...) or gt::gt(pd %>% select(-.pern, -AVISITN, -ATPTN))
print(pd %>% select(-.pern, -AVISITN, -ATPTN))
