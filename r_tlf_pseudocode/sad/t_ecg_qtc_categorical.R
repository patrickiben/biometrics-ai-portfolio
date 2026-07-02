################################################################################
# TABLE     : t_ecg_qtc_categorical  (Single Ascending Dose)
# TITLE     : QTcF - Categorical Outliers (Absolute Value and Change from
#             Baseline)
# POPULATION: Safety Population (SAFFL == "Y"), post-baseline
# INPUT     : ADEG (PARAMCD == "QTCF")
# NOTE      : PSEUDOCODE. Participant-level outlier categories per ICH E14:
#             absolute QTcF (>450, >480, >500 ms) and change from baseline
#             (>30, >60 ms). Each participant counted once per category if they ever
#             cross the threshold post-baseline (worst on-treatment value).
#             Counts = distinct participants; % denominator = cohort N from bign().
#             SAD: column = dv$trtvar (TRT01A = DOSE LEVEL), ordered low -> high
#             by TRT01AN (placebo pooled first) so outlier frequency reads across
#             ascending dose. Single dose -> no period structure.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SAD")

## column denominators (N=) per dose cohort + Total
denom <- bign(adam$adsl, trtvar = dv$trtvar, popfl = "SAFFL")

## dose-cohort column order: placebo first, then ascending by TRT01AN ----------
dose_order <- adam$adsl %>% filter(SAFFL == "Y") %>%
  distinct(trt = .data[[dv$trtvar]], trtn = .data[[dv$trtnvar]]) %>%
  arrange(trtn) %>% pull(trt)

## post-baseline QTcF analysis records
eg <- adam$adeg %>%
  filter(SAFFL == "Y", ANL01FL == "Y", PARAMCD == "QTCF", ONTRTFL == "Y") %>%
  mutate(trt = .data[[dv$trtvar]])

## per-participant worst (max) post-baseline absolute value and max change ---------
worst <- eg %>%
  group_by(USUBJID, trt) %>%
  summarise(max_aval = suppressWarnings(max(AVAL, na.rm = TRUE)),
            max_chg  = suppressWarnings(max(CHG,  na.rm = TRUE)),
            .groups  = "drop") %>%
  mutate(max_aval = if_else(is.infinite(max_aval), NA_real_, max_aval),
         max_chg  = if_else(is.infinite(max_chg),  NA_real_, max_chg))

## category membership flags (highest threshold crossed is captured by each cut)
flags <- worst %>%
  transmute(USUBJID, trt,
            a450 = !is.na(max_aval) & max_aval > 450,
            a480 = !is.na(max_aval) & max_aval > 480,
            a500 = !is.na(max_aval) & max_aval > 500,
            c30  = !is.na(max_chg)  & max_chg  > 30,
            c60  = !is.na(max_chg)  & max_chg  > 60)

## long: one record per (participant, satisfied category) -> distinct-participant count
cat_levels <- c("QTcF > 450 ms","QTcF > 480 ms","QTcF > 500 ms",
                "Change > 30 ms","Change > 60 ms")
long <- flags %>%
  pivot_longer(c(a450,a480,a500,c30,c60), names_to = "key", values_to = "hit") %>%
  filter(hit) %>%
  mutate(cat = recode(key, a450 = cat_levels[1], a480 = cat_levels[2],
                            a500 = cat_levels[3], c30  = cat_levels[4],
                            c60  = cat_levels[5]))

with_total <- function(df) bind_rows(df, mutate(df, trt = "Total"))

## n (%) distinct participants per cohort x category; denominator = cohort N from bign()
cnt <- with_total(long) %>%
  group_by(trt, cat) %>%
  summarise(n = n_distinct(USUBJID), .groups = "drop") %>%
  left_join(denom, by = c("trt" = "trt")) %>%
  mutate(disp = n_pct(n, N),
         cat  = factor(cat, levels = cat_levels))

## ensure all categories appear per cohort (zero-fill absent combinations)
grid <- tidyr::crossing(trt = unique(denom$trt), cat = factor(cat_levels, levels = cat_levels))
tab <- grid %>%
  left_join(cnt %>% select(trt, cat, disp, n), by = c("trt","cat")) %>%
  left_join(denom, by = c("trt" = "trt")) %>%
  mutate(disp = coalesce(disp, n_pct(0L, N)),
         trt  = factor(trt, levels = c(dose_order, "Total"))) %>%
  select(trt, cat, disp) %>%
  pivot_wider(names_from = trt, values_from = disp) %>%
  arrange(cat)

ttl <- tfl_titles(num = "14.3.5.2", type = "Table",
   text = "QTcF - Categorical Outliers (Absolute Value and Change from Baseline)",
   pop  = "Safety Population",
   foot = "Columns are ascending SAD dose cohorts (placebo pooled first). QTcF = Fridericia-corrected QT. Categories per ICH E14; participant counted once per category on worst on-treatment value. Percentages based on cohort N in the Safety Population.")

lyt <- basic_table(title = ttl$titles[3], main_footer = ttl$footnotes) %>%
  analyze("cat", afun = function(x) in_rows(.list = as.list(x)))
# tbl <- build_table(lyt, tab)   ## or gt::gt(tab)
print(tab)
