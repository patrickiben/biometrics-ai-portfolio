################################################################################
# LISTING   : l_disposition  (Crossover - 2x2 / Williams)
# TITLE     : Listing of Participant Disposition and Period Completion
# POPULATION: All Enrolled Participants (ENRLFL == "Y")
# INPUT     : ADSL
# NOTE      : PSEUDOCODE. One row per participant, ordered by sequence then participant.
#             Crossover-specific: shows the randomized SEQUENCE (TRTSEQP) and the
#             per-period analysis treatment (TRT01A/TRT02A on ADSL), plus overall
#             completion status and discontinuation reason. A disposition LISTING
#             shows ALL enrolled participants (incl. screen failures / pre-dose
#             discontinuations); SAFFL/PKFL are shown as Yes/No columns so they
#             stay visible rather than being used as a filter.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("CROSSOVER")   # seqvar = TRTSEQP, byperiod = APERIOD/APERIODC

## --- participant-level disposition frame (all enrolled) -------------------------
## per-period treatment carried on ADSL (TRT01A/TRT02A) -> no ADEX/SAFFL filter,
## so enrolled-but-not-dosed participants remain in the listing.
disp <- adam$adsl %>% filter(ENRLFL == "Y") %>%
  transmute(
    Sequence    = .data[[dv$seqvar]],          # TRTSEQP (randomized order, e.g. AB / BA)
    Participant     = str_extract(USUBJID, "[^-]+$"),
    `Period 1 Trt` = TRT01A,                    # analysis treatment per period (ADSL)
    `Period 2 Trt` = TRT02A,
    `Completed Study` = if_else(COMPLFL == "Y", "Yes", "No"),
    `Discontinued`    = if_else(DCSREAS != "" & !is.na(DCSREAS), "Yes", "No"),
    `DC Reason`       = if_else(is.na(DCSREAS) | DCSREAS == "", "-", DCSREAS),
    `DC Period`       = if_else(is.na(DCPERIOD), "-", as.character(DCPERIOD)),
    SAF         = if_else(SAFFL == "Y", "Yes", "No"),   # analysis-population membership
    PK          = if_else(PKFL  == "Y", "Yes", "No"),
    seqn = .data[[dv$seqvarn]]) %>%            # numeric sequence sort key
  arrange(seqn, Participant) %>%
  select(-seqn)

ttl <- tfl_titles(num = "16.2.1", type = "Listing",
   text = "Listing of Participant Disposition and Period Completion",
   pop  = "All Enrolled Participants",
   foot = "Sequence = randomized treatment order (TRTSEQP). Per-period treatment from ADSL (TRT01A/TRT02A). SAF/PK = analysis-population membership (Yes/No). One row per enrolled participant (incl. screen failures / pre-dose discontinuations); sorted by sequence then participant.")

## render: one block per sequence (page break), columns as ordered above
## listings::create_listing(disp, ...) or gt::gt(disp)
print(disp)
