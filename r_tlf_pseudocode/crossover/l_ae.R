################################################################################
# LISTING   : l_ae  (Crossover - 2x2 or Williams)
# TITLE     : Listing of Adverse Events
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADAE
# NOTE      : PSEUDOCODE. One row per AE record, ordered by sequence, participant,
#             period, then onset. Crossover requires SEQUENCE (dv$seqvar=TRTSEQP)
#             and PERIOD (dv$byperiod=APERIOD/APERIODC) on the listing so each
#             event is traceable to the treatment in effect when it emerged.
#             Treatment = actual treatment (dv$trtvar=TRTA). Flags SAE / TEAE /
#             relationship / action / outcome. Listings show all events (not only
#             treatment-emergent).
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("CROSSOVER")                 # trtvar=TRTA, seqvar=TRTSEQP, byperiod=APERIOD/APERIODC

ae <- adam$adae %>% filter(SAFFL == "Y") %>%
  transmute(
    Sequence    = .data[[dv$seqvar]],               # TRTSEQP  (participant's randomized order)
    Participant     = str_extract(USUBJID, "[^-]+$"),   # short site-participant id
    Period      = .data[[dv$byperiod[2]]],          # APERIODC (e.g. "Period 1")
    Treatment   = .data[[dv$trtvar]],               # TRTA (treatment in effect at onset)
    SOC         = AESOC,
    `Preferred Term` = AEDECOD,
    `Onset Day` = ASTDY,                            # numeric study day (display)
    `Dur (d)`   = ADURN,
    Severity    = factor(AESEVN, levels = 1:3, labels = c("Mild","Moderate","Severe")),
    Serious     = if_else(AESER == "Y", "Yes", "No"),
    TEAE        = if_else(TRTEMFL == "Y", "Yes", "No"),
    Relationship = AREL,
    `Action Taken` = AEACN,
    Outcome     = AEOUT,
    ## sort keys (kept numeric/date, dropped before render)
    seqn = .data[[dv$seqvarn]], pern = .data[[dv$byperiod[1]]], ASTDT) %>%
  arrange(seqn, Participant, pern, ASTDT, `Preferred Term`)   # sort on numeric/date keys, not text

ttl <- tfl_titles(num = "16.2.7.1", type = "Listing", text = "Listing of Adverse Events",
   pop = "Safety Population",
   foot = paste0("Crossover: Sequence (TRTSEQP) and Period (APERIODC) shown so each AE maps to the treatment in effect at onset. ",
                 "TEAE = treatment-emergent. SAE = serious. Rel = relationship per investigator/analysis. MedDRA v27.0."))

## render: one block per sequence (page break), columns as ordered above
## listings::create_listing(ae, ...) or gt::gt(ae %>% select(-seqn,-pern,-ASTDT))
print(ae %>% select(-seqn, -pern, -ASTDT))
