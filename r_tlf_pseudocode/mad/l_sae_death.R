################################################################################
# LISTING   : l_sae_death  (Multiple Ascending Dose)
# TITLE     : Listing of Serious Adverse Events and Deaths
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADAE (AESER == "Y" OR AESDTH == "Y")
# NOTE      : PSEUDOCODE. MAD = parallel ascending-dose cohorts, repeated dosing;
#             one treatment per participant, so the treatment column is the dose
#             level (dv$trtvar = TRT01A). One row per serious/fatal AE record,
#             ordered by dose then participant then onset. Restricts to SAEs and
#             deaths (not all AEs). An Onset Day (ASTDY) column locates the event
#             within the multi-day dosing period. Listings show all qualifying
#             events regardless of treatment-emergence; a TEAE flag is included
#             for reviewer context.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("MAD")                       # trtvar = TRT01A (dose level)

## --- death date from ADSL (DTHDT), merged on participant -------------------
dth_lk <- adam$adsl %>% distinct(USUBJID, DTHDT)

## --- serious and/or fatal AE records ---------------------------------------
sae <- adam$adae %>%
  filter(SAFFL == "Y", AESER == "Y" | AESDTH == "Y") %>%
  left_join(dth_lk, by = "USUBJID") %>%
  mutate(
    ## seriousness criteria = concatenation of the seriousness flags (matches SAS)
    sercrit = {
      crit <- cbind(
        ifelse(AESDTH   == "Y", "Death",                NA),
        ifelse(AESLIFE  == "Y", "Life-threatening",     NA),
        ifelse(AESHOSP  == "Y", "Hospitalization",      NA),
        ifelse(AESDISAB == "Y", "Disability",           NA),
        ifelse(AESCONG  == "Y", "Congenital anomaly",   NA),
        ifelse(AESMIE   == "Y", "Medically important",  NA))
      apply(crit, 1, function(r) paste(r[!is.na(r)], collapse = "; "))
    }) %>%
  transmute(
    `Dose Level` = .data[[dv$trtvar]],
    `Dose (n)`   = .data[[dv$trtnvar]],             # numeric dose -> ascending sort key
    Participant      = str_extract(USUBJID, "[^-]+$"),  # short site-participant id
    SOC          = AESOC,
    `Preferred Term` = AEDECOD,
    `Onset Day`  = ASTDY,                           # numeric study day within dosing period
    `Dur (d)`    = ADURN,
    Severity     = factor(AESEVN, levels = 1:3, labels = c("Mild","Moderate","Severe")),
    Serious      = if_else(AESER  == "Y", "Yes", "No"),
    Fatal        = if_else(AESDTH == "Y", "Yes", "No"),
    TEAE         = if_else(TRTEMFL == "Y", "Yes", "No"),
    Relationship = AREL,                            # verbatim AREL (listing = traceable)
    `Action Taken` = AEACN,
    Outcome      = AEOUT,
    `Seriousness Criteria` = sercrit,               # concatenated seriousness flags
    `Death Date` = DTHDT,                           # from ADSL DTHDT (never AEENDTC)
    ASTDT) %>%
  arrange(`Dose (n)`, Participant, ASTDT, `Preferred Term`)  # dose ascending, then date (not text)

ttl <- tfl_titles(
  num  = "16.2.7.2",
  type = "Listing",
  text = "Listing of Serious Adverse Events and Deaths",
  pop  = "Safety Population",
  foot = paste("MAD: one treatment per participant = dose level (blocks ascending by dose).",
               "Onset Day = study day within the repeated-dosing period.",
               "Includes records with AESER==Y (serious) and/or AESDTH==Y (fatal).",
               "TEAE = treatment-emergent (TRTEMFL=Y). Relationship per investigator/analysis.",
               "MedDRA v27.0."))

## render: one block per dose level (page break), ascending; drop sort-key columns.
## listings::create_listing(sae, ...) or gt::gt(sae %>% select(-ASTDT, -`Dose (n)`))
print(sae %>% select(-ASTDT, -`Dose (n)`))
