################################################################################
# LISTING   : l_pd  (Parallel-group)
# TITLE     : Listing of Pharmacodynamic / Biomarker Results
# POPULATION: PD-Evaluable Population (PDFL == "Y")
# INPUT     : ADPD
# NOTE      : PSEUDOCODE. One row per PD record, ordered by treatment, participant,
#             parameter, then nominal time. Shows observed value, baseline,
#             change and % change. Parallel-group: one treatment per participant ->
#             column = dv$trtvar (TRT01A, = dose for ascending-dose layouts).
#             Listings show all evaluable records (sort on numeric keys, not
#             display text).
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("PARALLEL")

pd <- adam$adpd %>% filter(PDFL == "Y") %>%
  transmute(
    Treatment   = .data[[dv$trtvar]],
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
  arrange(Treatment, Participant, Parameter, AVISITN, ATPTN)

ttl <- tfl_titles(num = "16.2.10.1", type = "Listing",
   text = "Listing of Pharmacodynamic Results",
   pop  = "Pharmacodynamic-Evaluable Population",
   foot = "Change and % change relative to ADaM BASE. Sorted on numeric visit/time keys. '.' = not done/missing.")

## render: one block per treatment (page break), numeric keys dropped
## listings::create_listing(pd, ...) or gt::gt(pd %>% select(-AVISITN, -ATPTN))
print(pd %>% select(-AVISITN, -ATPTN))
