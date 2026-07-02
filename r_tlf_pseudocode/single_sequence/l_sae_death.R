################################################################################
# LISTING   : l_sae_death  (Single-/fixed-sequence DDI)
# TITLE     : Listing of Serious Adverse Events and Deaths by Period
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADAE (AESER == "Y" OR AESDTH == "Y"); DTHDT merged from ADSL
# NOTE      : PSEUDOCODE. One row per serious / fatal AE record, ordered by
#             participant then onset. DDI: shows the PERIOD (APERIODC) of onset so
#             a reviewer can attribute the event to victim-alone (Period 1) vs
#             victim+perpetrator (Period 2). NO randomized sequence column
#             (single-/fixed-sequence) -- period replaces it. "Seriousness
#             Criteria" = concatenation of AESDTH/AESLIFE/AESHOSP/AESDISAB/
#             AESCONG/AESMIE (matching the SAS twin). "Death Date" comes from
#             DTHDT (merged from ADSL), NEVER the AE end date.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SINGLESEQ")                 # TRTA + APERIOD/APERIODC

period_col <- dv$byperiod[2]                    # "APERIODC"

## death date lives on ADSL; merge by USUBJID so non-fatal SAE rows show blank
dth_map <- adam$adsl %>% select(USUBJID, DTHDT)

## seriousness-criteria concatenation (mirrors the SAS catx logic)
ser_crit <- function(AESDTH, AESLIFE, AESHOSP, AESDISAB, AESCONG, AESMIE) {
  parts <- c(
    if_else(AESDTH   == "Y", "Death",                NA_character_),
    if_else(AESLIFE  == "Y", "Life-threatening",     NA_character_),
    if_else(AESHOSP  == "Y", "Hospitalization",      NA_character_),
    if_else(AESDISAB == "Y", "Disability",           NA_character_),
    if_else(AESCONG  == "Y", "Congenital anomaly",   NA_character_),
    if_else(AESMIE   == "Y", "Medically important",  NA_character_))
  paste(na.omit(parts), collapse = "; ")
}

sae <- adam$adae %>%
  filter(SAFFL == "Y", AESER == "Y" | AESDTH == "Y") %>%
  left_join(dth_map, by = "USUBJID") %>%
  rowwise() %>%
  mutate(`Seriousness Criteria` =
           ser_crit(AESDTH, AESLIFE, AESHOSP, AESDISAB, AESCONG, AESMIE)) %>%
  ungroup() %>%
  transmute(
    Participant     = str_extract(USUBJID, "[^-]+$"),
    Period      = .data[[period_col]],               # victim alone / + perpetrator
    Treatment   = .data[[dv$trtvar]],                # TRTA actual treatment in that period
    SOC         = AESOC,
    `Preferred Term` = AEDECOD,
    `Onset Day` = ASTDY,
    `Resol. Day` = AENDY,
    Severity    = factor(AESEVN, levels = 1:3, labels = c("Mild","Moderate","Severe")),
    `Seriousness Criteria` = `Seriousness Criteria`,
    Relationship = AREL,
    `Action Taken` = AEACN,
    Outcome     = AEOUT,
    `Death Date` = if_else(is.na(DTHDT), NA_character_, format(DTHDT, "%Y-%m-%d")),
    APERIODN, ASTDT) %>%
  arrange(Participant, APERIODN, ASTDT, `Preferred Term`)

ttl <- tfl_titles(num = "16.2.7.3", type = "Listing",
   text = "Listing of Serious Adverse Events and Deaths by Period",
   pop = "Safety Population",
   foot = paste("DDI: Period 1 = victim alone (reference); Period 2 = victim +",
                "perpetrator (test). Includes any AE with AESER='Y' or AESDTH='Y'.",
                "Seriousness Criteria = AESDTH/AESLIFE/AESHOSP/AESDISAB/AESCONG/",
                "AESMIE. Death Date from DTHDT (ADSL). Rel = relationship to study",
                "drug per investigator/analysis. MedDRA v27.0."))

## render: one block per participant; columns as ordered above
## listings::create_listing(sae, ...) or gt::gt(sae %>% select(-APERIODN, -ASTDT))
print(sae %>% select(-APERIODN, -ASTDT))
