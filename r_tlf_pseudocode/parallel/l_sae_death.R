################################################################################
# LISTING   : l_sae_death  (Parallel-group)
# TITLE     : Listing of Serious Adverse Events and Deaths
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADAE (AESER == "Y" OR AESDTH == "Y")
# NOTE      : PSEUDOCODE. One row per serious/fatal AE record, ordered by
#             participant then onset. Restricts to SAEs and deaths (not all AEs).
#             Listings show all qualifying events regardless of treatment-
#             emergence; a TEAE flag is included for reviewer context.
#             Parallel: treatment column = TRT01A (one treatment per participant).
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("PARALLEL")                  # trtvar = TRT01A

## --- death date from ADSL (DTHDT), merged in by participant -----------------
dth <- adam$adsl %>% select(USUBJID, DTHDT)

## --- seriousness-criteria concatenation helper ------------------------------
## Concatenate every "Y" seriousness flag into one readable, traceable string.
ser_crit <- function(AESDTH, AESLIFE, AESHOSP, AESDISAB, AESCONG, AESMIE) {
  flags <- c(Death = AESDTH, `Life-threatening` = AESLIFE,
             Hospitalization = AESHOSP, Disability = AESDISAB,
             `Congenital anomaly` = AESCONG, `Other medically important` = AESMIE)
  paste(names(flags)[toupper(coalesce(flags, "")) == "Y"], collapse = "; ")
}

## --- serious and/or fatal AE records ---------------------------------------
sae <- adam$adae %>%
  filter(SAFFL == "Y", AESER == "Y" | AESDTH == "Y" | toupper(AEOUT) == "FATAL") %>%
  left_join(dth, by = "USUBJID") %>%
  rowwise() %>%
  mutate(`Seriousness Criteria` = ser_crit(AESDTH, AESLIFE, AESHOSP,
                                            AESDISAB, AESCONG, AESMIE)) %>%
  ungroup() %>%
  transmute(
    Treatment    = .data[[dv$trtvar]],
    Participant      = str_extract(USUBJID, "[^-]+$"),     # short site-participant id
    SOC          = AESOC,
    `Preferred Term` = AEDECOD,
    `Onset Day`  = ASTDY,                              # numeric study day
    `Dur (d)`    = ADURN,
    Severity     = factor(AESEVN, levels = 1:3, labels = c("Mild","Moderate","Severe")),
    Serious      = if_else(AESER  == "Y", "Yes", "No"),
    Fatal        = if_else(AESDTH == "Y", "Yes", "No"),
    TEAE         = if_else(TRTEMFL == "Y", "Yes", "No"),
    Relationship = AREL,                               # verbatim AREL (listing = traceable)
    `Action Taken` = AEACN,
    Outcome      = AEOUT,
    `Seriousness Criteria`,                            # concatenated Y flags
    `Death Date` = if_else(is.na(DTHDT), "", format(DTHDT, "%Y-%m-%d")),  # from ADSL
    ASTDT) %>%
  arrange(Treatment, Participant, ASTDT, `Preferred Term`)   # sort on date, not text

ttl <- tfl_titles(
  num  = "16.2.7.2",
  type = "Listing",
  text = "Listing of Serious Adverse Events and Deaths",
  pop  = "Safety Population",
  foot = paste("Includes records with AESER==Y (serious) and/or a fatal outcome.",
               "Seriousness Criteria = concatenated Y flags",
               "(AESDTH/AESLIFE/AESHOSP/AESDISAB/AESCONG/AESMIE).",
               "Death Date from ADSL DTHDT. TEAE = treatment-emergent (TRTEMFL=Y).",
               "Relationship per investigator/analysis. MedDRA v27.0."))

## render: one block per treatment (page break); drop sort-key date column.
## listings::create_listing(sae, ...) or gt::gt(sae %>% select(-ASTDT))
print(sae %>% select(-ASTDT))
