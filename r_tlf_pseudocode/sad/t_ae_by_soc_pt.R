################################################################################
# TABLE     : t_ae_by_soc_pt  (Single Ascending Dose)
# TITLE     : Treatment-Emergent Adverse Events by System Organ Class and
#             Preferred Term, by Dose Level
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADAE (TRTEMFL == "Y")
# NOTE      : PSEUDOCODE. Counts = PARTICIPANTS with >=1 event (n_distinct USUBJID),
#             NOT event rows. n (%) per dose level; % denominator = SAFFL N per
#             dose level. SAD: parallel cohorts -> column = dose level
#             (dv$trtvar = TRT01A); columns ordered low->high by dose (TRT01AN),
#             placebo often pooled. SOC sorted by overall frequency desc; PT
#             within SOC desc. Single dose -> no accumulation.
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

adae <- adam$adae %>% filter(TRTEMFL == "Y", SAFFL == "Y")   # treatment-emergent

## 1) "Any TEAE" overall row (distinct participants, any event)
any_te <- adae %>% group_by(trt = .data[[dv$trtvar]]) %>%
  summarise(nsubj = n_distinct(USUBJID), .groups = "drop") %>%
  mutate(AESOC = NA_character_, AEDECOD = NA_character_, level = 0L,
         term = "Participants with any TEAE")

## 2) by SOC (distinct participants within SOC)
soc <- aecount(adae, trtvar = dv$trtvar, byvars = "AESOC") %>%
  mutate(level = 1L, term = AESOC)

## 3) by SOC*PT (distinct participants within SOC and PT)
socpt <- aecount(adae, trtvar = dv$trtvar, byvars = c("AESOC","AEDECOD")) %>%
  mutate(level = 2L, term = paste0("   ", AEDECOD))   # indent PT under SOC

## ordering: SOC by overall (all-dose) participant count desc; PT within SOC desc
soc_ord <- soc   %>% group_by(AESOC)          %>% summarise(socn = sum(nsubj), .groups = "drop")
pt_ord  <- socpt %>% group_by(AESOC, AEDECOD) %>% summarise(ptn  = sum(nsubj), .groups = "drop")

## assemble: Any TEAE -> SOC -> indented PT, with n (%) per dose level
rep <- bind_rows(any_te, soc, socpt) %>%
  left_join(denom, by = c("trt")) %>%
  mutate(value = n_pct(nsubj, N)) %>%
  left_join(soc_ord, by = "AESOC") %>% left_join(pt_ord, by = c("AESOC","AEDECOD")) %>%
  arrange(desc(socn), AESOC, level, desc(ptn)) %>%
  select(term, level, trt, value) %>%
  pivot_wider(names_from = trt, values_from = value)
## NB: dose columns re-ordered low->high via dose_key$dose_ord at render.

ttl <- tfl_titles(num = "14.3.1.1", type = "Table",
   text = "Treatment-Emergent Adverse Events by System Organ Class and Preferred Term, by Dose Level",
   pop  = "Safety Population",
   foot = paste("SAD: each column = single ascending dose level (TRT01A), ordered",
                "low to high; placebo may be pooled across cohorts. A participant is",
                "counted once at each level. MedDRA v27.0. % = participants with the",
                "event / N in dose level."))

## rtables/gt rendering; split_cols_by(dv$trtvar) (ascending dose);
## SOC bold (level 1), PT indented (level 2).
print(rep)
