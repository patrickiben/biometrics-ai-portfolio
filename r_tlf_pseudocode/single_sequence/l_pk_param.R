################################################################################
# LISTING   : l_pk_param  (Single-/fixed-sequence DDI)
# TITLE     : Listing of Individual Plasma PK Parameters of the Victim Drug
# POPULATION: PK Parameter Population (PKFL == "Y")
# INPUT     : ADPP (PARAMCD/PARAM; AVAL; APERIOD/APERIODC; TRTA; TRTSEQP)
# NOTE      : PSEUDOCODE. One row per participant x PERIOD with PK parameters in
#             columns (wide), ordered by participant then period. Single-/fixed-
#             sequence DDI: the within-participant PERIOD (dv$byperiod) drives the
#             paired structure -- Period 1 = victim alone (reference), Period 2 =
#             victim + perpetrator (test). There is NO randomized sequence, so the
#             fixed sequence label (dv$seqvar) is shown once as context. Tmax at
#             higher precision; other parameters as %.3g; non-estimable -> "NE".
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SINGLESEQ")                 # period via dv$byperiod; fixed seq

## --- subset parameters to report, in display order ------------------------
## Oral (extravascular) study: CL/F = CLFO, Vz/F = VZFO (same codes as SAS twin).
keep <- c("CMAX","TMAX","AUCLST","AUCIFO","T12","CLFO","VZFO")

pp <- adam$adpp %>%
  filter(PKFL == "Y", PARAMCD %in% keep) %>%
  mutate(
    Participant   = str_extract(USUBJID, "[^-]+$"),
    Sequence  = .data[[dv$seqvar]],             # fixed sequence label (context only)
    Period    = .data[[dv$byperiod[1]]],        # APERIOD numeric (sort key)
    `Period (Treatment)` = .data[[dv$byperiod[2]]],   # APERIODC label: Reference / Test
    ## format value: Tmax to 2dp, others 3 sig figs; NE if missing/non-estimable
    vchar = if_else(is.na(AVAL), "NE",
                    if_else(PARAMCD == "TMAX", sprintf("%.2f", AVAL),
                            sprintf("%.3g", AVAL))),
    PARAMCD = factor(PARAMCD, levels = keep))   # column order

## --- pivot parameters to columns (one row per participant x period) -----------
lst <- pp %>%
  select(Participant, Sequence, Period, `Period (Treatment)`, PARAMCD, vchar) %>%
  pivot_wider(names_from = PARAMCD, values_from = vchar) %>%
  arrange(Participant, Period)                      # numeric period as sort key

ttl <- tfl_titles(num = "16.2.10.2", type = "Listing",
   text = "Listing of Individual Plasma Pharmacokinetic Parameters of the Victim Drug",
   pop  = "Pharmacokinetic Parameter Population",
   foot = paste("NE = not estimable. Period 1 = victim alone (reference),",
                "Period 2 = victim + perpetrator (test); fixed-sequence design (no randomized sequence).",
                "Units per ADPP AVALU; Tmax in hours."))

## render: page break by Participant; reference and test period rows adjacent so the
## within-participant DDI comparison is easy to read. Columns = parameters.
## listings::create_listing(lst, ...) or gt::gt(lst %>% select(-Period))
print(lst %>% select(-Period))
