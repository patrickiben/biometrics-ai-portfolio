################################################################################
# LISTING   : l_ada  (Crossover - 2x2 or Williams)
# TITLE     : Listing of Anti-Drug Antibody Results by Participant, Sequence, Period
#             and Time
# POPULATION: Immunogenicity / ADA-Evaluable Population (ISEVALFL == "Y")
# INPUT     : ADIS (PARCAT1 = "ADA"; PARAM = ADA / NAb, AVALC = Positive/Negative,
#             AVAL = titer; status flags ADABLFL/TEADAFL/ADAPERFL/ADATRNFL/NABFL;
#             AVISIT/ADT, APERIOD/APERIODC, TRTA, TRTSEQP)
# NOTE      : PSEUDOCODE. One row per participant x assay x period x sample. Crossover
#             ordering: sequence (TRTSEQP) -> participant -> period (APERIOD) ->
#             treatment (TRTA) -> visit/time, so a reviewer can trace ADA status
#             across periods and washout. ADA status = participant-level
#             immunogenicity flags carried on ADIS (no re-derivation); shows
#             titer where positive.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("CROSSOVER")                 # TRTA + APERIOD + TRTSEQP

## --- assemble ADA + NAb listing rows ----------------------------------------
## ADA status string built from ADIS flags (no re-derivation), mirroring the SAS
## catx(): baseline+ / treatment-emergent / persistent vs transient / NAb+.
lst <- adam$adis %>%
  filter(ISEVALFL == "Y", PARCAT1 == "ADA") %>%   # immunogenicity-evaluable; ADA category
  mutate(
    status = {
      crit <- cbind(
        if_else(ADABLFL  == "Y", "Baseline+",                        ""),
        if_else(TEADAFL  == "Y", "Trt-emergent",                     ""),
        if_else(ADAPERFL == "Y", "Persistent",
                if_else(ADATRNFL == "Y", "Transient",                "")),
        if_else(NABFL    == "Y", "NAb+",                             ""))
      apply(crit, 1, function(x) paste(x[x != ""], collapse = "; "))
    }) %>%
  transmute(
    Sequence   = .data[[dv$seqvar]],            # TRTSEQP  (participant-level order)
    SeqN       = .data[[dv$seqvarn]],           # TRTSEQPN (sort key)
    Participant    = USUBJID,
    Period     = .data[[dv$byperiod[1]]],       # APERIOD
    PeriodC    = .data[[dv$byperiod[2]]],       # APERIODC
    Treatment  = .data[[dv$trtvar]],            # TRTA in that period
    Assay      = PARAM,                         # Anti-Drug Antibody / Neutralizing
    Visit      = AVISIT,
    Date       = as.character(ADT),
    Result     = AVALC,                         # Positive / Negative
    Titer      = ifelse(toupper(AVALC) == "POSITIVE" & !is.na(AVAL),
                        sprintf("%g", AVAL), ""),
    `ADA Status` = status,                      # participant-level ADIS status flags
    .pern = .data[[dv$byperiod[1]]], AVISITN, ATPTN) %>%   # numeric sort keys (dropped at render)
  arrange(SeqN, Participant, .pern, Assay, AVISITN, ATPTN)

ttl <- tfl_titles(num = "16.2.9.1", type = "Listing",
   text = "Anti-Drug Antibody Results by Participant, Sequence, Period and Time",
   pop  = "Immunogenicity Analysis Population",
   foot = paste("Ordered by sequence (TRTSEQP), participant, period (APERIOD), assay, then visit.",
                "ADA Status = participant-level immunogenicity flags from ADIS (treatment-emergent = induced or boosted).",
                "Titer shown for positive samples. NAb rows listed alongside the binding ADA result."))

## render: rtables/rlistings (rlistings::as_listing) or gt; keep order above.
## numeric sort keys dropped at render
print(lst %>% select(-.pern, -AVISITN, -ATPTN), n = 50)
