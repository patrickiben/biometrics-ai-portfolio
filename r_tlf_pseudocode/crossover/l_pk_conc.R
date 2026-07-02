################################################################################
# LISTING   : l_pk_conc  (Crossover - 2x2 or Williams)
# TITLE     : Listing of Individual Plasma Drug Concentrations
# POPULATION: PK Concentration Population (PKFL == "Y")
# INPUT     : ADPC (AVAL = concentration; ATPT/ATPTN nominal time; ARRLT actual
#             relative time; APERIOD/APERIODC; TRTA; TRTSEQP)
# NOTE      : PSEUDOCODE. One row per concentration record, ordered by sequence,
#             participant, period, then nominal time. Crossover: show the planned
#             SEQUENCE (dv$seqvar) and the within-participant PERIOD (dv$byperiod)
#             plus the actual treatment (dv$trtvar) so each sample's period AND
#             which drug it belongs to are both visible. BLQ values displayed as
#             "BLQ" (AVALC) rather than the numeric imputation.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("CROSSOVER")                 # TRTA + APERIOD + TRTSEQP

conc <- adam$adpc %>% filter(PKFL == "Y") %>%
  transmute(
    Sequence  = .data[[dv$seqvar]],             # TRTSEQP  (planned sequence)
    Participant   = str_extract(USUBJID, "[^-]+$"), # short site-participant id
    Period    = .data[[dv$byperiod[1]]],        # APERIOD  (numeric, sort key)
    PeriodC   = .data[[dv$byperiod[2]]],        # APERIODC (label)
    Treatment = .data[[dv$trtvar]],             # TRTA     (actual drug that period)
    Analyte   = PARAM,
    `Nominal Time` = ATPT,
    ATPTN,                                       # numeric nominal time (sort key)
    `Actual Time`  = sprintf("%.2f", ARRLT),    # actual relative time (h)
    ## display BLQ as character; otherwise the imputed/derived numeric AVAL
    Concentration = if_else(!is.na(AVALC) & toupper(AVALC) == "BLQ",
                            "BLQ", sprintf("%.3g", AVAL)),
    Unit      = AVALU) %>%
  arrange(Sequence, Participant, Period, ATPTN)     # sort on numeric keys, not text

ttl <- tfl_titles(num = "16.2.10.1", type = "Listing",
   text = "Listing of Individual Plasma Drug Concentrations",
   pop  = "Pharmacokinetic Concentration Population",
   foot = paste("BLQ = below limit of quantification. Sequence = planned treatment",
                "sequence (TRTSEQP); Period = within-participant study period; Treatment =",
                "actual treatment received that period (TRTA). Times in hours post-dose."))

## render: one block per Sequence -> Participant (page break by participant), columns as
## ordered above. listings::create_listing(conc, ...) or gt::gt(conc %>% select(-ATPTN))
print(conc %>% select(-ATPTN))
