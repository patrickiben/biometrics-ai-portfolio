################################################################################
# TABLE     : t_disposition  (Single-/Fixed-Sequence DDI)
# TITLE     : Participant Disposition
# POPULATION: All Enrolled Participants (ENRLFL == "Y")
# INPUT     : ADSL
# NOTE      : PSEUDOCODE. Single-/fixed-sequence design: ONE fixed sequence
#             column from ADSL (dv$seqvar = TRTSEQP; e.g. "Reference then
#             Test+Perpetrator"). There is NO randomized sequence. PARTICIPANT-
#             LEVEL table -> one row per participant, key on dv$seqvar. Population
#             = ALL ENROLLED (ENRLFL=="Y"); % based on the enrolled N so the
#             numerator population and the % denominator are the SAME set.
#             Completion uses EOSSTT (canonical ADaM end-of-study status), the
#             same source as the SAS twin. Counts = distinct USUBJID.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SINGLESEQ")                 # seqvar = TRTSEQP, seqvarn = TRTSEQPN
options(tfl.study = env$study)

## one row per participant; ALL ENROLLED for disposition rows
adsl <- adam$adsl %>% filter(ENRLFL == "Y")

## --- column denominators (N=) per fixed sequence + Total --------------------
## Population = enrolled (ENRLFL); % based on enrolled N (same set as numerator).
denom <- bign(adsl, trtvar = dv$seqvar, popfl = "ENRLFL")

## --- disposition categories (same row template as the SAS twin) -------------
## ADSL flags: SAFFL (Safety pop), PKFL (PK pop), TR0nSDTM (per-period dosing),
## EOSSTT (end-of-study status), DCSREAS (reason). Completion via EOSSTT.
dispo <- adsl %>%
  transmute(
    USUBJID,
    seq        = .data[[dv$seqvar]],
    Enrolled   = 1L,
    Safety     = if_else(SAFFL == "Y", 1L, 0L),
    PK         = if_else(PKFL  == "Y", 1L, 0L),
    DosedRef   = if_else(!is.na(TR01SDTM), 1L, 0L),   # dosed in reference period
    DosedTest  = if_else(!is.na(TR02SDTM), 1L, 0L),   # dosed in test period
    Completed  = if_else(EOSSTT == "COMPLETED",    1L, 0L),
    Discont    = if_else(EOSSTT == "DISCONTINUED", 1L, 0L),
    DCSREAS    = if_else(EOSSTT == "DISCONTINUED", DCSREAS, NA_character_))

## participant-level counts for the fixed disposition rows
fixed_rows <- dispo %>%
  group_by(seq) %>%
  summarise(
    `Participants enrolled`              = sum(Enrolled),
    `Included in Safety Population`      = sum(Safety),
    `Included in PK Population`          = sum(PK),
    `Dosed in reference period (Period 1)` = sum(DosedRef),
    `Dosed in test period (Period 2)`      = sum(DosedTest),
    `Completed the study`                = sum(Completed),
    `Discontinued the study`             = sum(Discont),
    .groups = "drop") %>%
  pivot_longer(-seq, names_to = "category", values_to = "n") %>%
  mutate(ord = match(category,
                     c("Participants enrolled",
                       "Included in Safety Population",
                       "Included in PK Population",
                       "Dosed in reference period (Period 1)",
                       "Dosed in test period (Period 2)",
                       "Completed the study",
                       "Discontinued the study")),
         level = 0L)

## --- discontinuation reasons (indented under "Discontinued") ---------------
dc_reasons <- dispo %>%
  filter(Discont == 1L, !is.na(DCSREAS)) %>%
  group_by(seq, category = DCSREAS) %>%
  summarise(n = n_distinct(USUBJID), .groups = "drop") %>%
  mutate(category = paste0("   ", category), ord = 99L, level = 1L)

## --- assemble: n (%) per fixed-sequence column ------------------------------
rep <- bind_rows(fixed_rows, dc_reasons) %>%
  left_join(denom, by = c("seq" = "trt")) %>%
  mutate(value = n_pct(n, N)) %>%
  arrange(ord, category) %>%
  select(category, level, seq, value) %>%
  pivot_wider(names_from = seq, values_from = value)

ttl <- tfl_titles(num = "14.1.1", type = "Table", text = "Participant Disposition",
   pop  = "All Enrolled Participants",
   foot = paste("Single-fixed-sequence design: Period 1 reference (victim alone),",
                "Period 2 test (victim + perpetrator). Percentages based on the",
                "number of participants enrolled. A participant discontinuing",
                "before Period 2 contributes to reference-period dosing only."))

## rtables layout: category rows x fixed-sequence column(s) + Total
lyt <- basic_table(title = ttl$titles[3], main_footer = ttl$footnotes) %>%
  analyze("category", afun = function(x) in_rows(.list = as.list(x)))
# tbl <- build_table(lyt, rep)   ## or gt::gt(rep)
print(rep)
