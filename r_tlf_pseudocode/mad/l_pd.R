################################################################################
# LISTING   : l_pd  (Multiple Ascending Dose)
# TITLE     : Listing of Pharmacodynamic / Biomarker Results
# POPULATION: PD-Evaluable Population (PDFL == "Y")
# INPUT     : ADPD
# NOTE      : PSEUDOCODE. One row per PD record, ordered by dose level, participant,
#             parameter, treatment-day, then nominal time. Shows observed value,
#             baseline, change and % change. MAD = parallel cohorts, REPEATED
#             dosing, one dose level per participant -> column = dv$trtvar (TRT01A =
#             dose level; placebo pooled). Repeated dosing -> treatment-day (ADY)
#             is a primary sort key so each participant's records list in dosing-day
#             order and the pre-dose (trough) value on successive days is easy to
#             read for the steady-state assessment; a Pre-dose flag is surfaced.
#             Dose-level ordering by the numeric dose (dv$trtnvar) so cohorts list
#             in ascending order. Listings show all evaluable records (sort on
#             numeric keys, not display text).
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("MAD")                      # column = TRT01A (= dose level)

pd <- adam$adpd %>% filter(PDFL == "Y") %>%
  transmute(
    `Dose Level` = .data[[dv$trtvar]],
    DoseN       = .data[[dv$trtnvar]],               # numeric dose -> ascending sort key
    Participant     = str_extract(USUBJID, "[^-]+$"),    # short site-participant id
    Parameter   = PARAM,
    `Day`       = ADY,                               # treatment-day (repeated dosing)
    Visit       = AVISIT,
    `Time`      = ATPT,
    `Pre-dose`  = if_else((!is.na(ATPTN) & ATPTN <= 0) |
                          toupper(coalesce(ATPT, "")) == "PRE-DOSE", "Yes", ""),  # trough marker
    `Result`    = AVAL,
    `Baseline`  = BASE,
    `Change`    = CHG,
    `% Change`  = PCHG,
    Unit        = AVALU,
    `Analysis Flag` = ANL01FL,                       # record-level analysis flag
    AVISITN, ATPTN) %>%                              # numeric sort keys (dropped at render)
  arrange(DoseN, Participant, Parameter, Day, AVISITN, ATPTN)

ttl <- tfl_titles(num = "16.2.9.1", type = "Listing",
   text = "Listing of Pharmacodynamic Results",
   pop  = "Pharmacodynamic-Evaluable Population",
   foot = paste("Change and % change relative to ADaM BASE.",
                "Multiple ascending dose: ordered by ascending dose level, participant,",
                "then treatment-day; 'Pre-dose' marks trough samples used for the",
                "steady-state assessment. Sorted on numeric dose/day/visit/time keys.",
                "'.' = not done/missing."))

## render: one block per dose level (page break), numeric keys dropped
## listings::create_listing(pd, ...) or gt::gt(pd %>% select(-DoseN, -AVISITN, -ATPTN))
print(pd %>% select(-DoseN, -AVISITN, -ATPTN))
