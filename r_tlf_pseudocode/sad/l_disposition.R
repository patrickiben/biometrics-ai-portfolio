################################################################################
# LISTING   : l_disposition  (Single Ascending Dose)
# TITLE     : Listing of Participant Disposition
# POPULATION: All Enrolled Participants (ENRLFL == "Y")
# INPUT     : ADSL
# NOTE      : PSEUDOCODE. One row per participant. SAD: parallel ascending-dose
#             cohorts, ONE treatment per participant -> NO sequence/period columns.
#             Shows the assigned dose level (TRT01A = cohort), enrolled/
#             randomized/safety/PK population flags, single-dose date, study
#             completion status, and reason/date of any discontinuation.
#             ALL enrolled participants are listed (do NOT filter to SAFFL/RANDFL)
#             so screen-fails and pre-dose discontinuations stay visible; the
#             Randomized/Safety/PK population flags are shown as Yes/No columns.
#             Listing ordered by ascending dose level (cohort) then participant.
#             Display fields carried from ADSL (no re-derivation of analysis vars).
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SAD")                       # -> trtvar = TRT01A (dose level), trtnvar = TRT01AN

disp <- adam$adsl %>% filter(ENRLFL == "Y") %>%
  transmute(
    .dose_ord        = .data[[dv$trtnvar]],                   # numeric ascending sort key
    `Dose Level`     = .data[[dv$trtvar]],                    # assigned dose level / cohort
    Participant      = str_extract(USUBJID, "[^-]+$"),        # short site-participant id
    `Rand`           = if_else(RANDFL == "Y", "Yes", "No"),   # randomized; screen-fails stay visible
    `Safety Pop`     = if_else(SAFFL  == "Y", "Yes", "No"),   # received single dose
    `PK Pop`         = if_else(PKFL   == "Y", "Yes", "No"),
    `First Dose`     = RFSTDTC,                               # single-dose date (SAD)
    `Last Contact`   = RFENDTC,                               # last study contact (display)
    `Status`         = if_else(COMPLFL == "Y", "Completed", "Discontinued"),
    `Disc. Date`     = DCSDTC,                                # NA if completed
    `Disc. Reason`   = DCSREAS) %>%                           # NA if completed
  arrange(.dose_ord, Participant)                             # ascending dose, then participant

ttl <- tfl_titles(num = "16.1.1", type = "Listing",
   text = "Listing of Participant Disposition",
   pop  = "All Enrolled Participants",
   foot = "One row per enrolled participant (ENRLFL == \"Y\"). Dose Level = assigned cohort (TRT01A); single dose administered. Rows grouped by ascending dose level (TRT01AN) then participant. Randomized/Safety/PK population membership shown as Yes/No so screen-fails and pre-dose discontinuations remain visible. First Dose = single-dose date; Disc. Date/Reason from ADSL (DCSDTC / DCSREAS, blank if completed).")

## render: one block per dose cohort (page break), columns as ordered above
## listings::create_listing(disp, ...) or gt::gt(disp %>% select(-.dose_ord))
print(disp %>% select(-.dose_ord))
