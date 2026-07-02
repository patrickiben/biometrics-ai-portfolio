################################################################################
# LISTING   : l_pd  (Crossover - 2x2 or Williams)
# TITLE     : Listing of Pharmacodynamic Biomarker Results by Participant, Sequence,
#             Period and Nominal Time
# POPULATION: Pharmacodynamic Population (PDFL == "Y" on ADPD)
# INPUT     : ADPD (PARAMCD/PARAM, AVAL, BASE, CHG, AVISIT/ATPT, APERIOD/APERIODC,
#             TRTA, TRTSEQP)
# NOTE      : PSEUDOCODE. One row per participant x parameter x period x timepoint.
#             Crossover ordering keys: sequence (TRTSEQP) -> participant -> period
#             (APERIOD) -> treatment (TRTA) -> nominal time, so a reviewer can
#             follow each participant through the crossover. Shows period-specific
#             baseline (BASE) and change (CHG) as carried on ADPD (no re-derive).
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("CROSSOVER")                 # TRTA + APERIOD + TRTSEQP

## --- assemble listing rows --------------------------------------------------
## participant ordering key = sequence then USUBJID; within participant by period+time.
lst <- adam$adpd %>%
  filter(PDFL == "Y") %>%
  transmute(
    Sequence  = .data[[dv$seqvar]],             # TRTSEQP  (participant-level order)
    SeqN      = .data[[dv$seqvarn]],            # TRTSEQPN (sort key)
    Participant   = USUBJID,
    Period    = .data[[dv$byperiod[1]]],        # APERIOD
    PeriodC   = .data[[dv$byperiod[2]]],        # APERIODC
    Treatment = .data[[dv$trtvar]],             # TRTA in that period
    Parameter = PARAM,
    Visit     = AVISIT,
    Time      = ATPT,
    TimeN     = ATPTN,
    Result    = sprintf("%.2f", AVAL),
    Baseline  = sprintf("%.2f", BASE),
    Change    = ifelse(ABLFL == "Y", "", sprintf("%+.2f", CHG))) %>%
  arrange(SeqN, Participant, Period, TimeN)        # numeric Period (APERIOD), not PeriodC label

ttl <- tfl_titles(num = "16.2.8.3", type = "Listing",
   text = "Pharmacodynamic Biomarker Results by Participant, Sequence, Period and Time",
   pop  = "Pharmacodynamic Population",
   foot = paste("Ordered by sequence (TRTSEQP), participant, period (APERIOD), then nominal time.",
                "Baseline and change are the period-specific values carried on ADPD.",
                "Change blank at the period baseline timepoint."))

## render: rtables listing (rlistings::as_listing) or gt; keep order above.
print(lst, n = 50)
