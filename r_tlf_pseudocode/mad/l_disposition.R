################################################################################
# LISTING   : l_disposition  (Multiple Ascending Dose)
# TITLE     : Listing of Participant Disposition by Dose Cohort
# POPULATION: All Enrolled Participants (ENRLFL == "Y")
# INPUT     : ADSL
# NOTE      : PSEUDOCODE. One row per participant. Dose cohort (TRT01A), key
#             milestone dates, study/treatment completion status and
#             discontinuation reason. MAD = parallel dose cohorts, repeated
#             dosing; one dose level per participant -> no period/sequence columns,
#             but report regimen window (first/last dose) since dosing is multi-day,
#             plus #Doses (CUMDOSEN) and the PK steady-state flag (PKSSFL) so the
#             dosing duration required for steady-state/Rac PK is visible. Listed on
#             All Enrolled so screen-failures / pre-dose discontinuations remain
#             visible; SAFFL/PKFL/PKSSFL shown as Yes/No columns. Blocked by cohort.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("MAD")                       # -> trtvar = TRT01A (dose level), trtnvar = TRT01AN

disp <- adam$adsl %>% filter(ENRLFL == "Y") %>%
  transmute(
    `Dose Level`     = .data[[dv$trtvar]],                    # assigned dose level / cohort
    Site                 = SITEID,                               # site id
    Participant          = str_extract(USUBJID, "[^-]+$"),       # short site-participant id
    `Rand`           = if_else(RANDFL  == "Y", "Yes", "No"),  # randomized
    `Safety Pop`     = if_else(SAFFL   == "Y", "Yes", "No"),
    `PK Pop`         = if_else(PKFL    == "Y", "Yes", "No"),
    `PKss Pop`       = if_else(PKSSFL  == "Y", "Yes", "No"),  # PK steady-state population
    `Randomized`     = RANDDT,                                # randomization date
    `First Dose`     = TRTSDT,                                # regimen start date (Day 1)
    `Last Dose`      = TRTEDT,                                # regimen end date (Day N)
    `# Doses`        = CUMDOSEN,                              # number of doses received
    `EOS Date`       = EOSDT,                                 # end-of-study date (milestone)
    `Study Status`   = EOSSTT,                                # COMPLETED / DISCONTINUED
    `Completed`      = if_else(COMPLFL == "Y", "Yes", "No"),  # completed full dosing regimen
    `Disc. Reason`   = DCSREAS,                               # NA if completed
    .DOSEORD         = .data[[dv$trtnvar]]) %>%               # ascending dose sort key
  arrange(.DOSEORD, Site, Participant)                           # cohort asc, then site, then participant

ttl <- tfl_titles(num = "16.2.1", type = "Listing",
   text = "Listing of Participant Disposition by Dose Cohort",
   pop  = "All Enrolled Participants",
   foot = "MAD: one row per enrolled participant, blocked by ascending dose cohort (TRT01A). Rand/Safety/PK/PKss shown as Yes/No so screen-failures and pre-dose discontinuations remain visible. First/Last Dose bracket the multi-day regimen; # Doses = CUMDOSEN. Study Status = EOSSTT; Completed = completed full dosing regimen (COMPLFL); Disc. Reason from ADSL DCSREAS (blank if completed).")

## render: one block per dose cohort (page break), columns as ordered above
## listings::create_listing(disp, ...) or gt::gt(disp %>% select(-.DOSEORD))
print(disp %>% select(-.DOSEORD))
