################################################################################
# LISTING   : l_lab_abnormal  (Single-/Fixed-Sequence DDI)
# TITLE     : Listing of Abnormal Laboratory Values by Period
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADLB (PARAMCD/PARAM, AVAL, A1LO, A1HI, ANRIND, ATOXGRN, BASE, CHG,
#             AVISIT, ADY, ONTRTFL, APERIOD/APERIODC)
# NOTE      : PSEUDOCODE. One row per on-treatment ABNORMAL laboratory record --
#             abnormal = ANRIND in (LOW,HIGH) OR CTCAE grade >=1 (ATOXGRN >= 1) --
#             matching the SAS twin. On-treatment scope = ONTRTFL == "Y", same
#             filter as SAS. Includes ALL participants (not only treatment-
#             emergent). Ordered by PERIOD, participant, parameter, study day
#             (Period 1 = reference / victim alone, Period 2 = test / victim +
#             perpetrator). Shows value vs reference range, the abnormal-range
#             flag, the CTCAE grade, baseline value and change from baseline.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SINGLESEQ")                 # byperiod = c("APERIOD","APERIODC")
options(tfl.study = env$study)
perC <- dv$byperiod[2]                           # character period label column

lab <- adam$adlb %>%
  filter(SAFFL == "Y", ONTRTFL == "Y", !is.na(AVAL),
         toupper(ANRIND) %in% c("LOW", "HIGH") |
           (!is.na(ATOXGRN) & ATOXGRN >= 1)) %>%        # abnormal range OR CTCAE Gr >=1
  mutate(per = .data[[perC]]) %>%
  transmute(
    Period      = per,
    Participant     = str_extract(USUBJID, "[^-]+$"),
    Parameter   = PARAM,
    Visit       = AVISIT,
    `Study Day` = ADY,                                   # numeric sort key
    Result      = sprintf("%.3g", AVAL),
    `Ref Range` = sprintf("%.3g - %.3g", A1LO, A1HI),
    Flag        = toupper(ANRIND),                       # LOW / HIGH
    `CTCAE Grade` = if_else(is.na(ATOXGRN), "", paste0("Gr ", ATOXGRN)),
    Baseline    = sprintf("%.3g", BASE),
    `Change from BL` = sprintf("%.3g", CHG),
    APERIOD, AVISITN, ADY) %>%
  arrange(APERIOD, Participant, Parameter, AVISITN, ADY)     # sort within period

ttl <- tfl_titles(num = "16.2.8.2", type = "Listing",
   text = "Listing of Abnormal Laboratory Values by Period",
   pop  = "Safety Population",
   foot = paste0("Single-fixed-sequence DDI: Period 1 = reference (victim alone), ",
                 "Period 2 = test (victim + perpetrator). Abnormal = normal-range ",
                 "indicator Low or High (ANRIND) or CTCAE Grade >=1 (ATOXGRN). ",
                 "On-treatment records only (ONTRTFL=Y). Range = lab reference range ",
                 "(A1LO - A1HI). Listing includes all participants, not only ",
                 "treatment-emergent."))

## render: one block per participant (page break); columns as ordered above
## listings::create_listing(lab, ...) or gt::gt(lab %>% select(-APERIOD,-AVISITN,-ADY))
print(lab %>% select(-APERIOD, -AVISITN, -ADY))
