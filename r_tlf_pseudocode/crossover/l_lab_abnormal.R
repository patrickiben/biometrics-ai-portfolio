################################################################################
# LISTING   : l_lab_abnormal  (Crossover - 2x2 or Williams)
# TITLE     : Listing of Abnormal Laboratory Values
# POPULATION: Safety Population (SAFFL == "Y"), on-treatment records (ONTRTFL == "Y")
# INPUT     : ADLB (PARAMCD/PARAM, AVAL, BASE, CHG, ANRIND, A1LO, A1HI, ATOXGRN,
#             AVISIT/AVISITN, ADT/ADY, TRTA/TRTAN, APERIOD/APERIODC, TRTSEQP, ONTRTFL)
# NOTE      : PSEUDOCODE. One row per ABNORMAL on-treatment laboratory record,
#             where abnormal = ANRIND in (LOW,HIGH) OR a CTCAE toxicity grade
#             >= 1 (ATOXGRN), on-treatment scope ONTRTFL == "Y", matching the SAS
#             twin. Crossover: ordered by SEQUENCE (dv$seqvar = TRTSEQP, the
#             participant-level fixed sequence label), then participant, PERIOD
#             (dv$byperiod), analyte and collection day, so each record is anchored
#             to the period in which it occurred and TRTA (actual treatment) names
#             the treatment given in that period. Baseline context travels on each
#             abnormal row via the BASE and CHG columns (NOT separate baseline rows).
#             A listing reproduces data (no statistics, no denominators).
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("CROSSOVER")    # trtvar = TRTA ; seqvar = TRTSEQP ; byperiod = APERIOD/APERIODC

## abnormal on-treatment lab records (matches SAS: SAFFL='Y' AND ONTRTFL='Y' AND
## (ANRIND in LOW/HIGH OR ATOXGRN >= 1)); baseline context via BASE/CHG columns.
lab_abn <- adam$adlb %>%
  filter(SAFFL == "Y", ONTRTFL == "Y",                  # on-treatment scope
         toupper(ANRIND) %in% c("LOW", "HIGH") |        # abnormal = Low/High OR
           (!is.na(ATOXGRN) & ATOXGRN >= 1)) %>%        #   CTCAE toxicity grade >= 1
  mutate(seq    = .data[[dv$seqvar]],          # TRTSEQP  (participant-level sequence)
         period = .data[[dv$byperiod[2]]],     # APERIODC (Period 1/2/...)
         trt    = .data[[dv$trtvar]],          # TRTA     (actual treatment)
         ## Low/High direction from the normal-range indicator (same as SAS twin)
         flag   = case_when(toupper(ANRIND) == "HIGH" ~ "High",
                            toupper(ANRIND) == "LOW"  ~ "Low",
                            TRUE                       ~ ""))

lst <- lab_abn %>%
  arrange(seq, USUBJID, APERIOD, PARAM, ADY) %>%   # sequence, participant, period, analyte, day
  transmute(
    `Sequence`       = seq,
    `Participant`    = str_extract(USUBJID, "[^-]+$"),
    `Period`         = period,
    `Treatment`      = trt,
    `Parameter`      = PARAM,
    `Visit`          = AVISIT,
    `Day`            = ADY,
    `Value`          = sprintf("%.3g", AVAL),
    `Baseline`       = sprintf("%.3g", BASE),
    `Change`         = sprintf("%.3g", CHG),
    `Reference Range`= sprintf("%.3g - %.3g", A1LO, A1HI),
    `Flag`           = flag,
    `Grade`          = ifelse(is.na(ATOXGRN), "", as.character(ATOXGRN)))   # CTCAE toxicity grade

ttl <- tfl_titles(num = "16.2.8.2", type = "Listing",
   text = "Listing of Abnormal Laboratory Values",
   pop  = "Safety Population",
   foot = paste0("Abnormal = normal-range indicator Low/High (ANRIND) OR a CTCAE ",
                 "toxicity grade >= 1 (ATOXGRN); on-treatment records (ONTRTFL = Y). ",
                 "Sequence = randomized treatment order (TRTSEQP); Period = treatment ",
                 "period; Treatment = analysis treatment in that period (crossover). ",
                 "Reference range = A1LO - A1HI. SI units. Source: ADLB."))

## listings render via gt (or rtables as_html); no statistics / denominators
# gt::gt(lst) |> gt::tab_header(title = ttl$titles[3]) |>
#   gt::tab_source_note(ttl$footnotes[1])
print(lst)
