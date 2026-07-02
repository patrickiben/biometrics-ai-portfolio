################################################################################
# LISTING   : l_sae_death  (Crossover - 2x2 or Williams)
# TITLE     : Listing of Serious Adverse Events and Deaths
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADAE (AESER == "Y" OR AESDTH == "Y")
# NOTE      : PSEUDOCODE. One row per SAE / death record, ordered by sequence,
#             participant, period, then onset. Crossover requires SEQUENCE
#             (dv$seqvar=TRTSEQP) and PERIOD (dv$byperiod=APERIOD/APERIODC) so
#             each serious event is traceable to the treatment in effect at
#             onset. Treatment = actual treatment (dv$trtvar=TRTA). Includes
#             seriousness criteria, relationship, action, outcome, and (if
#             applicable) death date. Listing-level filter, not treatment-
#             emergent only.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("CROSSOVER")                 # trtvar=TRTA, seqvar=TRTSEQP, byperiod=APERIOD/APERIODC

rel_set <- c("RELATED","POSSIBLE","PROBABLE","DEFINITE")

sae <- adam$adae %>%
  filter(SAFFL == "Y", AESER == "Y" | AESDTH == "Y") %>%
  left_join(adam$adsl %>% select(USUBJID, DTHDT), by = "USUBJID") %>%   # death date from ADSL
  transmute(
    Sequence    = .data[[dv$seqvar]],               # TRTSEQP
    Participant     = str_extract(USUBJID, "[^-]+$"),
    Period      = .data[[dv$byperiod[2]]],          # APERIODC
    Treatment   = .data[[dv$trtvar]],               # TRTA (treatment in effect at onset)
    SOC         = AESOC,
    `Preferred Term` = AEDECOD,
    `Onset Day` = ASTDY,
    `Dur (d)`   = ADURN,
    Severity    = factor(AESEVN, levels = 1:3, labels = c("Mild","Moderate","Severe")),
    `Seriousness Criteria` = {                       # which regulatory criteria were met (mirrors SAS catx)
      crit <- cbind(
        if_else(AESDTH   == "Y", "Death",                     ""),
        if_else(AESLIFE  == "Y", "Life-threatening",          ""),
        if_else(AESHOSP  == "Y", "Hospitalization",           ""),
        if_else(AESDISAB == "Y", "Disability",                ""),
        if_else(AESCONG  == "Y", "Congenital anomaly",        ""),
        if_else(AESMIE   == "Y", "Other medically important", ""))
      apply(crit, 1, function(x) paste(x[x != ""], collapse = "; "))
    },
    Serious     = if_else(AESER == "Y", "Yes", "No"),
    Fatal       = if_else(AESDTH == "Y", "Yes", "No"),
    `Death Date` = DTHDT,                            # death date (ADSL DTHDT); blank when not fatal
    Relationship = AREL,
    Related      = if_else(toupper(AREL) %in% rel_set, "Yes", "No"),
    `Action Taken` = AEACN,
    Outcome     = AEOUT,
    ## sort keys (dropped before render)
    seqn = .data[[dv$seqvarn]], pern = .data[[dv$byperiod[1]]], ASTDT) %>%
  arrange(seqn, Participant, pern, ASTDT, `Preferred Term`)

ttl <- tfl_titles(num = "16.2.7.2", type = "Listing",
   text = "Listing of Serious Adverse Events and Deaths",
   pop  = "Safety Population",
   foot = paste0("Includes any AE with AESER='Y' or AESDTH='Y'. Crossover: Sequence (TRTSEQP) and Period (APERIODC) shown to map ",
                 "each event to the treatment in effect at onset. Related = AREL in {Related, Possible, Probable, Definite}. MedDRA v27.0."))

## render: one block per sequence (page break), columns as ordered above
## listings::create_listing(sae, ...) or gt::gt(sae %>% select(-seqn,-pern,-ASTDT))
print(sae %>% select(-seqn, -pern, -ASTDT))
