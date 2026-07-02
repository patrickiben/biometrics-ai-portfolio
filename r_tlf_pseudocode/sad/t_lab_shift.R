################################################################################
# TABLE     : t_lab_shift  (Single Ascending Dose)
# TITLE     : Shift from Baseline to Worst Post-Baseline Laboratory Result
#             by Dose Level
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADLB (PARAMCD/PARAM, BNRIND baseline index, ANRIND post-baseline
#             index, ONTRTFL, ANL01FL)
# NOTE      : PSEUDOCODE. SAD = parallel dose cohorts; column variable = DOSE
#             LEVEL (dv$trtvar = TRT01A), placebo pooled. Cross-tab Baseline
#             category (BNRIND) x WORST post-baseline category per participant/
#             parameter. Counts = distinct PARTICIPANTS; % denominator = participants
#             with a non-missing baseline in that row, per dose level. WORST =
#             category FURTHEST from NORMAL (not the max() of the
#             LOW<NORMAL<HIGH ordinal); ties resolved to High.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SAD")                      # column = TRT01A (= dose level)

cat_levels <- c("LOW","NORMAL","HIGH")

## post-baseline records with a usable normal-range index
post <- adam$adlb %>%
  filter(SAFFL == "Y", ONTRTFL == "Y", ANL01FL == "Y",
         PARAMCD %in% c("ALT","AST","BILI","ALP","CREAT","K","NA","HGB","WBC","PLAT"),
         !is.na(ANRIND)) %>%
  mutate(trt   = .data[[dv$trtvar]],           # dose-level column
         indf  = factor(toupper(ANRIND), levels = cat_levels),
         rank  = as.integer(indf),             # LOW=1 NORMAL=2 HIGH=3
         dist  = abs(rank - 2L))               # distance from NORMAL

## --- WORST post-baseline = furthest from NORMAL; tie-break to HIGH ----------
## per participant/param keep the row with max dist; on ties prefer HIGH over LOW
worst <- post %>%
  group_by(USUBJID, trt, PARAMCD, PARAM) %>%
  arrange(desc(dist), desc(rank), .by_group = TRUE) %>%   # furthest, then HIGH
  slice(1) %>%
  ungroup() %>%
  transmute(USUBJID, trt, PARAMCD, PARAM, worst = factor(indf, levels = cat_levels))

## --- baseline category per participant/param (one row), non-missing only -------
base <- adam$adlb %>%
  filter(SAFFL == "Y", ABLFL == "Y", !is.na(BNRIND), PARAMCD %in% unique(worst$PARAMCD)) %>%
  transmute(USUBJID, PARAMCD,
            base = factor(toupper(BNRIND), levels = cat_levels)) %>%
  distinct(USUBJID, PARAMCD, .keep_all = TRUE)

## --- participant-level shift pairs; complete the 3x3 grid per param x dose ------
shift <- worst %>%
  inner_join(base, by = c("USUBJID","PARAMCD")) %>%
  count(trt, PARAM, base, worst, name = "nsubj") %>%       # distinct participants (1 row/subj)
  complete(nesting(trt, PARAM), base = factor(cat_levels, cat_levels),
           worst = factor(cat_levels, cat_levels), fill = list(nsubj = 0L))

## --- denominator = participants with that baseline category, per param x dose ---
row_denom <- shift %>% group_by(trt, PARAM, base) %>%
  summarise(rowN = sum(nsubj), .groups = "drop")

tab <- shift %>%
  left_join(row_denom, by = c("trt","PARAM","base")) %>%
  mutate(cell = if_else(rowN > 0, sprintf("%d (%.1f%%)", nsubj, 100*nsubj/rowN),
                        sprintf("%d", nsubj))) %>%
  arrange(PARAM, trt, base, worst) %>%
  select(PARAM, trt, base, worst, cell) %>%
  pivot_wider(names_from = worst, values_from = cell)      # columns: LOW/NORMAL/HIGH worst

ttl <- tfl_titles(num = "14.3.4.2", type = "Table",
   text = "Shift from Baseline to Worst Post-Baseline Laboratory Result by Dose Level",
   pop  = "Safety Population",
   foot = paste("Worst post-baseline category = result furthest from normal",
                "(ties resolved to High). A participant counted once per parameter.",
                "% = participants in the baseline-category row, per dose level (placebo",
                "pooled). Participants with missing baseline or no normal range excluded."))

## render: per parameter, per dose-level block -> baseline rows x worst-cat columns
lyt <- basic_table(title = ttl$titles[3], main_footer = ttl$footnotes) %>%
  split_rows_by("PARAM", page_by = TRUE) %>%
  split_cols_by(dv$trtvar) %>%                              # dose-level columns
  split_rows_by("base", split_label = "Baseline Category") %>%
  analyze(c("LOW","NORMAL","HIGH"))
# tbl <- build_table(lyt, tab)   ## or gt::gt(tab)
print(tab)
