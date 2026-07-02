################################################################################
# LISTING   : l_pk_conc  (SAD - Single Ascending Dose)
# TITLE     : Listing of Individual Plasma Concentrations
# POPULATION: PK Concentration Population (PKFL == "Y")
# INPUT     : ADPC (one row per sample: analyte, nominal + actual time, conc)
# NOTE      : PSEUDOCODE. One row per concentration record, ordered by dose
#             cohort, participant, analyte, then ACTUAL time. Shows nominal vs actual
#             time, BLQ flag, and time deviation. Listings show all collected
#             samples (not only analysis-flagged). SAD = parallel cohorts:
#             column = TRT01A = dose level (single dose, no second occasion).
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SAD")

pc <- adam$adpc %>% filter(PKFL == "Y") %>%
  transmute(
    `Dose Cohort` = .data[[dv$trtvar]],               # = dose level
    Participant     = str_extract(USUBJID, "[^-]+$"),     # short site-participant id
    Analyte     = PARAM,
    Visit       = AVISIT,
    `Nominal Time (h)` = ATPTN,
    `Actual Time (h)`  = NRRELTM,                      # actual elapsed time (PK) -- same var as SAS
    `Time Dev (h)`     = round(NRRELTM - ATPTN, 3),    # actual - nominal deviation
    `Concentration`    = if_else(AVAL <= 0 | toupper(coalesce(AVALC,"")) == "BLQ",
                                 "BLQ", sprintf("%.4g", AVAL)),
    Unit        = AVALU,
    `Analysis Record` = if_else(ANL01FL == "Y", "Y", ""),  # included in summary?
    NRRELTM, ATPTN) %>%
  arrange(`Dose Cohort`, Participant, Analyte, NRRELTM)    # sort on numeric actual time

ttl <- tfl_titles(num = "16.2.11.1", type = "Listing",
   text = "Listing of Individual Plasma Concentrations",
   pop  = "Pharmacokinetic Concentration Population",
   foot = paste("BLQ = below limit of quantification. Nominal time = protocol-scheduled;",
                "Actual time = recorded sample time used for parameter derivation.",
                "Analysis Record = Y if included in concentration summary.",
                "Single ascending dose: one dosing occasion per participant."))

## render: one block per dose cohort then participant (page break by participant)
## listings::create_listing(...) or gt::gt(pc %>% select(-NRRELTM, -ATPTN))
print(pc %>% select(-NRRELTM, -ATPTN))
