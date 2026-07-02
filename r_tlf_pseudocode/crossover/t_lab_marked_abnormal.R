################################################################################
# TABLE     : t_lab_marked_abnormal  (Crossover - 2x2 or Williams)
# TITLE     : Participants with Markedly Abnormal (PCSA) Laboratory Values
#             by Treatment and Period
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADLB (PARAMCD; AVAL, A1HI, A1LO limits, ANRIND, R2ULN)
# NOTE      : PSEUDOCODE. Counts of participants with >=1 potentially clinically
#             significant (markedly abnormal) post-baseline result, by direction
#             (High / Low) within each analyte. Crossover: assessed WITHIN each
#             treatment period and reported by actual treatment (dv$trtvar=TRTA);
#             a participant can be flagged under more than one treatment. HOUSE RULE:
#             guard limit comparisons with !is.na(A1HI)/!is.na(A1LO) before
#             classifying High vs Low. Counts = distinct participants (not rows);
#             denominator = treatment column N from bign().
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("CROSSOVER")                 # trtvar = TRTA ; byperiod = APERIOD/APERIODC

analytes <- c("ALT","AST","BILI","ALP","CREAT","BUN","GLUC","HGB","WBC","PLAT","K","NA")

## marked-abnormal (PCSA) thresholds. Prefer an ADaM-provided PCSA flag if it
## exists (e.g. ALBTRVAL / a sponsor PCSAFL); else derive from A1HI/A1LO with
## the protocol multiples. Shown here as a derivation with NA-guards.
## NOTE: backtick-quote the sodium key -- a bare NA element name is mangled to
## "NA." by c(), so pcsa_mult_hi[PARAMCD=="NA"] would miss and fall back to 1.
pcsa_mult_hi <- c(ALT = 3, AST = 3, BILI = 2, ALP = 3, CREAT = 1.5,
                  BUN = 2, GLUC = 1.5, K = 1.1, `NA` = 1.05,
                  HGB = 1.2, WBC = 2, PLAT = 1.5)             # x A1HI (illustrative)
## marked-Low multiples of A1LO (below LLN), mirroring sibling 0.5 x LLN default
pcsa_mult_lo <- c(ALT = 0.5, AST = 0.5, BILI = 0.5, ALP = 0.5, CREAT = 0.5,
                  BUN = 0.5, GLUC = 0.5, K = 0.5, `NA` = 0.5,
                  HGB = 0.5, WBC = 0.5, PLAT = 0.5)           # x A1LO (illustrative)

lb <- adam$adlb %>%
  filter(SAFFL == "Y", ONTRTFL == "Y", PARAMCD %in% analytes, !is.na(AVAL)) %>%
  mutate(trt    = .data[[dv$trtvar]],
         period = .data[[dv$byperiod[2]]],
         ## guarded High / Low marked-abnormal classification
         mult_hi = coalesce(pcsa_mult_hi[PARAMCD], 1),
         mult_lo = coalesce(pcsa_mult_lo[PARAMCD], 0.5),
         hi_flag = !is.na(A1HI) & AVAL >  A1HI * mult_hi,
         lo_flag = !is.na(A1LO) & AVAL <  A1LO * mult_lo, # marked Low: < mult x LLN
         direction = case_when(hi_flag ~ "High",
                               lo_flag ~ "Low",
                               TRUE    ~ NA_character_)) %>%
  filter(!is.na(direction))

## column denominators (N=) per treatment + Total, Safety Population
denom <- bign(adam$adsl %>%
                left_join(distinct(adam$adlb %>% filter(SAFFL=="Y"),
                                   USUBJID, !!sym(dv$trtvar)), by = "USUBJID"),
              trtvar = dv$trtvar, popfl = "SAFFL")

## participants with >=1 marked-abnormal result, by analyte x direction x treatment
ma <- lb %>%
  group_by(PARAM, trt, direction) %>%
  summarise(n = n_distinct(USUBJID), .groups = "drop") %>%
  left_join(denom, by = "trt") %>%
  mutate(disp = n_pct(n, N))

## any-direction "marked abnormal (any)" overall row per analyte/treatment
any_ma <- lb %>%
  group_by(PARAM, trt) %>%
  summarise(n = n_distinct(USUBJID), .groups = "drop") %>%
  left_join(denom, by = "trt") %>%
  mutate(direction = "Any markedly abnormal", disp = n_pct(n, N))

tab <- bind_rows(any_ma, ma) %>%
  mutate(direction = factor(direction,
           levels = c("Any markedly abnormal","High","Low"))) %>%
  select(PARAM, trt, direction, disp) %>%
  pivot_wider(names_from = trt, values_from = disp) %>%
  arrange(PARAM, direction)

ttl <- tfl_titles(num = "14.3.4.3", type = "Table",
   text = "Participants with Markedly Abnormal Laboratory Values by Treatment and Period",
   pop  = "Safety Population",
   foot = "Markedly abnormal = potentially clinically significant per protocol (High: AVAL > multiple x A1HI; Low: AVAL < multiple x A1LO), assessed within each treatment period. Counts = distinct participants with >=1 qualifying on-treatment result. Percentages on treatment-column N. Source: ADLB.")

## rtables layout: analyte rows, direction sub-rows, treatment columns
lyt <- basic_table(title = ttl$titles[3], main_footer = ttl$footnotes) %>%
  split_rows_by("PARAM", page_by = TRUE) %>%
  analyze("direction", afun = function(x) in_rows(.list = as.list(x)))
# tbl <- build_table(lyt, tab)   ## or gt::gt(tab)
print(tab)
