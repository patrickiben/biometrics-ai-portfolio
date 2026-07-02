################################################################################
# TABLE     : t_lab_marked_abnormal  (Parallel-group)
# TITLE     : Treatment-Emergent Markedly Abnormal Laboratory Values by Parameter
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADLB (PARAMCD/PARAM, ATOXGRN/BTOXGRN, ANRIND, ONTRTFL)
# NOTE      : PSEUDOCODE. "Markedly abnormal" = treatment-emergent CTCAE Grade >=3
#             (post-baseline grade worse than baseline grade), matching the SAS
#             twin. Counts = distinct USUBJID with >=1 qualifying post-baseline
#             value per analyte; % denominator = SAFFL N per arm from bign().
#             Per parameter three criterion rows are reported: Any Markedly
#             Abnormal, Markedly High, Markedly Low. Direction (High/Low) from
#             ANRIND; "Any" counts all qualifying records regardless of
#             direction. Columns = treatment arms (= dose level) + Total.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("PARALLEL")                 # column = TRT01A (= dose level)

denom <- bign(adam$adsl, trtvar = dv$trtvar, popfl = "SAFFL")

## treatment-emergent CTCAE Grade >=3 = ATOXGRN >= 3 AND ATOXGRN > baseline grade
## (coalesce baseline grade to 0 when missing). Direction split via ANRIND.
lb <- adam$adlb %>%
  filter(SAFFL == "Y", ONTRTFL == "Y", !is.na(ATOXGRN),
         PARAMCD %in% c("ALT","AST","BILI","ALP","CREAT","K","NA","HGB","WBC","PLAT","GLUC")) %>%
  mutate(trt = .data[[dv$trtvar]],
         teae_marked = ATOXGRN >= 3 & ATOXGRN > coalesce(BTOXGRN, 0L),   # Grade >=3 emergent
         mhi = teae_marked & grepl("HIGH", toupper(coalesce(ANRIND, ""))),   # marked High
         mlo = teae_marked & grepl("LOW",  toupper(coalesce(ANRIND, ""))))   # marked Low

## --- distinct participants with >=1 marked (any/High/Low) per param x arm ------
## Any Markedly Abnormal = any qualifying record (direction-agnostic, so records
## whose ANRIND is neither High nor Low are still counted); High/Low = splits.
marked <- lb %>%
  group_by(trt, PARAMCD, PARAM, USUBJID) %>%
  summarise(any_mark = any(teae_marked), any_hi = any(mhi), any_lo = any(mlo),
            .groups = "drop") %>%
  group_by(trt, PARAMCD, PARAM) %>%
  summarise(`Any Markedly Abnormal` = n_distinct(USUBJID[any_mark]),
            `Markedly High`         = n_distinct(USUBJID[any_hi]),
            `Markedly Low`          = n_distinct(USUBJID[any_lo]),
            .groups = "drop")

## --- Total column: distinct across all arms (participant can appear once) -------
total <- lb %>%
  group_by(PARAMCD, PARAM, USUBJID) %>%
  summarise(any_mark = any(teae_marked), any_hi = any(mhi), any_lo = any(mlo),
            .groups = "drop") %>%
  mutate(trt = "Total") %>%
  group_by(trt, PARAMCD, PARAM) %>%
  summarise(`Any Markedly Abnormal` = n_distinct(USUBJID[any_mark]),
            `Markedly High`         = n_distinct(USUBJID[any_hi]),
            `Markedly Low`          = n_distinct(USUBJID[any_lo]),
            .groups = "drop")

## --- n (%) with population-N denominator per column ------------------------
tab <- bind_rows(marked, total) %>%
  pivot_longer(c(`Any Markedly Abnormal`,`Markedly High`,`Markedly Low`),
               names_to = "criterion", values_to = "nsubj") %>%
  left_join(denom, by = c("trt")) %>%
  mutate(value = n_pct(nsubj, N)) %>%
  arrange(PARAM,
          factor(criterion, c("Any Markedly Abnormal","Markedly High","Markedly Low"))) %>%
  select(PARAM, criterion, trt, value) %>%
  pivot_wider(names_from = trt, values_from = value)

ttl <- tfl_titles(num = "14.3.4.3", type = "Table",
   text = "Treatment-Emergent Markedly Abnormal Laboratory Values by Parameter",
   pop  = "Safety Population",
   foot = paste0("Markedly abnormal = treatment-emergent CTCAE Grade >=3 ",
                 "(post-baseline grade worse than baseline). Markedly High/Low ",
                 "from ANRIND direction; Any = any qualifying record. A participant ",
                 "counted once per criterion per parameter. % = participants / N in arm."))

## render: PARAM split -> criterion rows x arm + Total columns
lyt <- basic_table(title = ttl$titles[3], main_footer = ttl$footnotes) %>%
  split_rows_by("PARAM", page_by = FALSE) %>%
  analyze("criterion", afun = function(x) in_rows(.list = as.list(x)))
# tbl <- build_table(lyt, tab)   ## or gt::gt(tab)
print(tab)
