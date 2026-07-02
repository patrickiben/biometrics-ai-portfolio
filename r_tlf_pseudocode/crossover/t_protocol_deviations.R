################################################################################
# TABLE     : t_protocol_deviations  (Crossover - 2x2 / Williams)
# TITLE     : Important Protocol Deviations by Category
# POPULATION: All Randomized Participants (RANDFL == "Y")
# INPUT     : ADDV  (one row per deviation; carries APERIOD for in-period events)
# NOTE      : PSEUDOCODE. Counts = PARTICIPANTS with >=1 deviation (n_distinct
#             USUBJID), NOT deviation rows. Participant-level summary columns =
#             treatment SEQUENCE (dv$seqvar = TRTSEQP) + Total; % denom =
#             randomized N per sequence from bign(). Because deviations can occur
#             in a specific period (e.g. dosing-window violation in Period 2),
#             a by-PERIOD companion keyed on dv$byperiod is included; per-period
#             denominators come from ADEX/ADDV (period-bearing), never ADSL.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("CROSSOVER")   # seqvar = TRTSEQP (participant-level), byperiod = APERIOD/APERIODC

## randomized N per SEQUENCE + Total (participant-level denominator)
denom <- bign(adam$adsl, trtvar = dv$seqvar, popfl = "RANDFL")

## ADDV: important deviations only; carry the participant's sequence label
pd <- adam$addv %>% filter(RANDFL == "Y", IMPDVFL == "Y") %>%   # important deviations
  left_join(adam$adsl %>% select(USUBJID, !!dv$seqvar), by = "USUBJID")

## --- "Any important deviation" overall row (distinct participants) --------------
any_pd <- pd %>% group_by(trt = .data[[dv$seqvar]]) %>%
  summarise(nsubj = n_distinct(USUBJID), .groups = "drop") %>%
  bind_rows(tibble(trt = "Total", nsubj = n_distinct(pd$USUBJID))) %>%
  mutate(category = "Participants with any important deviation", level = 0L)

## --- by deviation CATEGORY (distinct participants within category) --------------
bycat <- pd %>% group_by(trt = .data[[dv$seqvar]], DVCAT) %>%
  summarise(nsubj = n_distinct(USUBJID), .groups = "drop") %>%
  bind_rows(pd %>% group_by(DVCAT) %>%
              summarise(trt = "Total", nsubj = n_distinct(USUBJID), .groups = "drop")) %>%
  mutate(category = paste0("   ", DVCAT), level = 1L)

## ordering: category by overall (all-sequence) participant count desc
cat_ord <- bycat %>% filter(trt == "Total") %>% select(DVCAT, ord_n = nsubj)

rep <- bind_rows(any_pd, bycat) %>%
  left_join(denom, by = "trt") %>%
  mutate(value = n_pct(nsubj, N)) %>%
  left_join(cat_ord, by = "DVCAT") %>%
  arrange(level, desc(ord_n), DVCAT) %>%
  select(category, level, trt, value) %>%
  pivot_wider(names_from = trt, values_from = value)

## --- by-PERIOD companion (period-bearing): participants with a deviation/period --
## denominators = participants on study per period from ADEX (dosed that period).
per_denom <- adam$adex %>% filter(SAFFL == "Y") %>%
  group_by(per = .data[[dv$byperiod[2]]]) %>%
  summarise(N = n_distinct(USUBJID), .groups = "drop")
by_period <- pd %>% filter(!is.na(.data[[dv$byperiod[2]]])) %>%
  group_by(per = .data[[dv$byperiod[2]]]) %>%
  summarise(nsubj = n_distinct(USUBJID), .groups = "drop") %>%
  left_join(per_denom, by = "per") %>%
  transmute(Period = per, `Participants with deviation` = n_pct(nsubj, N))

ttl <- tfl_titles(num = "14.1.5", type = "Table",
   text = "Important Protocol Deviations by Category",
   pop  = "All Randomized Participants",
   foot = "A participant is counted once per category. Participant-level columns = randomized sequence (TRTSEQP). Per-period denominators = participants dosed in that period (ADEX), not ADSL.")

print(rep)
print(by_period)   # companion by-period deviation counts (dv$byperiod)
