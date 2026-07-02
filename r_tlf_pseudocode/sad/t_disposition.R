################################################################################
# TABLE     : t_disposition  (Single Ascending Dose)
# TITLE     : Participant Disposition by Dose Cohort
# POPULATION: All Enrolled Participants
# INPUT     : ADSL
# NOTE      : PSEUDOCODE. Participant-level (one row per USUBJID). SAD = parallel
#             dose cohorts; the column variable is the DOSE LEVEL (TRT01A), with
#             placebo typically pooled across cohorts into one "Placebo" column.
#             Single dose -> one treatment per participant, NO period/sequence
#             structure. n (%) per disposition row (EVERY row, including enrolled
#             and randomized; enrolled = 100% of its own denominator), matching
#             the SAS %dispblk macro. % denominator = enrolled N per dose cohort
#             + Total. Discontinued = DCSFL == "Y" (matches the SAS twin).
#             PLACEBO-POOLING CONTRACT (must match the SAS twin): TRT01A may
#             already collapse all placebo cohorts into a single "Placebo" level
#             in ADaM. The in-code dose_col collapse below is IDEMPOTENT -- it is
#             the single documented pooling point and is a no-op when ADaM has
#             already pooled. Both languages therefore yield the same placebo
#             column and denominator. Columns ordered by dose_ord (ascending
#             dose; Placebo at 0), Total last -> matches SAS transpose id TRT01AN.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SAD")                       # -> trtvar = TRT01A (dose level), trtnvar = TRT01AN

## one row per participant; disposition is reported on the ENROLLED frame so
## screen-fails / enrolled-not-randomized attrition is visible (matches SAS)
adsl <- adam$adsl %>%
  filter(ENRLFL == "Y") %>%
  ## pool placebo across cohorts (IDEMPOTENT if ADaM already pooled into TRT01A);
  ## active arms keep their ascending dose level (TRT01A). dose_ord = TRT01AN
  ## orders the columns ascending (Placebo at 0). This is the single documented
  ## pooling point and is a no-op when ADaM has already pooled -> same column set
  ## and denominators as the SAS twin (which groups by raw TRT01A/TRT01AN).
  mutate(
    dose_col = if_else(toupper(TRT01A) == "PLACEBO" | TRT01AN == 0,
                       "Placebo", .data[[dv$trtvar]]),
    dose_ord = if_else(toupper(TRT01A) == "PLACEBO" | TRT01AN == 0,
                       0, .data[[dv$trtnvar]]))               # ascending order key

## --- column denominators (N=) per dose cohort + Total ---------------------
## enrolled N drives the % for every disposition row (participant-level)
denom <- adsl %>%
  group_by(trt = dose_col) %>%
  summarise(N = n_distinct(USUBJID), .groups = "drop") %>%
  bind_rows(tibble(trt = "Total", N = n_distinct(adsl$USUBJID)))

## --- helper: a single n (%) disposition row across cohorts + Total --------
disp_row <- function(df, label, ord) {
  per <- df %>%
    group_by(trt = dose_col) %>%
    summarise(n = n_distinct(USUBJID), .groups = "drop")
  tot <- tibble(trt = "Total", n = n_distinct(df$USUBJID))
  bind_rows(per, tot) %>%
    right_join(denom, by = "trt") %>%                 # keep cohorts with 0 in this row
    mutate(n = coalesce(n, 0L),
           value = sprintf("%d (%.1f%%)", n, 100 * n / N),
           characteristic = label, ord = ord) %>%
    select(trt, characteristic, ord, value)
}

## --- disposition categories (SAD cohorts, ADSL flags) ---------------------
## Standard ADSL disposition fields: ENRLFL, RANDFL, SAFFL, PKFL, COMPLFL, DCSFL,
## DCSREAS, EOSSTT. Discontinued = DCSFL == "Y" (matches the SAS twin).
## EVERY row is n (%) via disp_row() -- including enrolled (100% of its own
## enrolled denominator) and randomized -- to match the uniform SAS %dispblk.
tab <- bind_rows(
  disp_row (adsl,                                              "Participants enrolled",          1),
  disp_row (adsl %>% filter(RANDFL  == "Y"),                   "Participants randomized",        2),
  disp_row (adsl %>% filter(SAFFL   == "Y"),                   "Received single dose (Safety Population)", 3),
  disp_row (adsl %>% filter(PKFL    == "Y"),                   "Included in PK Population",       4),
  disp_row (adsl %>% filter(COMPLFL == "Y"),                   "Completed study",                5),
  disp_row (adsl %>% filter(DCSFL   == "Y"),                   "Discontinued study",             6),
  ## discontinuation reasons (DCSREAS), data-driven, subset to discontinued
  ## participants. Reasons are taken from the values that actually occur in
  ## DCSREAS (no hard-coded list), matching the SAS twin's %catfreq over DCSREAS.
  {
    dc <- adsl %>% filter(DCSFL == "Y")
    reasons <- dc %>%
      filter(!is.na(DCSREAS), DCSREAS != "") %>%
      distinct(DCSREAS) %>%
      arrange(DCSREAS) %>%
      pull(DCSREAS)
    purrr::imap_dfr(
      reasons,
      function(reason, i)
        disp_row(dc %>% filter(DCSREAS == reason),
                 paste0("  ", reason), 6 + i / 10))   # indent reasons under "Discontinued"
  })

## --- stack rows x dose-cohort columns, render ------------------------------
## Column order = ascending dose (dose_ord; Placebo at 0), Total last -> matches
## the SAS transpose `id TRT01AN` (Total carries trtn=9999, so it sorts last).
col_ord <- adsl %>% distinct(dose_col, dose_ord) %>% arrange(dose_ord) %>%
  pull(dose_col)
out <- tab %>%
  pivot_wider(names_from = trt, values_from = value, values_fill = "0") %>%
  arrange(ord) %>% select(-ord) %>%
  select(characteristic, any_of(col_ord), Total)

ttl <- tfl_titles(num = "14.1.1", type = "Table",
   text = "Participant Disposition by Dose Cohort",
   pop  = "All Enrolled Participants",
   foot = "SAD: columns = ascending dose cohorts (TRT01A) with placebo pooled. Percentages based on enrolled participants per cohort. Discontinued = DCSFL == \"Y\"; discontinuation reasons from ADSL DCSREAS.")

## rtables layout: characteristic rows x dose-cohort columns
lyt <- basic_table(title = ttl$titles[3], main_footer = ttl$footnotes) %>%
  split_rows_by("characteristic", page_by = FALSE) %>%
  analyze("value", afun = function(x) in_rows(.list = as.list(x)))
# tbl <- build_table(lyt, tab)   ## or gt::gt(out)
print(out)
