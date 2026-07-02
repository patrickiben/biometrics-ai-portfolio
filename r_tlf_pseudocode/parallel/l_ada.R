################################################################################
# LISTING   : l_ada  (Parallel-group)
# TITLE     : Listing of Anti-Drug Antibody (ADA) Results
# POPULATION: ADA-Evaluable Population (ADIS-evaluable)
# INPUT     : ADIS
# NOTE      : PSEUDOCODE. One row per immunogenicity sample, ordered by
#             treatment, participant, then nominal time/visit. Shows ADA result,
#             titer, NAb result and derived treatment-emergent/induced/boosted
#             status. Parallel-group: one treatment per participant -> column =
#             dv$trtvar (TRT01A, = dose for ascending-dose layouts). Listings
#             show all evaluable records (sort on numeric keys, not text).
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("PARALLEL")

adis <- adam$adis %>% filter(ADAFL == "Y") %>%
  transmute(
    Treatment   = .data[[dv$trtvar]],
    Participant     = str_extract(USUBJID, "[^-]+$"),    # short site-participant id
    Parameter   = PARAM,
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
  arrange(Treatment, Participant, AVISITN, ATPTN)

ttl <- tfl_titles(num = "16.2.12.1", type = "Listing",
   text = "Listing of Anti-Drug Antibody (ADA) Results",
   pop  = "ADA-Evaluable Population",
   foot = paste("Treatment-emergent / induced / boosted derived per analysis plan (ADIS).",
                "NAb assessed in confirmed ADA-positive samples. Sorted on numeric",
                "visit/time keys. '.' = not done/missing."))

## render: one block per treatment (page break), numeric keys dropped
## listings::create_listing(adis, ...) or gt::gt(adis %>% select(-AVISITN, -ATPTN))
print(adis %>% select(-AVISITN, -ATPTN))
