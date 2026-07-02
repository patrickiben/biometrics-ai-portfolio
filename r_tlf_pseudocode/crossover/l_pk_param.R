################################################################################
# LISTING   : l_pk_param  (Crossover - 2x2 or Williams)
# TITLE     : Listing of Individual Plasma PK Parameters
# POPULATION: PK Parameter Population (PKFL == "Y")
# INPUT     : ADPP (PARAMCD/PARAM; AVAL; APERIOD/APERIODC; TRTA; TRTSEQP)
# NOTE      : PSEUDOCODE. One row per participant x treatment with PK parameters in
#             columns (wide), ordered by sequence, participant, period. Crossover:
#             show planned SEQUENCE (dv$seqvar) + within-participant PERIOD
#             (dv$byperiod) + actual treatment (dv$trtvar) so the paired
#             structure is explicit. Tmax displayed at higher precision; other
#             parameters as %.3g. Non-estimable parameters shown as "NE".
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("CROSSOVER")                 # TRTA + APERIOD + TRTSEQP

## --- subset parameters to report, in display order ------------------------
keep <- c("CMAX","TMAX","AUCLST","AUCIFO","T12","CL","VZ")

pp <- adam$adpp %>%
  filter(PKFL == "Y", PARAMCD %in% keep) %>%
  mutate(
    Sequence  = .data[[dv$seqvar]],             # TRTSEQP planned sequence
    Participant   = str_extract(USUBJID, "[^-]+$"),
    Period    = .data[[dv$byperiod[1]]],        # APERIOD numeric (sort key)
    PeriodC   = .data[[dv$byperiod[2]]],        # APERIODC label
    Treatment = .data[[dv$trtvar]],             # TRTA actual treatment
    ## format value: Tmax to 2dp, others 3 sig figs; NE if missing/non-estimable
    vchar = if_else(is.na(AVAL), "NE",
                    if_else(PARAMCD == "TMAX", sprintf("%.2f", AVAL),
                            sprintf("%.3g", AVAL))),
    PARAMCD = factor(PARAMCD, levels = keep))   # column order

## --- pivot parameters to columns (one row per participant x treatment) --------
lst <- pp %>%
  select(Sequence, Participant, Period, PeriodC, Treatment, PARAMCD, vchar) %>%
  pivot_wider(names_from = PARAMCD, values_from = vchar) %>%
  arrange(Sequence, Participant, Period)            # numeric period as sort key

ttl <- tfl_titles(num = "16.2.10.2", type = "Listing",
   text = "Listing of Individual Plasma Pharmacokinetic Parameters",
   pop  = "Pharmacokinetic Parameter Population",
   foot = paste("NE = not estimable. Sequence = planned treatment sequence (TRTSEQP);",
                "Period = within-participant study period; Treatment = actual treatment (TRTA).",
                "Units per ADPP AVALU; Tmax in hours."))

## render: one block per Sequence, page break by Participant; columns = parameters.
## listings::create_listing(lst, ...) or gt::gt(lst %>% select(-Period))
print(lst %>% select(-Period))
