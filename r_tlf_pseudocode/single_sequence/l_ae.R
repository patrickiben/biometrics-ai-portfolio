################################################################################
# LISTING   : l_ae  (Single-/fixed-sequence DDI)
# TITLE     : Listing of Adverse Events
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADAE
# NOTE      : PSEUDOCODE. One row per AE record, ordered by participant then onset.
#             DDI: shows the PERIOD (APERIODC) in which the AE started so reviewers
#             can read events as victim-alone (Period 1) vs victim+perpetrator
#             (Period 2). NO randomized sequence column (single-/fixed-sequence) --
#             period replaces it. Listings show all events (not only TEAE).
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SINGLESEQ")                 # TRTA + APERIOD/APERIODC

period_col <- dv$byperiod[2]                    # "APERIODC"

ae <- adam$adae %>% filter(SAFFL == "Y") %>%
  transmute(
    Participant     = str_extract(USUBJID, "[^-]+$"),    # short site-participant id
    Period      = .data[[period_col]],               # APERIODC = victim alone / + perpetrator
    Treatment   = .data[[dv$trtvar]],                # TRTA actual treatment in that period
    SOC         = AESOC,
    `Preferred Term` = AEDECOD,
    `Onset Day` = ASTDY,                             # numeric study day
    `Dur (d)`   = ADURN,
    Severity    = factor(AESEVN, levels = 1:3, labels = c("Mild","Moderate","Severe")),
    Serious     = if_else(AESER == "Y", "Yes", "No"),
    TEAE        = if_else(TRTEMFL == "Y", "Yes", "No"),
    Relationship = AREL,
    `Action Taken` = AEACN,
    Outcome     = AEOUT,
    APERIODN, ASTDT) %>%
  arrange(Participant, APERIODN, ASTDT, `Preferred Term`)   # sort by participant, period, date

ttl <- tfl_titles(num = "16.2.7.1", type = "Listing", text = "Listing of Adverse Events",
   pop = "Safety Population",
   foot = paste("DDI: Period 1 = victim alone (reference); Period 2 = victim + perpetrator (test).",
                "TEAE = treatment-emergent. SAE = serious. Rel = relationship to study drug per investigator/analysis. MedDRA v27.0."))

## render: one block per participant (or per period), columns as ordered above
## listings::create_listing(ae, ...) or gt::gt(ae %>% select(-APERIODN, -ASTDT))
print(ae %>% select(-APERIODN, -ASTDT))
