################################################################################
# LISTING   : l_pk_conc  (Single-/fixed-sequence DDI)
# TITLE     : Listing of Individual Plasma Concentrations of the Victim Drug
# POPULATION: PK Concentration Population (PKFL == "Y")
# INPUT     : ADPC (one row per sample: analyte, period, nominal + actual time, conc)
# NOTE      : PSEUDOCODE. One row per concentration record, ordered by participant,
#             study PERIOD, analyte, then NOMINAL time (ATPTN) -- same sort key as
#             the SAS twin. Single-/fixed-sequence DDI: show the within-participant
#             PERIOD (dv$byperiod) so the paired reference-vs-test structure is
#             explicit; there is NO randomized sequence, so the fixed sequence
#             label (dv$seqvar) is shown once as context only. Shows nominal vs
#             actual time, BLQ flag, time deviation. BLQ is flagged from the AVALC
#             token only (same rule as SAS). Listings show all collected samples
#             (not only analysis-flagged).
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SINGLESEQ")                 # period via dv$byperiod; fixed seq

pc <- adam$adpc %>% filter(PKFL == "Y") %>%
  transmute(
    Participant     = str_extract(USUBJID, "[^-]+$"),     # short site-participant id
    Sequence    = .data[[dv$seqvar]],                 # fixed sequence label (context only)
    Period      = .data[[dv$byperiod[1]]],            # APERIOD numeric (sort key)
    `Period (Treatment)` = .data[[dv$byperiod[2]]],   # APERIODC label: Reference / Test
    Analyte     = PARAM,
    Visit       = AVISIT,
    `Nominal Time (h)` = ATPTN,
    `Actual Time (h)`  = ATM,                          # actual elapsed time (PK)
    `Time Dev (h)`     = round(ATM - ATPTN, 3),        # actual - nominal deviation
    `Concentration`    = if_else(toupper(coalesce(AVALC,"")) == "BLQ",
                                 "BLQ", sprintf("%.4g", AVAL)),   # BLQ from AVALC token only
    Unit        = AVALU,
    `Analysis Record` = if_else(ANL01FL == "Y", "Y", ""),  # included in summary?
    ATM, ATPTN) %>%
  arrange(Participant, Period, Analyte, ATPTN)             # participant -> period -> nominal time

ttl <- tfl_titles(num = "16.2.10.1", type = "Listing",
   text = "Listing of Individual Plasma Concentrations of the Victim Drug",
   pop  = "Pharmacokinetic Concentration Population",
   foot = paste("BLQ = below limit of quantification. Period 1 = victim alone (reference),",
                "Period 2 = victim + perpetrator (test); fixed-sequence design (no randomized sequence).",
                "Nominal time = protocol-scheduled; Actual time = recorded sample time used for",
                "parameter derivation. Analysis Record = Y if included in the concentration summary."))

## render: one block per participant, page break by participant; within-participant period
## blocks adjacent so reference vs test are easy to compare.
## listings::create_listing(...) or gt::gt(pc %>% select(-ATM, -ATPTN))
print(pc %>% select(-ATM, -ATPTN))
