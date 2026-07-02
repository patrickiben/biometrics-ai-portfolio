################################################################################
# TABLE     : t_lab_shift  (Crossover - 2x2 or Williams)
# TITLE     : Shift from Baseline to Worst Post-Baseline Laboratory Result
#             by Treatment and Period
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADLB (PARAMCD; BNRIND baseline index, ANRIND analysis index)
# NOTE      : PSEUDOCODE. Cross-tab of baseline reference range category
#             (BNRIND) x WORST post-baseline category, by analyte/treatment.
#             Crossover: one shift per participant PER TREATMENT (within-participant),
#             so the baseline and the worst post-baseline are taken WITHIN each
#             treatment period (dv$byperiod) and reported by actual treatment
#             (dv$trtvar = TRTA). HOUSE RULE: worst = category FURTHEST from
#             NORMAL (rank LOW/NORMAL/HIGH -> max abs(rank-2)), NOT the LOW<
#             NORMAL<HIGH ordinal max(); direction resolved on the chosen row.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("CROSSOVER")                 # trtvar = TRTA ; byperiod = APERIOD/APERIODC

analytes <- c("ALT","AST","BILI","ALP","CREAT","BUN","GLUC","HGB","WBC","PLAT","K","NA")

## rank ANRIND so "worst" = furthest from NORMAL (NORMAL=2 -> abs(rank-2))
nri_rank <- c("LOW" = 1L, "NORMAL" = 2L, "HIGH" = 3L)

lb <- adam$adlb %>%
  filter(SAFFL == "Y", PARAMCD %in% analytes) %>%
  mutate(trt    = .data[[dv$trtvar]],
         period = .data[[dv$byperiod[2]]])           # APERIODC label

## --- baseline category within treatment/period (one per subj x trt x param)
base_cat <- lb %>%
  filter(ABLFL == "Y", !is.na(BNRIND)) %>%
  distinct(USUBJID, trt, period, PARAM, base_ind = BNRIND)

## --- WORST post-baseline category within treatment/period -------------------
## choose the row with max abs(rank-2); ties -> prefer HIGH side then LOW.
worst_cat <- lb %>%
  filter(ONTRTFL == "Y", !is.na(ANRIND)) %>%
  mutate(rank = nri_rank[toupper(ANRIND)],
         dist = abs(rank - 2L)) %>%
  group_by(USUBJID, trt, period, PARAM) %>%
  arrange(desc(dist), desc(rank), .by_group = TRUE) %>%   # furthest-from-normal, HIGH wins ties
  slice(1) %>%
  ungroup() %>%
  transmute(USUBJID, trt, period, PARAM, worst_ind = ANRIND)

## --- shift pairs (one per participant per treatment) ----------------------------
shift <- base_cat %>%
  inner_join(worst_cat, by = c("USUBJID","trt","period","PARAM")) %>%
  mutate(base_ind  = factor(toupper(base_ind),  levels = c("LOW","NORMAL","HIGH")),
         worst_ind = factor(toupper(worst_ind), levels = c("LOW","NORMAL","HIGH")))

## column denominators (N=) per treatment + Total
denom <- bign(adam$adsl %>%
                left_join(distinct(shift, USUBJID, !!sym(dv$trtvar) := trt), by = "USUBJID"),
              trtvar = dv$trtvar, popfl = "SAFFL")

## --- shift counts: distinct participants per base x worst cell, by analyte/trt --
cells <- shift %>%
  group_by(PARAM, trt, base_ind, worst_ind) %>%
  summarise(n = n_distinct(USUBJID), .groups = "drop") %>%
  left_join(denom, by = c("trt")) %>%
  mutate(disp = n_pct(n, N)) %>%
  complete(PARAM, trt, base_ind, worst_ind, fill = list(disp = "0 (0.0%)"))

tab <- cells %>%
  select(PARAM, trt, base_ind, worst_ind, disp) %>%
  pivot_wider(names_from = worst_ind, values_from = disp) %>%
  arrange(PARAM, trt, base_ind)

ttl <- tfl_titles(num = "14.3.4.2", type = "Table",
   text = "Shift from Baseline to Worst Post-Baseline Laboratory Result by Treatment and Period",
   pop  = "Safety Population",
   foot = "Worst post-baseline = category furthest from NORMAL (Low/Normal/High). Baseline and worst taken within each treatment period (within-participant). Rows = baseline category; columns = worst on-treatment category. Source: ADLB (BNRIND, ANRIND).")

## rtables layout: analyte > treatment, baseline-category rows x worst cols
lyt <- basic_table(title = ttl$titles[3], main_footer = ttl$footnotes) %>%
  split_rows_by("PARAM", page_by = TRUE) %>%
  split_rows_by("trt",   page_by = FALSE) %>%
  analyze("base_ind", afun = function(x) in_rows(.list = as.list(x)))
# tbl <- build_table(lyt, tab)   ## or gt::gt(tab)
print(tab)
