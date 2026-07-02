################################################################################
# TABLE     : t_ae_by_relationship  (Multiple Ascending Dose)
# TITLE     : Treatment-Related Treatment-Emergent Adverse Events by System
#             Organ Class and Preferred Term, by Dose Level
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADAE (TRTEMFL == "Y" & AREL related)
# NOTE      : PSEUDOCODE. MAD = parallel ascending-dose cohorts, repeated dosing;
#             one treatment per participant, so column = dose level (dv$trtvar =
#             TRT01A) ordered ascending by TRT01AN. Restricts to treatment-
#             RELATED TEAEs using the house "related" set, case-safe:
#             toupper(AREL) %in% {RELATED, POSSIBLE, PROBABLE, DEFINITE}.
#             Counts = PARTICIPANTS (n_distinct USUBJID), NOT event rows. n (%) per
#             dose; % denominator = SAFFL N per dose.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("MAD")                       # trtvar = TRT01A (dose level)

denom <- bign(adam$adsl, trtvar = dv$trtvar, popfl = "SAFFL")

## column (dose) order: ascending by numeric dose TRT01AN
doses <- adam$adsl %>% filter(SAFFL == "Y") %>%
  distinct(trt = .data[[dv$trtvar]], trtn = .data[[dv$trtnvar]]) %>%
  arrange(trtn) %>% pull(trt)

## --- house "related" set, applied case-safe --------------------------------
rel_set <- c("RELATED","POSSIBLE","PROBABLE","DEFINITE")

adae <- adam$adae %>%
  filter(SAFFL == "Y", TRTEMFL == "Y", toupper(AREL) %in% rel_set)

## 1) Any related TEAE overall (distinct participants)
any_rel <- adae %>% group_by(trt = .data[[dv$trtvar]]) %>%
  summarise(nsubj = n_distinct(USUBJID), .groups = "drop") %>%
  mutate(AESOC = NA_character_, AEDECOD = NA_character_, level = 0L,
         term = "Participants with any treatment-related TEAE")

## 2) by SOC (distinct related-AE participants within SOC)
soc <- aecount(adae, trtvar = dv$trtvar,
               where = quote(toupper(AREL) %in% c("RELATED","POSSIBLE","PROBABLE","DEFINITE")),
               byvars = "AESOC") %>%
  mutate(level = 1L, term = AESOC)

## 3) by SOC*PT
socpt <- aecount(adae, trtvar = dv$trtvar,
                 where = quote(toupper(AREL) %in% c("RELATED","POSSIBLE","PROBABLE","DEFINITE")),
                 byvars = c("AESOC","AEDECOD")) %>%
  mutate(level = 2L, term = paste0("   ", AEDECOD))

## --- ordering: SOC by overall freq desc; PT within SOC desc ----------------
soc_ord <- soc   %>% group_by(AESOC)          %>% summarise(socn = sum(nsubj), .groups = "drop")
pt_ord  <- socpt %>% group_by(AESOC, AEDECOD) %>% summarise(ptn  = sum(nsubj), .groups = "drop")

## --- assemble: Any -> SOC -> indented PT, n (%) per dose (ascending) --------
rep <- bind_rows(any_rel, soc, socpt) %>%
  left_join(denom, by = "trt") %>%
  mutate(value = n_pct(nsubj, N)) %>%
  left_join(soc_ord, by = "AESOC") %>%
  left_join(pt_ord,  by = c("AESOC","AEDECOD")) %>%
  arrange(desc(socn), AESOC, level, desc(ptn)) %>%
  mutate(trt = factor(trt, levels = doses)) %>%        # keep ascending-dose order
  select(term, level, trt, value) %>%
  pivot_wider(names_from = trt, values_from = value)

ttl <- tfl_titles(
  num  = "14.3.1.3",
  type = "Table",
  text = "Treatment-Related Treatment-Emergent Adverse Events by SOC and Preferred Term, by Dose Level",
  pop  = "Safety Population",
  foot = paste("MAD: parallel ascending-dose cohorts, repeated dosing; columns = dose",
               "level (ascending). Treatment-related = AREL in {RELATED, POSSIBLE,",
               "PROBABLE, DEFINITE} (case-insensitive). A participant is counted once at each",
               "level. % = participants / N at dose. MedDRA v27.0."))

## rtables/gt: split_cols_by(dose, ascending); SOC bold (level 1), PT indented (level 2)
print(rep)
