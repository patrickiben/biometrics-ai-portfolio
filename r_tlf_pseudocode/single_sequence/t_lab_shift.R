################################################################################
# TABLE     : t_lab_shift  (Single-/Fixed-Sequence DDI)
# TITLE     : Shift from Baseline to Worst Post-Baseline Laboratory Result
#             by Period
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADLB (PARAMCD/PARAM, BNRIND baseline index, ANRIND post-baseline
#             index, APERIOD/APERIODC, ABLFL, ONTRTFL, ANL01FL)
# NOTE      : PSEUDOCODE. PERIOD table -> split by dv$byperiod (APERIOD/APERIODC):
#             Period 1 = reference (victim alone), Period 2 = test (victim +
#             perpetrator). Cross-tab the WITHIN-PERIOD baseline category (BNRIND
#             carried on the period's records) x WORST post-baseline category per
#             participant/parameter WITHIN PERIOD -- baseline and worst are both
#             taken within each period (no pooling across periods), matching the
#             SAS twin. Counts = distinct PARTICIPANTS; % denominator =
#             participants with a non-missing baseline in that row, per period.
#             WORST = category FURTHEST from NORMAL (rank LOW/NORMAL/HIGH then max
#             abs(rank-2); ties -> HIGH), NEVER the max() of the LOW<NORMAL<HIGH
#             ordinal.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SINGLESEQ")                 # byperiod = c("APERIOD","APERIODC")
options(tfl.study = env$study)
perC <- dv$byperiod[2]                           # character period label column

cat_levels <- c("LOW","NORMAL","HIGH")

## post-baseline records with a usable normal-range index, within period
post <- adam$adlb %>%
  filter(SAFFL == "Y", ONTRTFL == "Y", ANL01FL == "Y",
         PARAMCD %in% c("ALT","AST","BILI","ALP","CREAT","K","NA","HGB","WBC","PLAT"),
         !is.na(ANRIND)) %>%
  mutate(per   = .data[[perC]],
         indf  = factor(toupper(ANRIND), levels = cat_levels),
         rank  = as.integer(indf),                # LOW=1 NORMAL=2 HIGH=3
         dist  = abs(rank - 2L))                  # distance from NORMAL

## --- WORST post-baseline = furthest from NORMAL; tie-break to HIGH ----------
## per participant/param/PERIOD keep the row with max dist; on ties prefer HIGH.
## The WITHIN-PERIOD baseline category (BNRIND on the period's records) is carried
## through so baseline is taken within each period, matching the SAS twin.
worst <- post %>%
  group_by(USUBJID, per, PARAMCD, PARAM) %>%
  arrange(desc(dist), desc(rank), .by_group = TRUE) %>%   # furthest, then HIGH
  mutate(base = factor(toupper(first(BNRIND[!is.na(BNRIND)])), levels = cat_levels)) %>%
  slice(1) %>%
  ungroup() %>%
  transmute(USUBJID, per, PARAMCD, PARAM,
            base, worst = factor(indf, levels = cat_levels)) %>%
  filter(!is.na(base))                                    # need a within-period baseline

## --- participant-level shift pairs; complete the 3x3 grid per param x PERIOD ----
shift <- worst %>%
  count(per, PARAM, base, worst, name = "nsubj") %>%      # distinct participants (1 row/subj/period)
  complete(nesting(per, PARAM), base = factor(cat_levels, cat_levels),
           worst = factor(cat_levels, cat_levels), fill = list(nsubj = 0L))

## --- denominator = participants with that baseline category, per param x PERIOD --
row_denom <- shift %>% group_by(per, PARAM, base) %>%
  summarise(rowN = sum(nsubj), .groups = "drop")

tab <- shift %>%
  left_join(row_denom, by = c("per","PARAM","base")) %>%
  mutate(cell = if_else(rowN > 0, sprintf("%d (%.1f%%)", nsubj, 100*nsubj/rowN),
                        sprintf("%d", nsubj))) %>%
  arrange(PARAM, per, base, worst) %>%
  select(PARAM, per, base, worst, cell) %>%
  pivot_wider(names_from = worst, values_from = cell)      # columns: LOW/NORMAL/HIGH worst

ttl <- tfl_titles(num = "14.3.4.2", type = "Table",
   text = "Shift from Baseline to Worst Post-Baseline Laboratory Result by Period",
   pop  = "Safety Population",
   foot = paste("Single-fixed-sequence DDI: Period 1 = reference (victim alone),",
                "Period 2 = test (victim + perpetrator). Worst post-baseline category",
                "= result furthest from normal (ties resolved to High). A participant",
                "counted once per parameter within period. % = participants in the",
                "baseline-category row, per period. Participants with missing baseline or",
                "no normal range excluded."))

## render: per parameter, per PERIOD block -> baseline rows x worst-category cols
lyt <- basic_table(title = ttl$titles[3], main_footer = ttl$footnotes) %>%
  split_rows_by("PARAM", page_by = TRUE) %>%
  split_cols_by("per") %>%
  split_rows_by("base", split_label = "Baseline Category") %>%
  analyze(c("LOW","NORMAL","HIGH"))
# tbl <- build_table(lyt, tab)   ## or gt::gt(tab)
print(tab)
