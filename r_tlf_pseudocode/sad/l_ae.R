################################################################################
# LISTING   : l_ae  (Single Ascending Dose)
# TITLE     : Listing of Adverse Events by Dose Level
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADAE
# NOTE      : PSEUDOCODE. One row per AE record, ordered by dose level then
#             participant then onset. Flags SAE / TEAE / relationship / action /
#             outcome. Listings show all events (not only treatment-emergent).
#             SAD: treatment column = dose level (dv$trtvar = TRT01A, one single
#             dose per participant); blocks ordered by ascending dose (TRT01AN).
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SAD")                       # trtvar = TRT01A, trtnvar = TRT01AN

ae <- adam$adae %>% filter(SAFFL == "Y") %>%
  transmute(
    `Dose Level` = .data[[dv$trtvar]],
    DoseN        = .data[[dv$trtnvar]],             # numeric dose -> ascending block order
    Participant      = str_extract(USUBJID, "[^-]+$"),  # short site-participant id
    SOC          = AESOC,
    `Preferred Term` = AEDECOD,
    `Onset Day`  = ASTDY,                           # numeric study day (display)
    `Dur (d)`    = ADURN,
    Severity     = factor(AESEVN, levels = 1:3, labels = c("Mild","Moderate","Severe")),
    Serious      = if_else(AESER == "Y", "Yes", "No"),
    TEAE         = if_else(TRTEMFL == "Y", "Yes", "No"),
    Relationship = AREL,
    `Action Taken` = AEACN,
    Outcome      = AEOUT,
    ASTDT) %>%
  arrange(DoseN, `Dose Level`, Participant, ASTDT, `Preferred Term`)  # ascending dose; sort on date, not text

ttl <- tfl_titles(
  num  = "16.2.7.1",
  type = "Listing",
  text = "Listing of Adverse Events by Dose Level",
  pop  = "Safety Population",
  foot = paste("SAD: one block per single ascending dose level (TRT01A), ordered",
               "low to high. TEAE = treatment-emergent. SAE = serious. Rel =",
               "relationship to study drug per investigator/analysis. MedDRA v27.0."))

## render: one block per dose level (page break), ascending; drop sort-key cols.
## listings::create_listing(ae, ...) or gt::gt(ae %>% select(-ASTDT, -DoseN))
print(ae %>% select(-ASTDT, -DoseN))
