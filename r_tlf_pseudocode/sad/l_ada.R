################################################################################
# LISTING   : l_ada  (Single Ascending Dose)
# TITLE     : Listing of Anti-Drug Antibody (ADA) Results
# POPULATION: ADA-Evaluable Population (ADIS-evaluable)
# INPUT     : ADIS (PARAM/PARAMCD, AVALC/AVAL = ADA result/titer; ABLFL,
#             ADAEMFL, NABRESC -- same ADIS variable names as the SAS twin)
# NOTE      : PSEUDOCODE. One row per immunogenicity sample, ordered by dose
#             level, participant, then nominal time/visit. Shows ADA result, titer,
#             baseline-record flag (ABLFL), treatment-emergent ADA (ADAEMFL) and
#             NAb result (NABRESC) -- the identical ADIS variables and displayed
#             columns as the SAS twin (no re-derivation of the assay outcome).
#             SAD = parallel cohorts, one dose per participant -> column = dv$trtvar
#             (TRT01A = dose level; placebo pooled). Dose-level ordering by the
#             numeric dose (dv$trtnvar) so cohorts list in ascending order.
#             Listings show all evaluable records (sort on numeric keys, not text).
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SAD")                      # column = TRT01A (= dose level)

adis <- adam$adis %>% filter(ADAFL == "Y") %>%
  transmute(
    `Dose Level` = .data[[dv$trtvar]],
    DoseN       = .data[[dv$trtnvar]],               # numeric dose -> ascending sort key
    Participant     = str_extract(USUBJID, "[^-]+$"),    # short site-participant id
    Parameter   = PARAM,
    Visit       = AVISIT,
    `Time`      = ATPT,
    `ADA Result`    = AVALC,                          # Positive / Negative
    `Titer`         = if_else(is.na(AVAL), "", as.character(AVAL)),   # reported titer (AVAL)
    `Baseline`      = if_else(ABLFL   == "Y", "Yes", "No"),  # baseline record (ABLFL)
    `TE-ADA`        = if_else(ADAEMFL == "Y", "Yes", "No"),  # treatment-emergent (ADAEMFL)
    `NAb Result`    = NABRESC,                        # NAb result (NABRESC)
    AVISITN, ATPTN) %>%                               # numeric sort keys (dropped at render)
  arrange(DoseN, Participant, AVISITN, ATPTN)

ttl <- tfl_titles(num = "16.2.10.1", type = "Listing",
   text = "Listing of Anti-Drug Antibody (ADA) Results",
   pop  = "Immunogenicity (ADA Evaluable) Population",
   foot = paste("One row per ADA sample. TE-ADA = treatment-emergent (induced or boosted)",
                "per ADIS (ADAEMFL). NAb = neutralizing antibody result (NABRESC).",
                "Single ascending dose: ordered by ascending dose level then participant.",
                "Sorted on numeric dose/visit/time keys."))

## render: one block per dose level (page break), numeric keys dropped
## listings::create_listing(adis, ...) or gt::gt(adis %>% select(-DoseN, -AVISITN, -ATPTN))
print(adis %>% select(-DoseN, -AVISITN, -ATPTN))
