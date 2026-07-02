################################################################################
# TABLE     : t_medical_history  (Single-/Fixed-Sequence DDI)
# TITLE     : Medical History by System Organ Class and Preferred Term
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADMH (MedDRA coded medical / surgical history)
# NOTE      : PSEUDOCODE. Counts = distinct PARTICIPANTS with a condition
#             (n_distinct USUBJID), NOT history rows. PARTICIPANT-LEVEL table ->
#             columns = the ONE fixed sequence (dv$seqvar). Ongoing/past history
#             (MHENRF / pre-treatment). SOC sorted by overall freq desc; PT
#             within SOC desc. % denominator = Safety N per sequence.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SINGLESEQ")                 # seqvar = TRTSEQP
options(tfl.study = env$study)

adsl <- adam$adsl %>% filter(SAFFL == "Y")
seq_map <- adsl %>% select(USUBJID, seq = .data[[dv$seqvar]])

## column denominators (N=) per fixed sequence + Total (participant-level)
denom <- bign(adsl, trtvar = dv$seqvar, popfl = "SAFFL")

## --- medical history records (pre-treatment conditions) --------------------
## ADMH: MHBODSYS (SOC), MHDECOD (PT). One inclusion rule (same as SAS twin):
## general medical history category. Map each participant to the fixed sequence.
admh <- adam$admh %>%
  filter(SAFFL == "Y", MHCAT == "GENERAL MEDICAL HISTORY") %>%
  inner_join(seq_map, by = "USUBJID")

## 1) "Any medical history" overall row (distinct participants, any condition)
any_mh <- admh %>% group_by(seq) %>%
  summarise(n = n_distinct(USUBJID), .groups = "drop") %>%
  mutate(MHBODSYS = NA_character_, MHDECOD = NA_character_, level = 0L,
         term = "Participants with any medical history")

## 2) by SOC (distinct participants within SOC)
soc <- admh %>% group_by(seq, MHBODSYS) %>%
  summarise(n = n_distinct(USUBJID), .groups = "drop") %>%
  mutate(level = 1L, term = MHBODSYS)

## 3) by SOC*PT (distinct participants within SOC and PT)
socpt <- admh %>% group_by(seq, MHBODSYS, MHDECOD) %>%
  summarise(n = n_distinct(USUBJID), .groups = "drop") %>%
  mutate(level = 2L, term = paste0("   ", MHDECOD))   # indent PT under SOC

## ordering: SOC by overall (all-sequence) participant count desc; PT within SOC desc
soc_ord <- soc   %>% group_by(MHBODSYS)          %>% summarise(socn = sum(n), .groups="drop")
pt_ord  <- socpt %>% group_by(MHBODSYS, MHDECOD) %>% summarise(ptn  = sum(n), .groups="drop")

## --- assemble: Any -> SOC -> indented PT, n (%) per fixed sequence ---------
rep <- bind_rows(any_mh, soc, socpt) %>%
  left_join(denom, by = c("seq" = "trt")) %>%
  mutate(value = n_pct(n, N)) %>%
  left_join(soc_ord, by = "MHBODSYS") %>%
  left_join(pt_ord,  by = c("MHBODSYS","MHDECOD")) %>%
  arrange(desc(socn), MHBODSYS, level, desc(ptn)) %>%
  select(term, level, seq, value) %>%
  pivot_wider(names_from = seq, values_from = value)

ttl <- tfl_titles(num = "14.1.7", type = "Table",
   text = "Medical History by System Organ Class and Preferred Term",
   pop  = "Safety Population",
   foot = paste("A participant is counted once at each level. MedDRA v27.0.",
                "Pre-treatment medical/surgical history. Percentages based on",
                "Safety Population N per fixed sequence."))

## rtables/gt rendering; SOC bold (level 1), PT indented (level 2)
lyt <- basic_table(title = ttl$titles[3], main_footer = ttl$footnotes) %>%
  analyze("term", afun = function(x) in_rows(.list = as.list(x)))
# tbl <- build_table(lyt, rep)   ## or gt::gt(rep)
print(rep)
