################################################################################
# LISTING   : l_lab_abnormal  (Multiple Ascending Dose)
# TITLE     : Listing of Abnormal Laboratory Values
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADLB (PARAMCD/PARAM, AVAL, A1LO, A1HI, ANRIND, ATOXGRN, BASE, CHG,
#             AVISIT, ADY, ONTRTFL)
# NOTE      : PSEUDOCODE. MAD = parallel dose cohorts with REPEATED dosing; one row
#             per ABNORMAL on-treatment result (ANRIND in LOW/HIGH OR CTCAE toxicity
#             grade ATOXGRN >= 1) across ALL on-treatment dosing days, ordered by
#             dose level, participant, parameter, study day -- so a participant's
#             repeat abnormalities over the dosing period appear in chronological
#             sequence. Shows value, baseline, change from baseline, reference range,
#             the Low/High flag and the CTCAE toxicity grade.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("MAD")                      # column / lead sort = TRT01A (dose level)

lab <- adam$adlb %>%
  filter(SAFFL == "Y", ONTRTFL == "Y",                  # on-treatment scope
         toupper(ANRIND) %in% c("LOW","HIGH") |         # abnormal = Low/High OR
           (!is.na(ATOXGRN) & ATOXGRN >= 1)) %>%        #   CTCAE toxicity grade >= 1
  transmute(
    `Dose Level` = .data[[dv$trtvar]],
    Participant  = str_extract(USUBJID, "[^-]+$"),
    Parameter    = PARAM,
    Visit        = AVISIT,
    `Study Day`  = ADY,                                  # numeric sort key (dosing-day order)
    Result       = sprintf("%.3g", AVAL),
    Baseline     = sprintf("%.3g", BASE),
    Change       = sprintf("%.3g", CHG),                 # change from baseline (matches SAS twin)
    `Ref Range`  = sprintf("%.3g - %.3g", A1LO, A1HI),
    Flag         = case_when(toupper(ANRIND) == "HIGH" ~ "High",
                             toupper(ANRIND) == "LOW"  ~ "Low",
                             TRUE ~ ""),                 # Low / High direction
    Grade        = ifelse(is.na(ATOXGRN), "", as.character(ATOXGRN)),  # CTCAE toxicity grade
    ADY) %>%
  arrange(`Dose Level`, Participant, Parameter, ADY)         # sort on numeric day, not text

ttl <- tfl_titles(num = "16.2.8.1", type = "Listing",
   text = "Listing of Abnormal Laboratory Values",
   pop  = "Safety Population",
   foot = paste0("Abnormal = normal-range indicator Low/High (ANRIND) or CTCAE ",
                 "toxicity grade ATOXGRN >= 1; on-treatment records only ",
                 "(ONTRTFL=Y), across all dosing days (MAD repeated dosing). ",
                 "Reference range = A1LO - A1HI. SI units."))

## render: one block per dose level (page break); columns as ordered above
## listings::create_listing(lab, ...) or gt::gt(lab %>% select(-ADY))
print(lab %>% select(-ADY))
