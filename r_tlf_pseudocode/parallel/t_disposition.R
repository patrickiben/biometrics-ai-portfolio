################################################################################
# TABLE     : t_disposition  (Parallel-group)
# TITLE     : Participant Disposition
# POPULATION: All Enrolled Participants (ENRLFL == "Y")
# INPUT     : ADSL
# NOTE      : PSEUDOCODE. Participant-level (one row per USUBJID). Columns =
#             treatment arms (TRT01A) + Total. n (%) for each disposition
#             category; % denominator = enrolled N per arm. Matches the SAS twin
#             (enrolled frame; leading "Participants enrolled" row; Discontinued
#             via DCSFL). Parallel-group: one treatment per participant.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("PARALLEL")                 # -> trtvar = TRT01A, trtnvar = TRT01AN

## one row per participant; disposition is reported on the enrolled frame
adsl <- adam$adsl %>% filter(ENRLFL == "Y")    # enrolled = disposition denominator

## --- column denominators (N=) per arm + Total -----------------------------
## enrolled N drives the % for every disposition row (participant-level)
denom <- adsl %>%
  group_by(trt = .data[[dv$trtvar]]) %>%
  summarise(N = n_distinct(USUBJID), .groups = "drop") %>%
  bind_rows(tibble(trt = "Total", N = n_distinct(adsl$USUBJID)))

## --- helper: a single n (%) disposition row across arms + Total -----------
disp_row <- function(df, label, ord) {
  per <- df %>%
    group_by(trt = .data[[dv$trtvar]]) %>%
    summarise(n = n_distinct(USUBJID), .groups = "drop")
  tot <- tibble(trt = "Total", n = n_distinct(df$USUBJID))
  bind_rows(per, tot) %>%
    right_join(denom, by = "trt") %>%                 # keep arms with 0 in this row
    mutate(n = coalesce(n, 0L),
           value = sprintf("%d (%.1f%%)", n, 100 * n / N),
           characteristic = label, ord = ord) %>%
    select(trt, characteristic, ord, value)
}

## --- count-only row (denominators themselves; no percent) -----------------
count_row <- function(df, label, ord) {
  per <- df %>% group_by(trt = .data[[dv$trtvar]]) %>%
    summarise(n = n_distinct(USUBJID), .groups = "drop")
  bind_rows(per, tibble(trt = "Total", n = n_distinct(df$USUBJID))) %>%
    transmute(trt, characteristic = label, ord, value = as.character(n))
}

## --- disposition categories (parallel-group, ADSL flags) ------------------
## Standard ADSL disposition fields: ENRLFL, RANDFL, SAFFL, PKFL, COMPLFL,
## DCSFL, DCSREAS. Discontinued = DCSFL=='Y' (matches SAS twin).
tab <- bind_rows(
  count_row(adsl,                                              "Participants enrolled",              1),
  disp_row (adsl %>% filter(RANDFL  == "Y"),                   "Participants randomized",            2),
  disp_row (adsl %>% filter(SAFFL   == "Y"),                   "Participants treated (Safety Pop)",  3),
  disp_row (adsl %>% filter(PKFL    == "Y"),                   "Participants in PK Population",       4),
  disp_row (adsl %>% filter(COMPLFL == "Y"),                   "Completed study",                    5),
  disp_row (adsl %>% filter(DCSFL   == "Y"),                   "Discontinued study",                 6),
  ## discontinuation reasons (DCSREAS) — data-driven sub-rows under "Discontinued";
  ## one indented row per reason present, mirroring the SAS catfreq(DCSREAS) block.
  {
    dc <- adsl %>% filter(DCSFL == "Y")
    reasons <- dc %>% distinct(DCSREAS) %>% arrange(DCSREAS) %>% pull(DCSREAS)
    purrr::imap_dfr(
      setNames(reasons, reasons),
      function(reason, label)
        disp_row(dc %>% filter(DCSREAS == reason),
                 paste0("  ", label), 6 + match(label, reasons) / 100))
  })

## --- stack rows x treatment columns, render --------------------------------
out <- tab %>%
  pivot_wider(names_from = trt, values_from = value, values_fill = "0") %>%
  arrange(ord) %>% select(-ord)

ttl <- tfl_titles(num = "14.1.1", type = "Table",
   text = "Participant Disposition",
   pop  = "All Enrolled Participants",
   foot = "Percentages based on the number of enrolled participants per treatment arm. Discontinued = DCSFL='Y'; reasons from ADSL DCSREAS.")

## rtables layout: characteristic rows x arm columns
lyt <- basic_table(title = ttl$titles[3], main_footer = ttl$footnotes) %>%
  split_rows_by("characteristic", page_by = FALSE) %>%
  analyze("value", afun = function(x) in_rows(.list = as.list(x)))
# tbl <- build_table(lyt, tab)   ## or gt::gt(out)
print(out)
