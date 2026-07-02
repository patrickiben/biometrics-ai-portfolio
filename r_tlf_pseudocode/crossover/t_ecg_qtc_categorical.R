################################################################################
# TABLE     : t_ecg_qtc_categorical  (Crossover - 2x2 or Williams)
# TITLE     : Categorical Summary of QTcF: Maximum Post-Baseline Value and
#             Maximum Change from Baseline by Treatment
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADEG (PARAMCD = QTCF; AVAL, CHG, post-baseline)
# NOTE      : PSEUDOCODE. Counts = PARTICIPANTS (n_distinct USUBJID), NOT records.
#             ICH E14 thresholds -- absolute QTcF: >450, >480, >500 ms;
#             change from baseline: >30, >60 ms. Categories are CUMULATIVE (not
#             mutually exclusive) per E14 convention -- a participant may appear
#             in more than one category. Crossover: counted per
#             TREATMENT (dv$trtvar = TRTA); each participant can appear under more
#             than one treatment (once per treatment received). % denominator =
#             participants with >=1 post-baseline QTcF in that treatment.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("CROSSOVER")                 # trtvar = TRTA

eg <- adam$adeg %>%
  filter(SAFFL == "Y", PARAMCD == "QTCF", ANL01FL == "Y", ABLFL != "Y") %>%   # post-baseline
  mutate(trt = .data[[dv$trtvar]])

## per-treatment denominator: participants with >=1 evaluable post-baseline QTcF
denom <- eg %>% filter(!is.na(AVAL)) %>%
  group_by(trt) %>% summarise(N = n_distinct(USUBJID), .groups = "drop")

## --- per participant x treatment: worst (max) absolute QTcF and max CHG ---------
worst <- eg %>%
  group_by(USUBJID, trt) %>%
  summarise(maxQT  = if (all(is.na(AVAL))) NA_real_ else max(AVAL, na.rm = TRUE),
            maxCHG = if (all(is.na(CHG)))  NA_real_ else max(CHG,  na.rm = TRUE),
            .groups = "drop")

## --- absolute QTcF: CUMULATIVE ICH E14 thresholds (not mutually exclusive) ---
## each threshold counts distinct participants whose worst value exceeds it
## (0-counts emit naturally) -- matches the SAS v450/v480/v500 indicator logic.
abs_cat <- worst %>% filter(!is.na(maxQT)) %>%
  group_by(trt) %>%
  summarise(`> 450 ms` = n_distinct(USUBJID[maxQT > 450]),
            `> 480 ms` = n_distinct(USUBJID[maxQT > 480]),
            `> 500 ms` = n_distinct(USUBJID[maxQT > 500]),
            .groups = "drop") %>%
  pivot_longer(-trt, names_to = "cat", values_to = "n") %>%
  mutate(block = "Maximum post-baseline QTcF")

## --- change from baseline: CUMULATIVE thresholds (not mutually exclusive) ----
chg_cat <- worst %>% filter(!is.na(maxCHG)) %>%
  group_by(trt) %>%
  summarise(`> 30 ms` = n_distinct(USUBJID[maxCHG > 30]),
            `> 60 ms` = n_distinct(USUBJID[maxCHG > 60]),
            .groups = "drop") %>%
  pivot_longer(-trt, names_to = "cat", values_to = "n") %>%
  mutate(block = "Maximum increase from baseline in QTcF")

## fixed category order within each block for display
cat_order <- c("> 450 ms","> 480 ms","> 500 ms","> 30 ms","> 60 ms")

rep <- bind_rows(abs_cat, chg_cat) %>%
  left_join(denom, by = "trt") %>%
  mutate(value = n_pct(n, N),                         # participants, % of treatment denom
         cat = factor(cat, levels = cat_order)) %>%
  arrange(block, cat) %>%
  select(block, cat, trt, value) %>%
  pivot_wider(names_from = trt, values_from = value)

ttl <- tfl_titles(num = "14.3.8.2", type = "Table",
   text = "Categorical Summary of QTcF (Maximum Value and Maximum Change) by Treatment",
   pop  = "Safety Population",
   foot = "ICH E14 thresholds. Categories are cumulative; a participant may appear in more than one category. % = participants with >=1 evaluable post-baseline QTcF in that treatment. A participant may contribute to more than one treatment column.")

## rtables: block -> category rows x treatment columns
lyt <- basic_table(title = ttl$titles[3], main_footer = ttl$footnotes) %>%
  split_rows_by("block", page_by = FALSE) %>%
  analyze("cat", afun = function(x) in_rows(.list = as.list(x)))
# tbl <- build_table(lyt, rep)
print(rep)
