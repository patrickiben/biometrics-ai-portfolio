################################################################################
# LISTING   : l_ae  (Multiple Ascending Dose)
# TITLE     : Listing of Adverse Events
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADAE
# NOTE      : PSEUDOCODE. MAD = parallel ascending-dose cohorts, repeated dosing;
#             one treatment per participant, so the treatment column is the dose
#             level (dv$trtvar = TRT01A). One row per AE record, ordered by dose
#             then participant then onset. Flags SAE / TEAE / relationship / action /
#             outcome. Because dosing is repeated, an Onset Day (ASTDY) column is
#             shown so reviewers can locate the event within the multi-day dosing
#             period. Listings show all events (not only treatment-emergent).
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("MAD")                       # trtvar = TRT01A (dose level)

ae <- adam$adae %>% filter(SAFFL == "Y") %>%
  transmute(
    `Dose Level` = .data[[dv$trtvar]],
    `Dose (n)`   = .data[[dv$trtnvar]],             # numeric dose -> ascending sort key
    Participant      = str_extract(USUBJID, "[^-]+$"),  # short site-participant id
    SOC          = AESOC,
    `Preferred Term` = AEDECOD,
    `Onset Day`  = ASTDY,                           # numeric study day within dosing period
    `Dur (d)`    = ADURN,
    Severity     = factor(AESEVN, levels = 1:3, labels = c("Mild","Moderate","Severe")),
    Serious      = if_else(AESER == "Y", "Yes", "No"),
    TEAE         = if_else(TRTEMFL == "Y", "Yes", "No"),
    Relationship = AREL,
    `Action Taken` = AEACN,
    Outcome      = AEOUT,
    ASTDT) %>%
  arrange(`Dose (n)`, Participant, ASTDT, `Preferred Term`)  # dose ascending, then date (not text)

ttl <- tfl_titles(
  num  = "16.2.7.1",
  type = "Listing",
  text = "Listing of Adverse Events",
  pop  = "Safety Population",
  foot = paste("MAD: one treatment per participant = dose level (blocks ascending by dose).",
               "Onset Day = study day within the repeated-dosing period.",
               "TEAE = treatment-emergent. SAE = serious. Rel = relationship to study",
               "drug per investigator/analysis. MedDRA v27.0."))

## render: one block per dose level (page break), ascending; columns as ordered.
## listings::create_listing(ae, ...) or gt::gt(ae %>% select(-ASTDT, -`Dose (n)`))
print(ae %>% select(-ASTDT, -`Dose (n)`))
