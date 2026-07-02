################################################################################
# TABLE     : t_lab_marked_abnormal  (Multiple Ascending Dose)
# TITLE     : Treatment-Emergent Markedly Abnormal Laboratory Values by Dose Level
# POPULATION: Safety Population (SAFFL == "Y"), on-treatment evaluable
# INPUT     : ADLB (PARAMCD/PARAM, ATOXGRN, BTOXGRN, ATOXGRH, ATOXGRL, ANRIND,
#             ADY, ONTRTFL, SAFFL)
# NOTE      : PSEUDOCODE. MAD = parallel dose cohorts with REPEATED dosing; column
#             variable = DOSE LEVEL (dv$trtvar = TRT01A) + Total. Marked abnormality
#             = TREATMENT-EMERGENT CTCAE Grade >= 3: ATOXGRN >= 3 AND
#             ATOXGRN > coalesce(BTOXGRN, 0) (post-baseline grade worse than baseline).
#             Direction (Low/High) from ATOXGRH/ATOXGRL (or ANRIND fallback). A
#             qualifying value at ANY on-treatment dosing day across the repeated-dose
#             period flags the participant. Counts = distinct USUBJID; % denominator =
#             on-treatment evaluable N from ADLB (SAFFL='Y' & ONTRTFL='Y', distinct
#             USUBJID). Fold-of-limit (xULN/xLLN) logic NOT used.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("MAD")                      # column = TRT01A (= dose level)

## ON-treatment spans the full repeated-dosing period; a qualifying value on any
## dosing day flags the participant. Treatment-emergent CTCAE Grade >= 3.
lb <- adam$adlb %>%
  filter(SAFFL == "Y", ONTRTFL == "Y",
         PARAMCD %in% c("ALT","AST","BILI","ALP","CREAT","K","NA","HGB","WBC","PLAT","GLUC")) %>%
  mutate(trt = .data[[dv$trtvar]],
         ## treatment-emergent CTCAE Grade >= 3 (post-baseline grade worse than baseline)
         te_marked = !is.na(ATOXGRN) & ATOXGRN >= 3 & ATOXGRN > coalesce(BTOXGRN, 0),
         ## direction from CTCAE high/low grade vars (fallback to ANRIND)
         mhi = te_marked & ((!is.na(ATOXGRH) & ATOXGRH >= 3) |
                            (is.na(ATOXGRH) & toupper(coalesce(ANRIND,"")) == "HIGH")),
         mlo = te_marked & ((!is.na(ATOXGRL) & ATOXGRL >= 3) |
                            (is.na(ATOXGRL) & toupper(coalesce(ANRIND,"")) == "LOW")))

## --- denominator: on-treatment evaluable N from ADLB (distinct USUBJID) -----
denom <- lb %>%
  group_by(trt) %>% summarise(N = n_distinct(USUBJID), .groups = "drop") %>%
  bind_rows(tibble(trt = "Total", N = n_distinct(lb$USUBJID)))

## --- distinct participants with >=1 marked High / Low / either, per param x dose -
marked <- lb %>%
  group_by(trt, PARAMCD, PARAM, USUBJID) %>%
  summarise(any_hi = any(mhi), any_lo = any(mlo), .groups = "drop") %>%
  mutate(any_mark = any_hi | any_lo) %>%
  group_by(trt, PARAMCD, PARAM) %>%
  summarise(`Markedly High`   = n_distinct(USUBJID[any_hi]),
            `Markedly Low`    = n_distinct(USUBJID[any_lo]),
            `Any Marked`      = n_distinct(USUBJID[any_mark]),
            .groups = "drop")

## --- Total column: distinct across all dose levels (participant appears once) ----
total <- lb %>%
  group_by(PARAMCD, PARAM, USUBJID) %>%
  summarise(any_hi = any(mhi), any_lo = any(mlo), .groups = "drop") %>%
  mutate(any_mark = any_hi | any_lo, trt = "Total") %>%
  group_by(trt, PARAMCD, PARAM) %>%
  summarise(`Markedly High`   = n_distinct(USUBJID[any_hi]),
            `Markedly Low`    = n_distinct(USUBJID[any_lo]),
            `Any Marked`      = n_distinct(USUBJID[any_mark]),
            .groups = "drop")

## --- n (%) with population-N denominator per column ------------------------
tab <- bind_rows(marked, total) %>%
  pivot_longer(c(`Markedly High`,`Markedly Low`,`Any Marked`),
               names_to = "criterion", values_to = "nsubj") %>%
  left_join(denom, by = c("trt")) %>%
  mutate(value = n_pct(nsubj, N)) %>%
  arrange(PARAM,
          factor(criterion, c("Any Marked","Markedly High","Markedly Low"))) %>%
  select(PARAM, criterion, trt, value) %>%
  pivot_wider(names_from = trt, values_from = value)

ttl <- tfl_titles(num = "14.3.4.3", type = "Table",
   text = "Treatment-Emergent Markedly Abnormal Laboratory Values by Dose Level",
   pop  = "Safety Population",
   foot = paste0("Markedly abnormal = treatment-emergent CTCAE Grade >= 3 ",
                 "(ATOXGRN >= 3 and ATOXGRN > baseline grade). Direction (High/Low) from ",
                 "ATOXGRH/ATOXGRL (ANRIND fallback). A qualifying value on any on-treatment ",
                 "dosing day (MAD repeated dosing) flags the participant; counted once per ",
                 "criterion per analyte. Denominator = on-treatment evaluable N (SAFFL='Y' & ",
                 "ONTRTFL='Y', distinct USUBJID) per dose level."))

## render: PARAM split -> criterion rows x dose level + Total columns
lyt <- basic_table(title = ttl$titles[3], main_footer = ttl$footnotes) %>%
  split_rows_by("PARAM", page_by = FALSE) %>%
  analyze("criterion", afun = function(x) in_rows(.list = as.list(x)))
# tbl <- build_table(lyt, tab)   ## or gt::gt(tab)
print(tab)
