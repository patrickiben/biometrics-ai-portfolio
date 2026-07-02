################################################################################
# LISTING   : l_ada  (Multiple Ascending Dose)
# TITLE     : Listing of Anti-Drug Antibody (ADA) Results
# POPULATION: ADA-Evaluable Population (ADIS-evaluable)
# INPUT     : ADIS
# NOTE      : PSEUDOCODE. One row per immunogenicity sample, ordered by dose
#             level, participant, treatment-day, then nominal time/visit. Shows ADA
#             result, titer, NAb result and derived treatment-emergent/induced/
#             boosted status. MAD = parallel cohorts, REPEATED dosing, one dose
#             level per participant -> column = dv$trtvar (TRT01A = dose level;
#             placebo pooled). Repeated dosing -> multiple on-treatment ADA
#             samples per participant across dosing days/visits, so treatment-day
#             (ADY) is a primary sort key and the within-participant titer trajectory
#             reads top-to-bottom. Dose-level ordering by the numeric dose
#             (dv$trtnvar) so cohorts list in ascending order. Listings show all
#             evaluable records (sort on numeric keys, not text).
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("MAD")                      # column = TRT01A (= dose level)

adis <- adam$adis %>% filter(ADAFL == "Y") %>%
  transmute(
    `Dose Level` = .data[[dv$trtvar]],
    DoseN       = .data[[dv$trtnvar]],               # numeric dose -> ascending sort key
    Participant     = str_extract(USUBJID, "[^-]+$"),    # short site-participant id
    Parameter   = PARAM,
    `Day`       = ADY,                               # treatment-day (repeated dosing)
    Visit       = AVISIT,
    `Time`      = ATPT,
    `Baseline ADA`  = BASEADA,                        # baseline status
    `ADA Result`    = AVALC,                          # Positive / Negative
    `Titer`         = ADATITER,
    `NAb Result`    = NABRES,
    `Trt-Emergent`  = if_else(toupper(TEADAFL)  == "Y", "Yes", "No"),
    `Induced`       = if_else(toupper(ADAINDFL) == "Y", "Yes", "No"),
    `Boosted`       = if_else(toupper(ADABSTFL) == "Y", "Yes", "No"),
    AVISITN, ATPTN) %>%                               # numeric sort keys (dropped at render)
  arrange(DoseN, Participant, Day, AVISITN, ATPTN)

ttl <- tfl_titles(num = "16.2.10.1", type = "Listing",
   text = "Listing of Anti-Drug Antibody (ADA) Results",
   pop  = "ADA-Evaluable Population",
   foot = paste("Treatment-emergent / induced / boosted derived per analysis plan (ADIS).",
                "Multiple ascending dose: ordered by ascending dose level, participant,",
                "then treatment-day so each participant's multi-visit titer trajectory reads",
                "in dosing-day order. NAb assessed in confirmed ADA-positive samples.",
                "Sorted on numeric dose/day/visit/time keys. '.' = not done/missing."))

## render: one block per dose level (page break), numeric keys dropped
## listings::create_listing(adis, ...) or gt::gt(adis %>% select(-DoseN, -AVISITN, -ATPTN))
print(adis %>% select(-DoseN, -AVISITN, -ATPTN))
