################################################################################
# LISTING   : l_pk_conc  (MAD - Multiple Ascending Dose)
# TITLE     : Listing of Individual Plasma Concentrations
# POPULATION: PK Concentration Population (PKFL == "Y")
# INPUT     : ADPC (one row per sample: analyte, dosing day, nominal + actual
#             time, conc)
# NOTE      : PSEUDOCODE. One row per concentration record, ordered by dose
#             cohort, participant, analyte, dosing DAY, then ACTUAL time. Shows
#             nominal vs actual time, BLQ flag, and time deviation. Listings show
#             all collected samples (not only analysis-flagged). MAD = parallel
#             cohorts, REPEATED daily dosing: column = TRT01A = dose level; the
#             dosing day (AVISIT/ADY) distinguishes Day 1 (single dose) from
#             Day N (steady state) and carries the pre-dose troughs.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("MAD")

pc <- adam$adpc %>% filter(PKFL == "Y") %>%
  transmute(
    `Dose Cohort` = .data[[dv$trtvar]],               # = dose level
    Participant     = str_extract(USUBJID, "[^-]+$"),     # short site-participant id
    Analyte     = PARAM,
    `Dosing Day`= AVISIT,                              # Day 1 ... Day N (dosing occasion)
    Visit       = AVISIT,
    `Nominal Time (h)` = ATPTN,                        # nominal time within the dosing interval
    `Actual Time (h)`  = ATM,                          # actual elapsed time (PK)
    `Time Dev (h)`     = round(ATM - ATPTN, 3),        # actual - nominal deviation
    `Concentration`    = if_else(AVAL <= 0 | toupper(coalesce(AVALC,"")) == "BLQ",
                                 "BLQ", sprintf("%.4g", AVAL)),
    Unit        = AVALU,
    `Analysis Record` = if_else(ANL01FL == "Y", "Y", ""),  # included in summary?
    ADY, ATM, ATPTN) %>%
  arrange(`Dose Cohort`, Participant, Analyte, ADY, ATM)  # sort on day then numeric actual time

ttl <- tfl_titles(num = "16.2.11.1", type = "Listing",
   text = "Listing of Individual Plasma Concentrations",
   pop  = "Pharmacokinetic Concentration Population",
   foot = paste("BLQ = below limit of quantification. Nominal time = protocol-scheduled",
                "(relative to the day's dose); Actual time = recorded sample time used for",
                "parameter derivation. Analysis Record = Y if included in concentration summary.",
                "MAD: repeated daily dosing; Dosing Day distinguishes Day 1 (single dose)",
                "from Day N (steady state)."))

## render: one block per dose cohort -> participant -> dosing day (page break by participant)
## listings::create_listing(...) or gt::gt(pc %>% select(-ADY, -ATM, -ATPTN))
print(pc %>% select(-ADY, -ATM, -ATPTN))
