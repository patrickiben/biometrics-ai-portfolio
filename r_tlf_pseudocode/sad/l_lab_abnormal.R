################################################################################
# LISTING   : l_lab_abnormal  (Single Ascending Dose)
# TITLE     : Listing of Abnormal Laboratory Values
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADLB (PARAMCD/PARAM, AVAL, A1LO, A1HI, ANRIND, ATOXGRN, BASE, CHG,
#             BNRIND, AVISIT, ADY, ADTC)
# NOTE      : PSEUDOCODE. SAD = parallel dose cohorts; the leading sort/block
#             key is DOSE LEVEL (dv$trtvar = TRT01A), placebo pooled. One row per
#             ABNORMAL laboratory record, where abnormal = ANRIND in LOW/HIGH OR
#             a CTCAE grade >=1 (ATOXGRN >= 1) -- so a high-grade-but-in-range
#             value is still listed. Requires non-missing AVAL. On-treatment
#             scope = ONTRTFL == "Y" (same as the SAS twin).
#             Ordered by dose level, participant, parameter, visit/day. Shows
#             value vs reference range, normal-range flag, CTCAE grade, baseline
#             and change from baseline.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SAD")                      # leading block/sort = TRT01A (dose level)

lab <- adam$adlb %>%
  ## abnormal = ANRIND in LOW/HIGH OR a CTCAE grade >=1; on-treatment, non-missing AVAL (matches SAS)
  filter(SAFFL == "Y", ONTRTFL == "Y", !is.na(AVAL),
         toupper(ANRIND) %in% c("LOW", "HIGH") | (!is.na(ATOXGRN) & ATOXGRN >= 1)) %>%
  transmute(
    `Dose Level` = .data[[dv$trtvar]],                   # SAD cohort = dose
    dosen        = .data[[dv$trtnvar]],                  # numeric dose sort key
    Participant      = str_extract(USUBJID, "[^-]+$"),
    Parameter    = PARAM,
    Visit        = AVISIT,
    `Study Day`  = ADY,                                  # numeric sort key
    Result       = sprintf("%.3g", AVAL),
    `Ref Range`  = sprintf("%.3g - %.3g", A1LO, A1HI),
    Flag         = toupper(ANRIND),                      # LOW / HIGH / NORMAL
    Grade        = ifelse(is.na(ATOXGRN), "", paste0("Gr ", ATOXGRN)),  # CTCAE grade
    Baseline     = sprintf("%.3g", BASE),
    `Change from BL` = sprintf("%.3g", CHG),
    ADY) %>%
  arrange(dosen, `Dose Level`, Participant, Parameter, ADY)  # ascending dose, then subj/day

ttl <- tfl_titles(num = "16.2.8.1", type = "Listing",
   text = "Listing of Abnormal Laboratory Values",
   pop  = "Safety Population",
   foot = paste0("Abnormal = reference-range flag Low/High (ANRIND) or CTCAE Grade >=1 ",
                 "(ATOXGRN). On-treatment records only (ONTRTFL=='Y'). Range = lab ",
                 "reference range (A1LO - A1HI). Blocked by dose level (TRT01A); ",
                 "placebo pooled."))

## render: one block per dose level (page break); columns as ordered above
## listings::create_listing(lab, ...) or gt::gt(lab %>% select(-dosen, -ADY))
print(lab %>% select(-dosen, -ADY))
