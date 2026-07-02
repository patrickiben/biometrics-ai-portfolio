################################################################################
# LISTING   : l_ecg  (Crossover - 2x2 or Williams)
# TITLE     : Listing of Electrocardiogram (ECG) Results
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADEG (all ECG parameters)
# NOTE      : PSEUDOCODE. One row per ECG assessment, ordered by SEQUENCE
#             (TRTSEQPN) then participant, then treatment PERIOD then timepoint
#             (matches the SAS twin's sequence-first order). Crossover: show treatment
#             (dv$trtvar = TRTA), the period (dv$byperiod = APERIODC) and
#             sequence (dv$seqvar = TRTSEQP) so the within-participant crossover
#             structure is legible. Includes overall interpretation (EGINTP) and
#             the reference-range indicator. Sort on numeric date/period/time
#             keys, never on display text. Listings show all records.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("CROSSOVER")                 # trtvar=TRTA; seqvar=TRTSEQP; byperiod=APERIOD/APERIODC

eg <- adam$adeg %>% filter(SAFFL == "Y") %>%
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
    `NR Ind`   = ANRIND,                                 # LOW / NORMAL / HIGH
    Interp     = EGINTP,                                  # Normal / Abnormal NCS / Abnormal CS
    ## numeric sort keys -- kept out of the printed body
    SeqN = .data[[dv$seqvarn]],                          # TRTSEQPN (sequence-first order)
    APERIODn = .data[[dv$byperiod[1]]], AVISITN, ATPTN, ADT) %>%
  arrange(SeqN, Participant, APERIODn, AVISITN, ATPTN, ADT, Parameter)

ttl <- tfl_titles(num = "16.2.8.1", type = "Listing", text = "Listing of Electrocardiogram (ECG) Results",
   pop = "Safety Population",
   foot = "Ordered by sequence (TRTSEQP), participant, treatment period, then scheduled time. Baseline = period pre-dose value (ABLFL='Y'). Interp = overall ECG interpretation (EGINTP). NR Ind = reference-range indicator (ANRIND).")

## render: page-break by Participant; drop the numeric sort keys from the body
print(eg %>% select(-SeqN, -APERIODn, -AVISITN, -ATPTN, -ADT))
