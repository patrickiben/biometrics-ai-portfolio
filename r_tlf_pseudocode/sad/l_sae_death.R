################################################################################
# LISTING   : l_sae_death  (Single Ascending Dose)
# TITLE     : Listing of Serious Adverse Events and Deaths by Dose Level
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADAE (AESER == "Y" OR AESDTH == "Y" OR AEOUT == "FATAL");
#             ADSL (DTHDT merged in for the Death Date column)
# NOTE      : PSEUDOCODE. One row per serious/fatal AE record, ordered by ascending
#             dose (TRT01AN) then participant then onset. Restricts to SAEs and
#             deaths (not all AEs). Shows onset day, duration, severity, serious/
#             fatal flags, TEAE, relationship, action, outcome, seriousness criteria,
#             and death date. Listings show all qualifying events regardless of
#             treatment-emergence; a TEAE flag is included for reviewer context.
#             Death Date is sourced from DTHDT (merged from ADSL), NEVER AEENDTC,
#             and is blank for non-fatal rows -- matches the SAS twin.
#             SAD: treatment column = dose level (dv$trtvar = TRT01A, one single
#             dose per participant); blocks ordered by ascending dose (TRT01AN).
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SAD")                       # trtvar = TRT01A, trtnvar = TRT01AN

## --- serious and/or fatal AE records; merge DTHDT (death date) from ADSL -----
sae <- adam$adae %>%
  filter(SAFFL == "Y", AESER == "Y" | AESDTH == "Y" | toupper(AEOUT) == "FATAL") %>%
  left_join(adam$adsl %>% select(USUBJID, DTHDT), by = "USUBJID") %>%
  transmute(
    `Dose Level` = .data[[dv$trtvar]],
    DoseN        = .data[[dv$trtnvar]],             # numeric dose -> ascending block order
    Participant      = str_extract(USUBJID, "[^-]+$"),  # short site-participant id
    SOC          = AESOC,
    `Preferred Term` = AEDECOD,
    `Onset Day`  = ASTDY,                           # numeric study day
    `Dur (d)`    = ADURN,
    Severity     = factor(AESEVN, levels = 1:3, labels = c("Mild","Moderate","Severe")),
    Serious      = if_else(AESER  == "Y", "Yes", "No"),
    Fatal        = if_else(AESDTH == "Y", "Yes", "No"),
    TEAE         = if_else(TRTEMFL == "Y", "Yes", "No"),
    Relationship = AREL,                            # verbatim AREL (listing = traceable)
    `Action Taken` = AEACN,
    Outcome      = AEOUT,
    `Seriousness Criteria` = {                      # which regulatory criteria were met (mirrors SAS catx)
      crit <- cbind(
        if_else(AESDTH   == "Y", "Death",                     ""),
        if_else(AESLIFE  == "Y", "Life-threatening",          ""),
        if_else(AESHOSP  == "Y", "Hospitalization",           ""),
        if_else(AESDISAB == "Y", "Disability",                ""),
        if_else(AESCONG  == "Y", "Congenital anomaly",        ""),
        if_else(AESMIE   == "Y", "Other medically important", ""))
      apply(crit, 1, function(x) paste(x[x != ""], collapse = "; "))
    },
    `Death Date` = if_else(is.na(DTHDT), "", format(DTHDT, "%Y-%m-%d")),  # DTHDT from ADSL, blank if non-fatal
    ASTDT) %>%
  arrange(DoseN, `Dose Level`, Participant, ASTDT, `Preferred Term`)  # ascending dose; sort on date, not text

ttl <- tfl_titles(
  num  = "16.2.7.2",
  type = "Listing",
  text = "Listing of Serious Adverse Events and Deaths by Dose Level",
  pop  = "Safety Population",
  foot = paste("SAD: one block per single ascending dose level (TRT01A), ordered",
               "low to high. Includes records with AESER==Y (serious) and/or",
               "AESDTH==Y or a fatal outcome. TEAE = treatment-emergent (TRTEMFL=Y).",
               "Death Date from ADSL DTHDT (blank if non-fatal).",
               "Relationship per investigator/analysis. MedDRA v27.0."))

## render: one block per dose level (page break), ascending; drop sort-key cols.
## listings::create_listing(sae, ...) or gt::gt(sae %>% select(-ASTDT, -DoseN))
print(sae %>% select(-ASTDT, -DoseN))
