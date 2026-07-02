################################################################################
# TABLE     : t_ae_by_relationship  (Crossover - 2x2 or Williams)
# TITLE     : Treatment-Related Treatment-Emergent Adverse Events by
#             System Organ Class and Preferred Term
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADAE (TRTEMFL == "Y"); ADEX for per-treatment denominators
# NOTE      : PSEUDOCODE. Subset to RELATED TEAEs only, then count PARTICIPANTS
#             (n_distinct USUBJID), NOT event rows. "Related" set, case-safe:
#             toupper(AREL) %in% {RELATED, POSSIBLE, PROBABLE, DEFINITE}.
#             Columns = treatment (TRTA); % denominator = participants exposed to
#             that treatment from ADEX (period-bearing), NOT ADSL. SOC by overall
#             participant freq desc; PT within SOC desc.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("CROSSOVER")                 # trtvar=TRTA, byperiod=APERIOD/APERIODC

rel_set <- c("RELATED","POSSIBLE","PROBABLE","DEFINITE")

## --- per-TREATMENT denominators from ADEX (participants dosed per TRTA) ----------
denom <- adam$adex %>%
  filter(SAFFL == "Y") %>%
  group_by(trt = .data[[dv$trtvar]]) %>%
  summarise(N = n_distinct(USUBJID), .groups = "drop") %>%
  bind_rows(tibble(trt = "Total",
                   N = n_distinct(adam$adex$USUBJID[adam$adex$SAFFL == "Y"])))

## --- RELATED treatment-emergent AEs only -------------------------------------
adae <- adam$adae %>%
  filter(SAFFL == "Y", TRTEMFL == "Y", toupper(AREL) %in% rel_set)

## 1) "Any related TEAE" overall (distinct participants) per treatment + Total
any_te <- bind_rows(
  adae %>% group_by(trt = .data[[dv$trtvar]]) %>%
    summarise(nsubj = n_distinct(USUBJID), .groups = "drop"),
  tibble(trt = "Total", nsubj = n_distinct(adae$USUBJID))) %>%
  mutate(AESOC = NA_character_, AEDECOD = NA_character_, level = 0L,
         term = "Participants with any related TEAE")

## 2) by SOC, per treatment + Total
soc <- bind_rows(
  aecount(adae, trtvar = dv$trtvar, where = quote(TRTEMFL == "Y"), byvars = "AESOC"),
  adae %>% group_by(AESOC) %>%
    summarise(nsubj = n_distinct(USUBJID), .groups = "drop") %>% mutate(trt = "Total")) %>%
  mutate(level = 1L, term = AESOC)

## 3) by SOC*PT, per treatment + Total
socpt <- bind_rows(
  aecount(adae, trtvar = dv$trtvar, where = quote(TRTEMFL == "Y"), byvars = c("AESOC","AEDECOD")),
  adae %>% group_by(AESOC, AEDECOD) %>%
    summarise(nsubj = n_distinct(USUBJID), .groups = "drop") %>% mutate(trt = "Total")) %>%
  mutate(level = 2L, term = paste0("   ", AEDECOD))

## ordering: SOC by overall participant count desc; PT within SOC desc
soc_ord <- adae %>% group_by(AESOC) %>%
  summarise(socn = n_distinct(USUBJID), .groups = "drop")
pt_ord  <- adae %>% group_by(AESOC, AEDECOD) %>%
  summarise(ptn = n_distinct(USUBJID), .groups = "drop")

rep <- bind_rows(any_te, soc, socpt) %>%
  left_join(denom, by = "trt") %>%
  mutate(value = n_pct(nsubj, N)) %>%
  left_join(soc_ord, by = "AESOC") %>%
  left_join(pt_ord,  by = c("AESOC","AEDECOD")) %>%
  arrange(desc(socn), AESOC, level, desc(ptn)) %>%
  select(term, level, trt, value) %>%
  pivot_wider(names_from = trt, values_from = value)

ttl <- tfl_titles(num = "14.3.1.4", type = "Table",
   text = "Treatment-Related Treatment-Emergent Adverse Events by System Organ Class and Preferred Term",
   pop  = "Safety Population",
   foot = paste0("Related = AREL in {Related, Possible, Probable, Definite} (case-insensitive). ",
                 "A participant is counted once at each level. Columns = treatment (TRTA). % = participants / N exposed (ADEX). MedDRA v27.0."))

## rtables/gt rendering; SOC bold (level 1), PT indented (level 2)
print(rep)
