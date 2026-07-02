################################################################################
# TABLE     : t_lab_marked_abnormal  (Single-/Fixed-Sequence DDI)
# TITLE     : Treatment-Emergent Markedly Abnormal Laboratory Values by Parameter
#             and Period
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADLB (PARAMCD/PARAM, ATOXGRN, BTOXGRN, ATOXGRH/ATOXGRL, ANRIND,
#             APERIOD/APERIODC, ONTRTFL)
# NOTE      : PSEUDOCODE. "Markedly abnormal" = treatment-emergent CTCAE Grade
#             >=3 (post-baseline grade worse than within-period baseline grade),
#             matching the SAS twin. PERIOD table -> split by dv$byperiod
#             (APERIOD/APERIODC): Period 1 = reference (victim alone), Period 2 =
#             test (victim + perpetrator). Counts PARTICIPANTS (distinct USUBJID)
#             with >=1 qualifying value per analyte WITHIN PERIOD, split Low/High.
#             % denominator = on-treatment evaluable N from ADLB (SAFFL="Y" &
#             ONTRTFL="Y", distinct USUBJID per period) -- same source as SAS.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SINGLESEQ")                 # byperiod = c("APERIOD","APERIODC")
options(tfl.study = env$study)
perC <- dv$byperiod[2]                           # character period label column

## --- per-PERIOD denominators FROM ADLB (on-treatment evaluable, same as SAS) ----
## Denominator = distinct USUBJID per period with an on-treatment ADLB record.
perdenom <- adam$adlb %>%
  filter(SAFFL == "Y", ONTRTFL == "Y") %>%
  group_by(trt = .data[[perC]]) %>%
  summarise(N = n_distinct(USUBJID), .groups = "drop")

lb <- adam$adlb %>%
  filter(SAFFL == "Y", ONTRTFL == "Y", !is.na(ATOXGRN), !is.na(.data[[perC]])) %>%
  mutate(per = .data[[perC]],
         btoxn = coalesce(BTOXGRN, 0),                          # missing baseline -> 0
         te_marked = ATOXGRN >= 3 & ATOXGRN > btoxn,            # treatment-emergent Gr >=3
         ## direction (Low/High) from grade-direction columns, else ANRIND
         dir = case_when(
           !is.na(ATOXGRH) & ATOXGRH >= 3 ~ "High",
           !is.na(ATOXGRL) & ATOXGRL >= 3 ~ "Low",
           grepl("HIGH", toupper(coalesce(ANRIND,""))) ~ "High",
           grepl("LOW",  toupper(coalesce(ANRIND,""))) ~ "Low",
           TRUE ~ NA_character_))

## --- distinct participants with >=1 treatment-emergent marked High / Low ------
marked <- lb %>%
  filter(te_marked, !is.na(dir)) %>%
  group_by(trt = per, PARAMCD, PARAM, dir) %>%
  summarise(nsubj = n_distinct(USUBJID), .groups = "drop")

## --- n (%) with per-PERIOD on-treatment-evaluable denominator ----------------
tab <- marked %>%
  left_join(perdenom, by = "trt") %>%
  mutate(value = n_pct(nsubj, N)) %>%
  arrange(PARAM, factor(dir, c("High","Low")), trt) %>%
  select(PARAM, Direction = dir, trt, value) %>%
  pivot_wider(names_from = trt, values_from = value)        # columns = PERIODs

ttl <- tfl_titles(num = "14.3.4.3", type = "Table",
   text = "Treatment-Emergent Markedly Abnormal Laboratory Values by Parameter and Period",
   pop  = "Safety Population",
   foot = paste0("Single-fixed-sequence DDI: Period 1 = reference (victim alone), ",
                 "Period 2 = test (victim + perpetrator). Markedly abnormal = ",
                 "treatment-emergent CTCAE Grade >=3 (post-baseline grade worse than ",
                 "within-period baseline grade). A participant counted once per ",
                 "parameter/direction within period. % = participants / N evaluable ",
                 "in period (ADLB, SAFFL = Y & ONTRTFL = Y)."))

## render: PARAM split -> Direction (Low/High) rows x PERIOD columns
lyt <- basic_table(title = ttl$titles[3], main_footer = ttl$footnotes) %>%
  split_rows_by("PARAM", page_by = FALSE) %>%
  analyze("Direction", afun = function(x) in_rows(.list = as.list(x)))
# tbl <- build_table(lyt, tab)   ## or gt::gt(tab)
print(tab)
