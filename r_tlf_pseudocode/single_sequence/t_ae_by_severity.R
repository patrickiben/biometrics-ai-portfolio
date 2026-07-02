################################################################################
# TABLE     : t_ae_by_severity  (Single-/fixed-sequence DDI)
# TITLE     : Treatment-Emergent Adverse Events by System Organ Class,
#             Preferred Term and Maximum Severity, by Period
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADAE (TRTEMFL == "Y"); ADEX for per-PERIOD dosed denominators
# NOTE      : PSEUDOCODE. Columns nested: PERIOD (APERIODC) x severity (Mild/
#             Moderate/Severe). A participant is counted ONCE per PT at the MAXIMUM
#             severity reported within the period (max AESEVN per USUBJID*PT*per).
#             Counts = distinct PARTICIPANTS, NOT event rows. % denominator =
#             participants DOSED per APERIOD (ADEX, SAFFL) -- NOT ADSL.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SINGLESEQ")                 # TRTA + APERIOD/APERIODC

period_col <- dv$byperiod[2]                    # "APERIODC"
sev_lab    <- c("1" = "Mild", "2" = "Moderate", "3" = "Severe")

## --- per-PERIOD denominator (period-bearing source: ADEX) ---------------------
denom <- adam$adex %>%
  filter(SAFFL == "Y") %>%
  group_by(per = .data[[period_col]]) %>%
  summarise(N = n_distinct(USUBJID), .groups = "drop")

adae <- adam$adae %>% filter(SAFFL == "Y", TRTEMFL == "Y")

## --- collapse to MAX severity per participant*PT*period (count once at worst) -----
## Within a period a participant reporting the same PT twice (mild then severe) is
## counted once, at Severe. Use max(AESEVN); do NOT count separate event rows.
maxsev <- adae %>%
  group_by(per = .data[[period_col]], AESOC, AEDECOD, USUBJID) %>%
  summarise(sevn = max(AESEVN, na.rm = TRUE), .groups = "drop") %>%
  mutate(sev = factor(sev_lab[as.character(sevn)],
                      levels = c("Mild","Moderate","Severe")))

## --- counts: distinct participants per period x severity, by SOC and SOC*PT -------
cnt_socpt <- maxsev %>%
  group_by(per, AESOC, AEDECOD, sev) %>%
  summarise(nsubj = n_distinct(USUBJID), .groups = "drop") %>%
  mutate(level = 2L, term = paste0("   ", AEDECOD))

## SOC-level: a participant is counted once per SOC at their worst severity in the SOC
soc_maxsev <- adae %>%
  group_by(per = .data[[period_col]], AESOC, USUBJID) %>%
  summarise(sevn = max(AESEVN, na.rm = TRUE), .groups = "drop") %>%
  mutate(sev = factor(sev_lab[as.character(sevn)], levels = c("Mild","Moderate","Severe")))
cnt_soc <- soc_maxsev %>%
  group_by(per, AESOC, sev) %>%
  summarise(nsubj = n_distinct(USUBJID), .groups = "drop") %>%
  mutate(AEDECOD = NA_character_, level = 1L, term = AESOC)

## --- top-line "Participants with any TEAE" at MAX severity across all SOC/PT ------
## Per period a participant is counted ONCE at their WORST AESEVN over every event,
## so the any-TEAE row reflects the worst grade reported in that period.
any_worst <- adae %>%
  group_by(per = .data[[period_col]], USUBJID) %>%
  summarise(sevn = max(AESEVN, na.rm = TRUE), .groups = "drop") %>%
  mutate(sev = factor(sev_lab[as.character(sevn)],
                      levels = c("Mild","Moderate","Severe")))
any_te <- any_worst %>%
  group_by(per, sev) %>%
  summarise(nsubj = n_distinct(USUBJID), .groups = "drop") %>%
  mutate(AESOC = NA_character_, AEDECOD = NA_character_,
         level = 0L, term = "Participants with any TEAE")

## ordering: SOC by overall participant count desc; PT within SOC desc
soc_ord <- cnt_soc   %>% group_by(AESOC)          %>% summarise(socn = sum(nsubj), .groups = "drop")
pt_ord  <- cnt_socpt %>% group_by(AESOC, AEDECOD) %>% summarise(ptn  = sum(nsubj), .groups = "drop")

rep <- bind_rows(any_te, cnt_soc, cnt_socpt) %>%
  left_join(denom, by = "per") %>%
  mutate(value = n_pct(nsubj, N),
         col = paste(per, sev, sep = " | ")) %>%       # nested PERIOD x severity column
  left_join(soc_ord, by = "AESOC") %>%
  left_join(pt_ord,  by = c("AESOC","AEDECOD")) %>%
  arrange(level != 0L, desc(socn), AESOC, level, desc(ptn)) %>%  # any-TEAE row first
  select(term, level, col, value) %>%
  pivot_wider(names_from = col, values_from = value)

ttl <- tfl_titles(num = "14.3.1.3", type = "Table",
   text = "Treatment-Emergent Adverse Events by SOC, Preferred Term and Maximum Severity, by Period",
   pop  = "Safety Population",
   foot = paste("DDI: Period 1 = victim alone (reference); Period 2 = victim + perpetrator (test).",
                "Severity = NCI-CTCAE grade collapsed to Mild/Moderate/Severe; participant counted once per PT at maximum severity within the period.",
                "% = participants / participants dosed in that period (ADEX). MedDRA v27.0."))

## rtables / gt: spanning PERIOD header over (Mild, Moderate, Severe) sub-columns
print(rep)
