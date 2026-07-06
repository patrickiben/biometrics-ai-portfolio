################################################################################
# TABLE     : t_lab_marked_abnormal  (Single Ascending Dose)
# TITLE     : Treatment-Emergent Markedly Abnormal Laboratory Values by Parameter
# POPULATION: Safety Population (SAFFL == "Y"), on-treatment evaluable
# INPUT     : ADLB (PARAMCD/PARAM, ATOXGR/ATOXGRN, BTOXGRN, ANRIND,
#             ATOXGRH/ATOXGRL, ONTRTFL)
# NOTE      : PSEUDOCODE. SAD = parallel dose cohorts; column = DOSE LEVEL
#             (dv$trtvar = TRT01A), placebo pooled, + Total. "Markedly abnormal"
#             = treatment-emergent CTCAE Grade >=3 worsening, i.e. ATOXGRN >= 3
#             AND ATOXGRN > coalesce(BTOXGRN, 0) (post-baseline grade worse than
#             baseline). Direction (Low/High) carried from ATOXGRH/ATOXGRL or
#             ANRIND. Counts PARTICIPANTS (distinct USUBJID) with >=1 qualifying
#             post-baseline value per analyte; all gradable labs reported (no
#             PARAMCD restriction). Denominator = on-treatment evaluable N from
#             ADLB (SAFFL == "Y" & ONTRTFL == "Y", distinct USUBJID per dose level)
#             -- identical to the SAS twin denominator. Single dose: no period
#             structure. Useful as a dose-escalation safety read-out across cohorts.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SAD")                      # column = TRT01A (= dose level)

## --- post-baseline records with a gradable toxicity ------------------------
lb <- adam$adlb %>%
  filter(SAFFL == "Y", ONTRTFL == "Y", !is.na(ATOXGRN)) %>%   # all gradable labs
  mutate(trt    = .data[[dv$trtvar]],                     # dose-level column
         btoxn  = dplyr::coalesce(BTOXGRN, 0),            # missing baseline = 0
         ## treatment-emergent markedly abnormal = Grade >=3 worse than baseline
         teae_marked = ATOXGRN >= 3 & ATOXGRN > btoxn,
         ## direction (Low/High) for the abnormality label
         dir    = dplyr::case_when(
                    !is.na(ATOXGRH) & ATOXGRH >= 3 ~ "High",
                    !is.na(ATOXGRL) & ATOXGRL >= 3 ~ "Low",
                    grepl("HIGH", toupper(ANRIND))  ~ "High",
                    grepl("LOW",  toupper(ANRIND))  ~ "Low",
                    TRUE                            ~ ""))

## --- denominator: on-treatment evaluable N (distinct USUBJID) per dose level + Total.
## Built from ADLB filtered SAFFL & ONTRTFL ONLY -- BEFORE the gradable-lab (ATOXGRN)
## filter -- so a participant with no gradable lab still counts, matching the SAS _bign
## twin. (Deriving N from `lb`, which already dropped missing ATOXGRN, understates the
## denominator and shifts every percentage.)
evalpop <- adam$adlb %>%
  filter(SAFFL == "Y", ONTRTFL == "Y") %>%
  mutate(trt = .data[[dv$trtvar]])
denom <- evalpop %>%
  group_by(trt) %>%
  summarise(N = n_distinct(USUBJID), .groups = "drop")
total_n <- tibble(trt = "Total", N = n_distinct(evalpop$USUBJID))
denom   <- bind_rows(denom, total_n)

## --- distinct participants with >=1 treatment-emergent marked value --------
marked <- lb %>%
  filter(teae_marked) %>%
  group_by(trt, PARAMCD, PARAM, dir) %>%
  summarise(nsubj = n_distinct(USUBJID), .groups = "drop")

## --- Total column: distinct across all dose levels (participant once) ------
total <- lb %>%
  filter(teae_marked) %>%
  mutate(trt = "Total") %>%
  group_by(trt, PARAMCD, PARAM, dir) %>%
  summarise(nsubj = n_distinct(USUBJID), .groups = "drop")

## --- n (%) with on-treatment evaluable-N denominator per column ------------
tab <- bind_rows(marked, total) %>%
  left_join(denom, by = "trt") %>%
  mutate(value = n_pct(nsubj, N)) %>%
  arrange(PARAM, factor(dir, c("Low","High"))) %>%
  select(PARAM, Direction = dir, trt, value) %>%
  pivot_wider(names_from = trt, values_from = value)        # dose columns + Total

ttl <- tfl_titles(num = "14.3.4.3", type = "Table",
   text = "Treatment-Emergent Markedly Abnormal Laboratory Values by Parameter",
   pop  = "Safety Population",
   foot = paste0("Markedly abnormal = treatment-emergent CTCAE Grade >=3 ",
                 "(post-baseline grade worse than baseline). A participant counted ",
                 "once per parameter/direction. Columns = dose levels (TRT01A); ",
                 "placebo pooled, ordered ascending. % = participants / on-treatment ",
                 "evaluable N in dose level."))

## render: PARAM split -> direction rows x dose-level + Total columns
lyt <- basic_table(title = ttl$titles[3], main_footer = ttl$footnotes) %>%
  split_rows_by("PARAM", page_by = FALSE) %>%
  analyze("Direction", afun = function(x) in_rows(.list = as.list(x)))
# tbl <- build_table(lyt, tab)   ## or gt::gt(tab)
print(tab)
