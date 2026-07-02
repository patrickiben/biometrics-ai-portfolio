################################################################################
# TABLE     : t_protocol_deviations  (Single-/Fixed-Sequence DDI)
# TITLE     : Important Protocol Deviations by Category
# POPULATION: All Enrolled Participants (ENRLFL == "Y")
# INPUT     : ADDV (protocol deviation BDS) keyed back to ADSL fixed sequence
# NOTE      : PSEUDOCODE. Counts = distinct PARTICIPANTS with >=1 deviation in a
#             category (n_distinct USUBJID), NOT deviation rows. PARTICIPANT-LEVEL
#             table -> columns = the ONE fixed sequence (dv$seqvar). Important
#             deviations only (strict IMPDVFL == "Y" / DVCAT). Population = ALL
#             ENROLLED (ENRLFL == "Y"); % based on the enrolled N per sequence.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SINGLESEQ")                 # seqvar = TRTSEQP
options(tfl.study = env$study)

adsl <- adam$adsl %>% filter(ENRLFL == "Y")
seq_map <- adsl %>% select(USUBJID, seq = .data[[dv$seqvar]])

## column denominators (N=) per fixed sequence + Total (all enrolled)
denom <- bign(adsl, trtvar = dv$seqvar, popfl = "ENRLFL")

## --- important protocol deviations -----------------------------------------
## ADDV: DVCAT (category), DVDECOD, important flag IMPDVFL. Strict IMPDVFL=="Y"
## filter (no | is.na()); map each participant to the fixed sequence from ADSL.
dv_imp <- adam$addv %>%
  filter(IMPDVFL == "Y") %>%
  inner_join(seq_map, by = "USUBJID")

## 1) "Any important deviation" overall row (distinct participants, any deviation)
any_dv <- dv_imp %>%
  group_by(seq) %>%
  summarise(n = n_distinct(USUBJID), .groups = "drop") %>%
  mutate(DVCAT = NA_character_, level = 0L, term = "Participants with any important deviation")

## 2) by deviation category (distinct participants within category)
cat_dv <- dv_imp %>%
  group_by(seq, DVCAT) %>%
  summarise(n = n_distinct(USUBJID), .groups = "drop") %>%
  mutate(level = 1L, term = DVCAT)

## ordering: category by overall (all-sequence) participant count desc
cat_ord <- cat_dv %>% group_by(DVCAT) %>% summarise(catn = sum(n), .groups = "drop")

## --- assemble: n (%) per fixed-sequence column ------------------------------
rep <- bind_rows(any_dv, cat_dv) %>%
  left_join(denom, by = c("seq" = "trt")) %>%
  mutate(value = n_pct(n, N)) %>%
  left_join(cat_ord, by = "DVCAT") %>%
  arrange(level, desc(catn), DVCAT) %>%
  select(term, level, seq, value) %>%
  pivot_wider(names_from = seq, values_from = value)

ttl <- tfl_titles(num = "14.1.5", type = "Table",
   text = "Important Protocol Deviations by Category",
   pop  = "All Enrolled Participants",
   foot = paste("A participant is counted once per category. Important deviations",
                "only (IMPDVFL = Y; categories from ADDV DVCAT). Percentages based",
                "on the number of participants enrolled per fixed sequence."))

## rtables/gt rendering; category indented under the overall "any" row
lyt <- basic_table(title = ttl$titles[3], main_footer = ttl$footnotes) %>%
  analyze("term", afun = function(x) in_rows(.list = as.list(x)))
# tbl <- build_table(lyt, rep)   ## or gt::gt(rep)
print(rep)
