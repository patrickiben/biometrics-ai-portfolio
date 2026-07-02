################################################################################
# LISTING   : l_disposition  (Single-/Fixed-Sequence DDI)
# TITLE     : Listing of Participant Disposition and Period Completion
# POPULATION: All Enrolled Participants
# INPUT     : ADSL
# NOTE      : PSEUDOCODE. One row per participant, ordered by fixed sequence then
#             participant. ALL ENROLLED -- NOT filtered to SAFFL -- so screen-fail
#             and pre-dose discontinuations remain visible; SAFFL/PKFL are shown
#             as Yes/No columns (mirroring the SAS twin) rather than used as a row
#             filter. Single-/fixed-sequence design: shows the ONE fixed treatment
#             order (dv$seqvar = TRTSEQP), per-PERIOD completion (COMPP1FL/COMPP2FL),
#             end-of-study status (EOSSTT) and discontinuation reason. No
#             randomized sequence column.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SINGLESEQ")                 # seqvar = TRTSEQP, seqvarn = TRTSEQPN
options(tfl.study = env$study)

## one row per participant; ALL ENROLLED (no SAFFL filter). Period-completion and
## EOS variable names match the SAS twin (COMPP1FL/COMPP2FL, EOSSTT).
disp <- adam$adsl %>%
  transmute(
    Sequence       = .data[[dv$seqvar]],               # fixed treatment order
    SequenceN      = .data[[dv$seqvarn]],              # numeric sort key
    Participant        = str_extract(USUBJID, "[^-]+$"),    # short site-participant id
    `Safety Pop`   = if_else(SAFFL == "Y", "Yes", "No"),   # shown, not filtered
    `PK Pop`       = if_else(PKFL  == "Y", "Yes", "No"),
    `First Dose Date` = RFSTDTC,                            # match SAS twin column
    `Period 1 (Ref)`  = if_else(COMPP1FL == "Y", "Completed",
                                if_else(is.na(TR01SDTM), "Not dosed", "Discontinued")),
    `Period 2 (Test)` = if_else(COMPP2FL == "Y", "Completed",
                                if_else(is.na(TR02SDTM), "Not dosed", "Discontinued")),
    `End of Study`    = str_to_title(EOSSTT),              # Completed / Discontinued
    `Discont. Reason` = if_else(EOSSTT == "DISCONTINUED", DCSREAS, NA_character_)) %>%
  arrange(SequenceN, Participant) %>%                       # sort on numeric key, not text
  select(-SequenceN)

ttl <- tfl_titles(num = "16.2.1", type = "Listing",
   text = "Listing of Participant Disposition and Period Completion",
   pop = "All Enrolled Participants",
   foot = paste("Single-fixed-sequence DDI: Period 1 = reference (victim alone),",
                "Period 2 = test (victim + perpetrator). All enrolled participants",
                "shown; Safety/PK population membership flagged as Yes/No so",
                "screen-fail and pre-dose discontinuations remain visible. One",
                "fixed treatment order; no randomized sequence."))

## render: ordered by fixed sequence then participant; columns as above
## listings::create_listing(disp, ...) or gt::gt(disp)
print(disp)
