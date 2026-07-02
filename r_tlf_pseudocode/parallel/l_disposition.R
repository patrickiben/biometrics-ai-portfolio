################################################################################
# LISTING   : l_disposition  (Parallel-group)
# TITLE     : Listing of Participant Disposition
# POPULATION: All Randomized Participants (RANDFL == "Y")
# INPUT     : ADSL
# NOTE      : PSEUDOCODE. One row per participant. Treatment, key milestone dates,
#             study/treatment completion status and discontinuation reason.
#             Parallel-group: one treatment per participant (TRT01A), no period or
#             sequence columns. Listing shows all randomized participants.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("PARALLEL")                 # -> trtvar = TRT01A, trtnvar = TRT01AN

disp <- adam$adsl %>% filter(RANDFL == "Y") %>%
  transmute(
    Treatment        = .data[[dv$trtvar]],
    Participant          = str_extract(USUBJID, "[^-]+$"),       # short site-participant id
    Age              = AGE,
    Sex              = SEX,
    `Safety Pop`     = if_else(SAFFL  == "Y", "Yes", "No"),
    `PK Pop`         = if_else(PKFL   == "Y", "Yes", "No"),
    `Randomized`     = RANDDT,                                # randomization date
    `First Dose`     = TRTSDT,                                # treatment start date
    `Last Dose`      = TRTEDT,                                # treatment end date
    `Study Status`   = EOSSTT,                                # COMPLETED / DISCONTINUED
    `Completed`      = if_else(COMPLFL == "Y", "Yes", "No"),
    `Disc. Reason`   = DCSREAS,                               # NA if completed
    `EOS Date`       = EOSDT,
    .RANDDT          = RANDDT) %>%                            # numeric sort key
  arrange(Treatment, .RANDDT, Participant)                       # sort on date, not text

ttl <- tfl_titles(num = "16.2.1", type = "Listing",
   text = "Listing of Participant Disposition",
   pop  = "All Randomized Participants",
   foot = "One row per randomized participant. Disc. Reason from ADSL DCSREAS (blank if completed). Study status = EOSSTT.")

## render: one block per treatment (page break), columns as ordered above
## listings::create_listing(disp, ...) or gt::gt(disp %>% select(-.RANDDT))
print(disp %>% select(-.RANDDT))
