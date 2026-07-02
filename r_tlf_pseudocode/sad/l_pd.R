################################################################################
# LISTING   : l_pd  (Single Ascending Dose)
# TITLE     : Listing of Pharmacodynamic / Biomarker Results
# POPULATION: PD-Evaluable Population (PDFL == "Y")
# INPUT     : ADPD
# NOTE      : PSEUDOCODE. One row per PD record, ordered by dose level, participant,
#             parameter, then nominal time. Shows observed value, baseline,
#             change and % change. SAD = parallel cohorts, one dose per participant
#             -> column = dv$trtvar (TRT01A = dose level; placebo pooled).
#             Dose-level ordering by the numeric dose (dv$trtnvar) so cohorts
#             list in ascending order. Listings show all evaluable records
#             (sort on numeric keys, not display text).
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SAD")                      # column = TRT01A (= dose level)

pd <- adam$adpd %>% filter(PDFL == "Y") %>%
  transmute(
    `Dose Level` = .data[[dv$trtvar]],
    DoseN       = .data[[dv$trtnvar]],               # numeric dose -> ascending sort key
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
    AVISITN, ATPTN) %>%                              # numeric sort keys (dropped at render)
  arrange(DoseN, Participant, Parameter, AVISITN, ATPTN)

ttl <- tfl_titles(num = "16.2.9.1", type = "Listing",
   text = "Listing of Pharmacodynamic Results",
   pop  = "Pharmacodynamic-Evaluable Population",
   foot = paste("Change and % change relative to ADaM BASE.",
                "Single ascending dose: ordered by ascending dose level then participant.",
                "Sorted on numeric dose/visit/time keys. '.' = not done/missing."))

## render: one block per dose level (page break), numeric keys dropped
## listings::create_listing(pd, ...) or gt::gt(pd %>% select(-DoseN, -AVISITN, -ATPTN))
print(pd %>% select(-DoseN, -AVISITN, -ATPTN))
