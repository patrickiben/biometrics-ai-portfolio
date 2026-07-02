################################################################################
# LISTING   : l_pk_conc  (Parallel-group)
# TITLE     : Listing of Individual Plasma Concentrations
# POPULATION: PK Concentration Population (PKFL == "Y")
# INPUT     : ADPC (one row per sample: analyte, nominal + actual time, conc)
# NOTE      : PSEUDOCODE. One row per concentration record, ordered by treatment,
#             participant, analyte, then ACTUAL time. Shows nominal vs actual time,
#             BLQ flag, and time deviation. Listings show all collected samples
#             (not only analysis-flagged). Column = TRT01A = dose level.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("PARALLEL")

pc <- adam$adpc %>% filter(PKFL == "Y") %>%
  transmute(
    Treatment   = .data[[dv$trtvar]],                 # = dose level
    Participant     = str_extract(USUBJID, "[^-]+$"),     # short site-participant id
    Analyte     = PARAM,
    Visit       = AVISIT,
    `Nominal Time (h)` = ATPTN,
    `Actual Time (h)`  = ATM,                          # actual elapsed time (PK)
    `Time Dev (h)`     = round(ATM - ATPTN, 3),        # actual - nominal deviation
    `Concentration`    = if_else(AVAL <= 0 | toupper(coalesce(AVALC,"")) == "BLQ",
                                 "BLQ", sprintf("%.4g", AVAL)),
    Unit        = AVALU,
    `Analysis Record` = if_else(ANL01FL == "Y", "Y", ""),  # included in summary?
    ATM, ATPTN) %>%
  arrange(Treatment, Participant, Analyte, ATM)            # sort on numeric actual time

ttl <- tfl_titles(num = "16.2.11.1", type = "Listing",
   text = "Listing of Individual Plasma Concentrations",
   pop  = "Pharmacokinetic Concentration Population",
   foot = paste("BLQ = below limit of quantification. Nominal time = protocol-scheduled;",
                "Actual time = recorded sample time used for parameter derivation.",
                "Analysis Record = Y if included in concentration summary."))

## render: one block per treatment then participant (page break by participant)
## listings::create_listing(...) or gt::gt(pc %>% select(-ATM, -ATPTN))
print(pc %>% select(-ATM, -ATPTN))
