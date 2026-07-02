################################################################################
# TABLE     : t_ae_by_relationship  (Single Ascending Dose)
# TITLE     : Treatment-Related Treatment-Emergent Adverse Events by System
#             Organ Class and Preferred Term, by Dose Level
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADAE (TRTEMFL == "Y" & AREL related)
# NOTE      : PSEUDOCODE. Restricts to treatment-RELATED TEAEs using the house
#             "related" set, case-safe: toupper(AREL) %in%
#             {RELATED, POSSIBLE, PROBABLE, DEFINITE}. Counts = PARTICIPANTS
#             (n_distinct USUBJID), NOT event rows. n (%) per dose level;
#             % denominator = SAFFL N per dose level. SAD: column = dose level
#             (dv$trtvar = TRT01A), ordered low->high (TRT01AN), placebo often
#             pooled. Dose-related AE patterns inform escalation/DLT review.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SAD")                       # trtvar = TRT01A

denom <- bign(adam$adsl, trtvar = dv$trtvar, popfl = "SAFFL")

## ascending-dose column order (+ optional placebo pooling) for rendering
dose_key <- adam$adsl %>% filter(SAFFL == "Y") %>%
  distinct(trt = .data[[dv$trtvar]], dosen = .data[[dv$trtnvar]]) %>%
  mutate(is_pbo = grepl("PLACEBO|PBO", toupper(trt)),
         dose_ord = if_else(is_pbo, -Inf, dosen))

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

## --- assemble: Any -> SOC -> indented PT, n (%) per dose level -------------
rep <- bind_rows(any_rel, soc, socpt) %>%
  left_join(denom, by = "trt") %>%
  mutate(value = n_pct(nsubj, N)) %>%
  left_join(soc_ord, by = "AESOC") %>%
  left_join(pt_ord,  by = c("AESOC","AEDECOD")) %>%
  arrange(desc(socn), AESOC, level, desc(ptn)) %>%
  select(term, level, trt, value) %>%
  pivot_wider(names_from = trt, values_from = value)
## NB: dose columns re-ordered low->high via dose_key$dose_ord at render.

ttl <- tfl_titles(
  num  = "14.3.1.3",
  type = "Table",
  text = "Treatment-Related Treatment-Emergent Adverse Events by SOC and Preferred Term, by Dose Level",
  pop  = "Safety Population",
  foot = paste("SAD: each column = single ascending dose level (TRT01A), ordered",
               "low to high; placebo may be pooled. Treatment-related = AREL in",
               "{RELATED, POSSIBLE, PROBABLE, DEFINITE} (case-insensitive). A",
               "participant is counted once at each level. % = participants / N in dose",
               "level. MedDRA v27.0."))

## rtables/gt: split_cols_by(dv$trtvar) (ascending dose); SOC bold (level 1),
## PT indented (level 2).
print(rep)
