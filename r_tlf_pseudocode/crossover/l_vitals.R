################################################################################
# LISTING   : l_vitals  (Crossover - 2x2 or Williams)
# TITLE     : Listing of Vital Signs
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADVS (all vital-sign parameters)
# NOTE      : PSEUDOCODE. One row per vital-sign assessment, ordered within
#             participant by treatment PERIOD then timepoint. Crossover: show
#             treatment (dv$trtvar = TRTA), the period (dv$byperiod = APERIODC)
#             and sequence (dv$seqvar = TRTSEQP) so the within-participant crossover
#             structure is legible. Sort on numeric date/period/time keys,
#             never on display text. Listings show all records.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("CROSSOVER")                 # trtvar=TRTA; seqvar=TRTSEQP; byperiod=APERIOD/APERIODC

vs <- adam$advs %>% filter(SAFFL == "Y") %>%
  transmute(
    Participant    = str_extract(USUBJID, "[^-]+$"),         # short site-participant id
    Sequence   = .data[[dv$seqvar]],                     # TRTSEQP (fixed per participant)
    Period     = .data[[dv$byperiod[2]]],                # APERIODC (display)
    Treatment  = .data[[dv$trtvar]],                     # TRTA in that period
    Parameter  = PARAM,
    Visit      = AVISIT,
    `Time (h)` = ATPT,
    Baseline   = if_else(ABLFL == "Y", "Y", ""),
    Result     = sprintf("%.1f", AVAL),
    Unit       = AVALU,
    `Chg from BL` = if_else(is.na(CHG), "", sprintf("%.1f", CHG)),
    `Ref range`   = case_when(!is.na(A1LO) & !is.na(A1HI) ~ sprintf("%.1f - %.1f", A1LO, A1HI),
                              TRUE ~ ""),
    `NR Ind`   = ANRIND,                                 # LOW / NORMAL / HIGH
    ## sort keys (numeric) -- kept out of the printed body
    APERIODn = .data[[dv$byperiod[1]]], AVISITN, ATPTN, ADT) %>%
  arrange(Participant, APERIODn, AVISITN, ATPTN, ADT, Parameter)

ttl <- tfl_titles(num = "16.2.7.3", type = "Listing", text = "Listing of Vital Signs",
   pop = "Safety Population",
   foot = "Ordered within participant by treatment period then scheduled time. Baseline = period pre-dose value (ABLFL='Y'). NR Ind = reference-range indicator (ANRIND).")

## render: page-break by Participant; drop the numeric sort keys from the body
print(vs %>% select(-APERIODn, -AVISITN, -ATPTN, -ADT))
