################################################################################
# TABLE     : t_disposition  (Crossover - 2x2 / Williams)
# TITLE     : Participant Disposition
# POPULATION: All Enrolled / Randomized; columns = treatment SEQUENCE + Total
# INPUT     : ADSL  (+ ADEX/ADDS for per-period completion if reported by period)
# NOTE      : PSEUDOCODE. Crossover disposition is PARTICIPANT-LEVEL: a participant is
#             randomized to a SEQUENCE (TRTSEQP), not an arm, so columns are the
#             fixed sequences (dv$seqvar) + Total -- NOT TRTA (which varies by
#             period within participant). Counts = distinct participants; % denom =
#             randomized N per sequence from bign() on the sequence variable.
#             Per-PERIOD completion (completed Period 1 / Period 2) is shown
#             separately and MUST come from a period-bearing source (ADEX), never
#             one-row-per-participant ADSL.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("CROSSOVER")   # seqvar = TRTSEQP, seqvarn = TRTSEQPN, byperiod = APERIOD/APERIODC

## one row per participant; columns are the randomized treatment SEQUENCE
adsl <- adam$adsl %>% filter(RANDFL == "Y")

## column denominators (N=) per SEQUENCE + Total  (randomized population)
denom <- bign(adsl, trtvar = dv$seqvar, popfl = "RANDFL")

## --- helper: a single disposition count row (distinct participants per sequence) -
disp_row <- function(df, label, ord, indent = FALSE) {
  df %>% group_by(trt = .data[[dv$seqvar]]) %>%
    summarise(nsubj = n_distinct(USUBJID), .groups = "drop") %>%
    ## append an all-participants Total column to mirror bign()'s Total row
    bind_rows(tibble(trt = "Total", nsubj = n_distinct(df$USUBJID))) %>%
    left_join(denom, by = "trt") %>%
    mutate(characteristic = if (indent) paste0("   ", label) else label,
           ord = ord, value = n_pct(nsubj, N)) %>%
    select(trt, characteristic, ord, value)
}

## --- participant-level disposition milestones (ADSL flags) ----------------------
rep <- bind_rows(
  disp_row(adsl,                                   "Randomized",                 1),
  disp_row(adsl %>% filter(SAFFL  == "Y"),         "Treated (received >=1 dose)", 2),
  disp_row(adsl %>% filter(PKFL   == "Y"),         "PK population",               3),
  disp_row(adsl %>% filter(COMPLFL== "Y"),         "Completed all periods",       4),
  disp_row(adsl %>% filter(DCSREAS != "" & !is.na(DCSREAS)),
                                                   "Discontinued (any period)",   5),
  ## breakdown of discontinuation reasons (indented under the parent)
  { adsl %>% filter(DCSREAS != "" & !is.na(DCSREAS)) %>%
      group_by(trt = .data[[dv$seqvar]], DCSREAS) %>%
      summarise(nsubj = n_distinct(USUBJID), .groups = "drop") %>%
      bind_rows(adsl %>% filter(DCSREAS != "" & !is.na(DCSREAS)) %>%
                  group_by(DCSREAS) %>%
                  summarise(trt = "Total", nsubj = n_distinct(USUBJID), .groups = "drop")) %>%
      left_join(denom, by = "trt") %>%
      mutate(characteristic = paste0("   ", DCSREAS), ord = 5.5,
             value = n_pct(nsubj, N)) %>%
      select(trt, characteristic, ord, value) }
)

## --- per-PERIOD completion: denominators from ADEX (participants dosed/period) ---
## A participant can complete Period 1 but discontinue in Period 2, so this is a
## period-bearing count keyed on dv$byperiod, NOT derivable from ADSL.
ex <- adam$adex %>% filter(SAFFL == "Y")
per_denom <- ex %>% group_by(per = .data[[dv$byperiod[2]]]) %>%   # APERIODC
  summarise(N = n_distinct(USUBJID), .groups = "drop")
per_comp <- ex %>% filter(EXSTDTC != "" & !is.na(EXENDTC)) %>%    # dosed & period completed
  group_by(per = .data[[dv$byperiod[2]]]) %>%
  summarise(nsubj = n_distinct(USUBJID), .groups = "drop") %>%
  left_join(per_denom, by = "per") %>%
  transmute(characteristic = paste("Completed", per), ord = 6 + row_number()/10,
            trt = "Total", value = n_pct(nsubj, N))

tab <- bind_rows(rep, per_comp) %>%
  arrange(ord) %>%
  select(characteristic, ord, trt, value) %>%
  pivot_wider(names_from = trt, values_from = value) %>%
  arrange(ord) %>% select(-ord)

ttl <- tfl_titles(num = "14.1.1", type = "Table", text = "Participant Disposition",
   pop  = "All Randomized Participants",
   foot = "Columns = randomized treatment sequence (TRTSEQP). A participant is counted once per row. Per-period completion denominators = participants dosed in that period (ADEX).")

## rtables/gt rendering: milestones as rows, sequences + Total as columns
print(tab)
