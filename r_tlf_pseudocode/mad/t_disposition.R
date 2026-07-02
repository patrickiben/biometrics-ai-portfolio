################################################################################
# TABLE     : t_disposition  (Multiple Ascending Dose)
# TITLE     : Participant Disposition
# POPULATION: All Enrolled Participants (ENRLFL == "Y"); counts also vs Safety / PK Pops
# INPUT     : ADSL
# NOTE      : PSEUDOCODE. Participant-level (one row per USUBJID). MAD = parallel
#             dose cohorts with REPEATED dosing; the column variable is the DOSE
#             LEVEL (TRT01A), with placebo typically pooled across cohorts into
#             one "Placebo" column. One treatment per participant -> NO period/
#             sequence structure at the participant level (dosing-DAY structure lives
#             on ADEX/ADPC, not here). n (%) per disposition category;
#             % denominator = enrolled N per dose cohort + Total.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("MAD")                       # -> trtvar = TRT01A (dose level), trtnvar = TRT01AN

## one row per participant; disposition is reported on the ENROLLED frame
adsl <- adam$adsl %>%
  filter(ENRLFL == "Y") %>%
  ## MAD convention: pool placebo across all ascending cohorts into one column,
  ## keep active arms at their ascending dose level (TRT01A). TRT01AN orders cols.
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

## --- count-only row (denominators themselves; no percent) -----------------
count_row <- function(df, label, ord) {
  per <- df %>% group_by(trt = dose_col) %>%
    summarise(n = n_distinct(USUBJID), .groups = "drop")
  bind_rows(per, tibble(trt = "Total", n = n_distinct(df$USUBJID))) %>%
    transmute(trt, characteristic = label, ord, value = as.character(n))
}

## --- disposition categories (MAD cohorts, ADSL flags) ---------------------
## Standard ADSL disposition fields: ENRLFL, RANDFL, SAFFL, COMPDOSF, PKFL,
## PKSSFL, COMPLFL, DCSFL, DCSREAS. MAD-relevant nuance: participants must
## complete the full multi-day regimen (COMPDOSF) and the steady-state PK day
## (PKSSFL) to support steady-state/Rac PK -> these milestones are shown
## explicitly. Discontinued uses the ADaM DCSFL flag (matching the SAS twin).
tab <- bind_rows(
  count_row(adsl,                                  "Participants enrolled",                1),
  disp_row (adsl %>% filter(RANDFL   == "Y"),      "Participants randomized",              2),
  disp_row (adsl %>% filter(SAFFL    == "Y"),      "Received >= 1 dose (Safety Pop)",      3),
  disp_row (adsl %>% filter(COMPDOSF == "Y"),      "Completed full dosing regimen",        4),
  disp_row (adsl %>% filter(PKFL     == "Y"),      "Participants in PK Population",         5),
  disp_row (adsl %>% filter(PKSSFL   == "Y"),      "Participants in PK Steady-State Pop",   6),
  disp_row (adsl %>% filter(COMPLFL  == "Y"),      "Completed study",                      7),
  disp_row (adsl %>% filter(DCSFL    == "Y"),      "Discontinued study",                   8),
  ## discontinuation reasons (DCSREAS) — subset to discontinued participants (DCSFL) ----
  {
    dc <- adsl %>% filter(DCSFL == "Y")
    purrr::imap_dfr(
      c("Adverse Event"            = "ADVERSE EVENT",
        "Withdrawal by Participant"    = "WITHDRAWAL BY PARTICIPANT",
        "Lost to Follow-up"        = "LOST TO FOLLOW-UP",
        "Protocol Deviation"       = "PROTOCOL DEVIATION",
        "Physician Decision"       = "PHYSICIAN DECISION",
        "Death"                    = "DEATH",
        "Other"                    = "OTHER"),
      function(reason, label)
        disp_row(dc %>% filter(toupper(DCSREAS) == reason),
                 paste0("  ", label), 8 + which(label == c(
                   "Adverse Event","Withdrawal by Participant","Lost to Follow-up",
                   "Protocol Deviation","Physician Decision","Death","Other")) / 10))
  })

## --- stack rows x dose-cohort columns, render ------------------------------
## Column order: ascending dose then Placebo/Total handled at render time via
## dose_ord (place Placebo first or last per SAP); Total always last.
out <- tab %>%
  pivot_wider(names_from = trt, values_from = value, values_fill = "0") %>%
  arrange(ord) %>% select(-ord)

ttl <- tfl_titles(num = "14.1.1", type = "Table",
   text = "Participant Disposition",
   pop  = "All Enrolled Participants",
   foot = "MAD: columns = ascending dose cohorts (TRT01A) with placebo pooled; repeated dosing. Completed dosing regimen = COMPDOSF; PK steady-state population = PKSSFL. Percentages based on enrolled participants per cohort. Discontinued = DCSFL; reasons from ADSL DCSREAS.")

## rtables layout: characteristic rows x dose-cohort columns
lyt <- basic_table(title = ttl$titles[3], main_footer = ttl$footnotes) %>%
  split_rows_by("characteristic", page_by = FALSE) %>%
  analyze("value", afun = function(x) in_rows(.list = as.list(x)))
# tbl <- build_table(lyt, tab)   ## or gt::gt(out)
print(out)
