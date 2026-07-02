################################################################################
# LISTING   : l_ae  (Parallel-group)
# TITLE     : Listing of Adverse Events
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADAE
# NOTE      : PSEUDOCODE. One row per AE record, ordered by participant then onset.
#             Flags SAE / TEAE / relationship / action / outcome. Listings show
#             all events (not only treatment-emergent).
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("PARALLEL")

ae <- adam$adae %>% filter(SAFFL == "Y") %>%
  transmute(
    Treatment = .data[[dv$trtvar]],
    Participant   = str_extract(USUBJID, "[^-]+$"),     # short site-participant id
    SOC       = AESOC,
    `Preferred Term` = AEDECOD,
    `Onset Day` = ASTDY,                            # numeric study day (sort key)
    `Dur (d)`   = ADURN,
    Severity    = factor(AESEVN, levels = 1:3, labels = c("Mild","Moderate","Severe")),
    Serious     = if_else(AESER == "Y", "Yes", "No"),
    TEAE        = if_else(TRTEMFL == "Y", "Yes", "No"),
    Relationship = AREL,
    `Action Taken` = AEACN,
    Outcome     = AEOUT,
    ASTDT) %>%
  arrange(Treatment, Participant, ASTDT, `Preferred Term`)   # sort on the date/day, not text

ttl <- tfl_titles(num = "16.2.7.1", type = "Listing", text = "Listing of Adverse Events",
   pop = "Safety Population",
   foot = "TEAE = treatment-emergent. SAE = serious. Rel = relationship to study drug per investigator/analysis. MedDRA v27.0.")

## render: one block per treatment (page break), columns as ordered above
## listings::create_listing(ae, ...) or gt::gt(ae %>% select(-ASTDT))
print(ae %>% select(-ASTDT))
