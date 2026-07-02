################################################################################
# TABLE     : t_medical_history  (Crossover - 2x2 / Williams)
# TITLE     : Medical History by System Organ Class and Preferred Term
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADMH  (one row per medical-history condition; MedDRA SOC + PT)
# NOTE      : PSEUDOCODE. PARTICIPANT-LEVEL table -- medical history is recorded once
#             at screening and is fixed within participant, so columns = treatment
#             SEQUENCE (dv$seqvar = TRTSEQP) + Total, NOT TRTA. Counts = PARTICIPANTS
#             with the condition (n_distinct USUBJID), NOT history rows. n (%);
#             % denominator = SAFFL N per sequence from bign(). SOC sorted by
#             overall participant frequency desc; PT within SOC desc.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("CROSSOVER")   # seqvar = TRTSEQP (participant-level sequence column)

## SAFFL N per SEQUENCE + Total
denom <- bign(adam$adsl, trtvar = dv$seqvar, popfl = "SAFFL")

## ADMH: medical-history conditions present, with participant's sequence label
mh <- adam$admh %>% filter(SAFFL == "Y", MHOCCUR == "Y") %>%
  left_join(adam$adsl %>% select(USUBJID, !!dv$seqvar), by = "USUBJID")

## --- "Any condition" overall row (distinct participants) ------------------------
any_mh <- mh %>% group_by(trt = .data[[dv$seqvar]]) %>%
  summarise(nsubj = n_distinct(USUBJID), .groups = "drop") %>%
  bind_rows(tibble(trt = "Total", nsubj = n_distinct(mh$USUBJID))) %>%
  mutate(MHBODSYS = NA_character_, MHDECOD = NA_character_, level = 0L,
         term = "Participants with any medical history")

## --- by SOC (distinct participants within SOC) ----------------------------------
soc <- mh %>% group_by(trt = .data[[dv$seqvar]], MHBODSYS) %>%
  summarise(nsubj = n_distinct(USUBJID), .groups = "drop") %>%
  bind_rows(mh %>% group_by(MHBODSYS) %>%
              summarise(trt = "Total", nsubj = n_distinct(USUBJID), .groups = "drop")) %>%
  mutate(level = 1L, term = MHBODSYS)

## --- by SOC*PT (distinct participants within SOC and PT) ------------------------
socpt <- mh %>% group_by(trt = .data[[dv$seqvar]], MHBODSYS, MHDECOD) %>%
  summarise(nsubj = n_distinct(USUBJID), .groups = "drop") %>%
  bind_rows(mh %>% group_by(MHBODSYS, MHDECOD) %>%
              summarise(trt = "Total", nsubj = n_distinct(USUBJID), .groups = "drop")) %>%
  mutate(level = 2L, term = paste0("   ", MHDECOD))   # indent PT under SOC

## ordering: SOC by overall (all-sequence) participant count desc; PT within SOC desc
soc_ord <- soc   %>% filter(trt == "Total") %>% select(MHBODSYS, socn = nsubj)
pt_ord  <- socpt %>% filter(trt == "Total") %>% select(MHBODSYS, MHDECOD, ptn = nsubj)

rep <- bind_rows(any_mh, soc, socpt) %>%
  left_join(denom, by = "trt") %>%
  mutate(value = n_pct(nsubj, N)) %>%
  left_join(soc_ord, by = "MHBODSYS") %>%
  left_join(pt_ord,  by = c("MHBODSYS","MHDECOD")) %>%
  arrange(desc(socn), MHBODSYS, level, desc(ptn)) %>%
  select(term, level, trt, value) %>%
  pivot_wider(names_from = trt, values_from = value)

ttl <- tfl_titles(num = "14.1.7", type = "Table",
   text = "Medical History by System Organ Class and Preferred Term",
   pop  = "Safety Population",
   foot = "A participant is counted once at each level. Columns = randomized sequence (TRTSEQP); medical history is fixed within participant. MedDRA v27.0. % = participants with condition / N in sequence.")

## rtables/gt rendering: SOC bold (level 1), PT indented (level 2)
print(rep)
