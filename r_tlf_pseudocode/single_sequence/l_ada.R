################################################################################
# LISTING   : l_ada  (Single-/Fixed-Sequence DDI)
# TITLE     : Listing of Anti-Drug Antibody (ADA) Results
# POPULATION: ADA-Evaluable Population (ADIS-evaluable)
# INPUT     : ADIS
# NOTE      : PSEUDOCODE. One row per immunogenicity sample, ordered by PERIOD,
#             participant, then nominal time/visit. Shows ADA result, titer, NAb
#             result and a derived ADA STATUS string built from the ADIS-specific
#             flags (ADABLFL/TEADAFL/ADAPERFL/ADATRNFL/NABFL) -- same content as
#             the SAS twin. Single-/fixed-sequence DDI: a participant is sampled
#             across BOTH periods -> a PERIOD column (dv$byperiod, APERIODC:
#             Period 1 = reference / victim alone, Period 2 = test / victim +
#             perpetrator) is shown and is the leading sort key. Listings show all
#             evaluable records (sort on numeric keys, not text).
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SINGLESEQ")                 # byperiod = c("APERIOD","APERIODC")
options(tfl.study = env$study)
perN <- dv$byperiod[1]; perC <- dv$byperiod[2]  # numeric + character period

## derived ADA status string from the ADIS flags (mirrors the SAS catx logic)
ada_status <- function(ADABLFL, TEADAFL, ADAPERFL, ADATRNFL, NABFL) {
  parts <- c(
    if_else(ADABLFL  == "Y", "Baseline+",   NA_character_),
    if_else(TEADAFL  == "Y", "Trt-emergent", NA_character_),
    case_when(ADAPERFL == "Y" ~ "Persistent",
              ADATRNFL == "Y" ~ "Transient",
              TRUE ~ NA_character_),
    if_else(NABFL    == "Y", "NAb+",        NA_character_))
  paste(na.omit(parts), collapse = "; ")
}

adis <- adam$adis %>% filter(ADAFL == "Y") %>%
  rowwise() %>%
  mutate(`ADA Status` = ada_status(ADABLFL, TEADAFL, ADAPERFL, ADATRNFL, NABFL)) %>%
  ungroup() %>%
  transmute(
    Period      = .data[[perC]],                     # Period 1 ref / Period 2 test+perp
    Participant     = str_extract(USUBJID, "[^-]+$"),    # short site-participant id
    Parameter   = PARAM,
    Visit       = AVISIT,
    `Time`      = ATPT,
    `Baseline`      = if_else(ADABLFL == "Y", "Yes", "No"),  # baseline ADA-positive
    `ADA Result`    = AVALC,                          # Positive / Negative
    `Titer`         = ADATITER,
    `ADA Status`    = `ADA Status`,                   # derived status (same as SAS)
    `NAb Result`    = NABRESC,
    .pern = .data[[perN]], AVISITN, ATPTN) %>%       # numeric sort keys (dropped at render)
  arrange(.pern, Participant, AVISITN, ATPTN)

ttl <- tfl_titles(num = "16.2.9.2", type = "Listing",
   text = "Listing of Anti-Drug Antibody (ADA) Results",
   pop  = "Immunogenicity (ADA Evaluable) Population",
   foot = paste("Single-fixed-sequence DDI: Period 1 = reference (victim alone),",
                "Period 2 = test (victim + perpetrator). Status derived from ADIS",
                "flags: Baseline+ (ADABLFL), Trt-emergent (TEADAFL),",
                "Persistent/Transient (ADAPERFL/ADATRNFL), NAb+ (NABFL). NAb",
                "assessed in confirmed ADA-positive samples. Sorted on numeric",
                "period/visit/time keys. '.' = not done/missing."))

## render: one block per period (page break), numeric keys dropped
## listings::create_listing(adis, ...) or gt::gt(adis %>% select(-.pern, -AVISITN, -ATPTN))
print(adis %>% select(-.pern, -AVISITN, -ATPTN))
