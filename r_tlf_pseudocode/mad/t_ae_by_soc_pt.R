################################################################################
# TABLE     : t_ae_by_soc_pt  (Multiple Ascending Dose)
# TITLE     : Treatment-Emergent Adverse Events by System Organ Class and
#             Preferred Term, by Dose Level
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADAE (TRTEMFL == "Y")
# NOTE      : PSEUDOCODE. MAD = parallel ascending-dose cohorts, repeated dosing;
#             one treatment per participant, so column = dose level (dv$trtvar =
#             TRT01A) ordered ascending by TRT01AN. Counts = PARTICIPANTS with >=1
#             event (n_distinct USUBJID), NOT event rows. n (%) per dose;
#             % denominator = SAFFL N per dose. SOC sorted by overall frequency
#             desc; PT within SOC desc.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("MAD")                       # trtvar = TRT01A (dose level)

denom <- bign(adam$adsl, trtvar = dv$trtvar, popfl = "SAFFL")
adae  <- adam$adae %>% filter(TRTEMFL == "Y", SAFFL == "Y")   # treatment-emergent

## column (dose) order: ascending by numeric dose TRT01AN
doses <- adam$adsl %>% filter(SAFFL == "Y") %>%
  distinct(trt = .data[[dv$trtvar]], trtn = .data[[dv$trtnvar]]) %>%
  arrange(trtn) %>% pull(trt)

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
soc_ord   <- soc   %>% group_by(AESOC)          %>% summarise(socn = sum(nsubj), .groups="drop")
pt_ord    <- socpt %>% group_by(AESOC, AEDECOD) %>% summarise(ptn  = sum(nsubj), .groups="drop")

## assemble: Any TEAE -> SOC -> indented PT, with n (%) per dose (ascending)
rep <- bind_rows(any_te, soc, socpt) %>%
  left_join(denom, by = c("trt")) %>%
  mutate(value = n_pct(nsubj, N)) %>%
  left_join(soc_ord, by = "AESOC") %>% left_join(pt_ord, by = c("AESOC","AEDECOD")) %>%
  arrange(desc(socn), AESOC, level, desc(ptn)) %>%
  mutate(trt = factor(trt, levels = doses)) %>%        # keep ascending-dose order
  select(term, level, trt, value) %>%
  pivot_wider(names_from = trt, values_from = value)

ttl <- tfl_titles(num = "14.3.1.1", type = "Table",
   text = "Treatment-Emergent Adverse Events by System Organ Class and Preferred Term, by Dose Level",
   pop  = "Safety Population",
   foot = paste("MAD: parallel ascending-dose cohorts, repeated dosing; columns = dose",
                "level (ascending). A participant is counted once at each level. MedDRA v27.0.",
                "% = participants with the event / N at dose."))

## rtables/gt rendering; split_cols_by(dose) ascending; SOC bold (level 1),
## PT indented (level 2)
print(rep)
