################################################################################
# TABLE     : t_ae_overview  (Crossover - 2x2 or Williams)
# TITLE     : Overview of Treatment-Emergent Adverse Events
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADAE (TRTEMFL == "Y"); ADEX for per-period denominators
# NOTE      : PSEUDOCODE. Counts = PARTICIPANTS with >=1 event (n_distinct USUBJID),
#             NOT event rows. n (%) per TREATMENT (TRTA); % denominator = SAFFL N
#             per treatment from bign(). Because each participant is exposed to every
#             treatment in a crossover, the per-treatment column N is the number
#             of participants DOSED with that treatment, taken from ADEX (period-
#             bearing) - NOT one-row-per-participant ADSL. An optional by-APERIOD
#             panel is shown using per-period denominators from ADEX.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("CROSSOVER")                 # trtvar=TRTA, byperiod=APERIOD/APERIODC, seqvar=TRTSEQP

## --- per-TREATMENT denominators (participants dosed per TRTA, period-bearing) ----
## In crossover the safety column variable is the actual treatment received in a
## period (TRTA). Use ADEX (one record per participant*period dosing) so the N
## reflects participants actually exposed to that treatment, not ADSL.
denom <- adam$adex %>%
  filter(SAFFL == "Y") %>%
  group_by(trt = .data[[dv$trtvar]]) %>%
  summarise(N = n_distinct(USUBJID), .groups = "drop") %>%
  bind_rows(tibble(trt = "Total",
                   N = n_distinct(adam$adex$USUBJID[adam$adex$SAFFL == "Y"])))

adae <- adam$adae %>% filter(SAFFL == "Y", TRTEMFL == "Y")

## --- "related" set: consistent + case-safe -----------------------------------
rel_set <- c("RELATED","POSSIBLE","PROBABLE","DEFINITE")

## --- per-treatment participant counts, one explicit predicate per category -------
## (kept explicit per category for audit clarity; counts = distinct participants)
cats <- bind_rows(
  adae %>% group_by(trt = .data[[dv$trtvar]]) %>%
    summarise(nsubj = n_distinct(USUBJID), .groups = "drop") %>%
    mutate(category = "Participants with any TEAE", ord = 1),
  adae %>% filter(toupper(AREL) %in% rel_set) %>%
    group_by(trt = .data[[dv$trtvar]]) %>%
    summarise(nsubj = n_distinct(USUBJID), .groups = "drop") %>%
    mutate(category = "Participants with any treatment-related TEAE", ord = 2),
  adae %>% filter(AESEVN == 3) %>%
    group_by(trt = .data[[dv$trtvar]]) %>%
    summarise(nsubj = n_distinct(USUBJID), .groups = "drop") %>%
    mutate(category = "Participants with any severe TEAE", ord = 3),
  adae %>% filter(AESER == "Y") %>%
    group_by(trt = .data[[dv$trtvar]]) %>%
    summarise(nsubj = n_distinct(USUBJID), .groups = "drop") %>%
    mutate(category = "Participants with any serious TEAE (SAE)", ord = 4),
  adae %>% filter(AESER == "Y", toupper(AREL) %in% rel_set) %>%
    group_by(trt = .data[[dv$trtvar]]) %>%
    summarise(nsubj = n_distinct(USUBJID), .groups = "drop") %>%
    mutate(category = "Participants with any related SAE", ord = 5),
  adae %>% filter(AEACN == "DRUG WITHDRAWN") %>%
    group_by(trt = .data[[dv$trtvar]]) %>%
    summarise(nsubj = n_distinct(USUBJID), .groups = "drop") %>%
    mutate(category = "Participants withdrawn due to TEAE", ord = 6),
  adae %>% filter(AESDTH == "Y") %>%
    group_by(trt = .data[[dv$trtvar]]) %>%
    summarise(nsubj = n_distinct(USUBJID), .groups = "drop") %>%
    mutate(category = "Participants with TEAE leading to death", ord = 7)
)

## add per-category all-treatment Total (distinct participants across treatments)
tot <- bind_rows(
  tibble(category = "Participants with any TEAE", ord = 1,
         nsubj = n_distinct(adae$USUBJID)),
  tibble(category = "Participants with any treatment-related TEAE", ord = 2,
         nsubj = n_distinct(adae$USUBJID[toupper(adae$AREL) %in% rel_set])),
  tibble(category = "Participants with any severe TEAE", ord = 3,
         nsubj = n_distinct(adae$USUBJID[adae$AESEVN == 3])),
  tibble(category = "Participants with any serious TEAE (SAE)", ord = 4,
         nsubj = n_distinct(adae$USUBJID[adae$AESER == "Y"])),
  tibble(category = "Participants with any related SAE", ord = 5,
         nsubj = n_distinct(adae$USUBJID[adae$AESER == "Y" & toupper(adae$AREL) %in% rel_set])),
  tibble(category = "Participants withdrawn due to TEAE", ord = 6,
         nsubj = n_distinct(adae$USUBJID[adae$AEACN == "DRUG WITHDRAWN"])),
  tibble(category = "Participants with TEAE leading to death", ord = 7,
         nsubj = n_distinct(adae$USUBJID[adae$AESDTH == "Y"]))
) %>% mutate(trt = "Total")

## --- n (%) with per-treatment denominator, wide by treatment -----------------
tab <- bind_rows(cats, tot) %>%
  left_join(denom, by = "trt") %>%
  mutate(value = n_pct(nsubj, N)) %>%
  arrange(ord) %>%
  select(category, ord, trt, value) %>%
  pivot_wider(names_from = trt, values_from = value)

ttl <- tfl_titles(num = "14.3.1.1", type = "Table",
   text = "Overview of Treatment-Emergent Adverse Events",
   pop  = "Safety Population",
   foot = paste0("A participant is counted once within each category. % = participants with the event / N exposed to the treatment (ADEX). ",
                 "Related = AREL in {Related, Possible, Probable, Definite}. Severe = AESEVN=3. MedDRA v27.0."))

## rtables layout: category rows x treatment columns (+ Total)
lyt <- basic_table(title = ttl$titles[3], main_footer = ttl$footnotes) %>%
  analyze("category", afun = function(x) in_rows(.list = as.list(x)))
# tbl <- build_table(lyt, tab)   ## or gt::gt(tab)
print(tab)
