################################################################################
# TABLE     : t_protocol_deviations  (Multiple Ascending Dose)
# TITLE     : Important Protocol Deviations
# POPULATION: All Enrolled Participants (ENRLFL == "Y")
# INPUT     : ADDV  (protocol deviation analysis dataset)
# NOTE      : PSEUDOCODE. Participants with >=1 deviation = distinct USUBJID
#             (NOT deviation rows). % denominator = enrolled N per cohort from
#             bign(). MAD = parallel dose cohorts; columns = DOSE LEVEL (TRT01A)
#             with placebo pooled + Total. Row hierarchy (3 levels, matches the
#             SAS twin): Any important deviation -> deviation CATEGORY (DVCAT) ->
#             indented TERM (DVDECOD). Participant-level; no period/sequence
#             split (dosing-day structure lives on ADEX/ADPC, not here).
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("MAD")                       # -> trtvar = TRT01A (dose level), trtnvar = TRT01AN

## ADSL drives the column denominators (enrolled N per cohort); pool placebo
adsl <- adam$adsl %>%
  filter(ENRLFL == "Y") %>%
  mutate(dose_col = if_else(toupper(TRT01A) == "PLACEBO" | TRT01AN == 0,
                            "Placebo", .data[[dv$trtvar]]))
denom <- bign(adsl %>% mutate(.dc = dose_col), trtvar = ".dc", popfl = "ENRLFL")

## protocol deviations; carry dose cohort + important-deviation flag from ADDV
## (filter on IMPDVFL only, as the SAS twin does; ADDV rows are for enrolled
##  participants, and the enrolled-N denominator already comes from ADSL/bign)
pd <- adam$addv %>%
  filter(toupper(IMPDVFL) == "Y") %>%                    # important deviations only (IMPDVFL)
  mutate(dose_col = if_else(toupper(.data[[dv$trtvar]]) == "PLACEBO" | .data[[dv$trtnvar]] == 0,
                            "Placebo", .data[[dv$trtvar]]))

## --- helper: participants with >=1 deviation in a subset -> n (%) row ---------
## counts DISTINCT participants, % vs population N per cohort + Total.
## indent = 0 (Any) | 1 (category) | 2 (term); term_rank orders rows within a
## category block (0 = the category row itself, >=1 = its terms).
pd_row <- function(df, label, cat_rank, indent = 0L, term_rank = 0L) {
  per <- df %>% group_by(trt = dose_col) %>%
    summarise(n = n_distinct(USUBJID), .groups = "drop")
  bind_rows(per, tibble(trt = "Total", n = n_distinct(df$USUBJID))) %>%
    right_join(denom, by = "trt") %>%
    mutate(n = coalesce(n, 0L),
           value = sprintf("%d (%.1f%%)", n, 100 * n / N),
           characteristic = paste0(strrep("  ", indent), label),
           cat_rank = cat_rank, term_rank = term_rank) %>%
    select(trt, characteristic, cat_rank, term_rank, value)
}

## --- overall "any important deviation" row (distinct participants) ------------
## level 0; sorts first (cat_rank = 0).
any_pd <- pd_row(pd, "Participants with any important deviation", 0)

## --- by deviation category (DVCAT) — distinct participants per category -------
## Order categories by overall participant frequency (desc), matching the SAS
## twin (category by Total-column participant count desc). cat_rank drives the
## category block order so each category's terms nest directly beneath it.
cat_order <- pd %>% group_by(DVCAT) %>%
  summarise(catn = n_distinct(USUBJID), .groups = "drop") %>%
  arrange(desc(catn)) %>% mutate(cat_rank = row_number())

## category rows: level 1; ord = cat_rank, term_rank 0 so category precedes terms
by_cat <- purrr::pmap_dfr(cat_order, function(DVCAT, catn, cat_rank)
  pd_row(pd %>% filter(DVCAT == !!DVCAT), DVCAT, cat_rank, indent = 1L))

## --- by category x term (DVCAT x DVDECOD) — distinct participants -------------
## level 2; term within category by participant count desc (matches SAS twin).
## term_rank starts at 1 so the parent category row (term_rank 0) sorts first.
term_order <- pd %>% group_by(DVCAT, DVDECOD) %>%
  summarise(tmn = n_distinct(USUBJID), .groups = "drop") %>%
  inner_join(cat_order %>% select(DVCAT, cat_rank), by = "DVCAT") %>%
  arrange(cat_rank, desc(tmn)) %>%
  group_by(DVCAT) %>% mutate(term_rank = row_number()) %>% ungroup()

by_term <- purrr::pmap_dfr(term_order, function(DVCAT, DVDECOD, tmn, cat_rank, term_rank)
  pd_row(pd %>% filter(DVCAT == !!DVCAT, DVDECOD == !!DVDECOD),
         DVDECOD, cat_rank, indent = 2L, term_rank = term_rank))

## --- stack rows x dose-cohort columns, render ------------------------------
## sort: category block (cat_rank), then category row before its terms (term_rank),
## with the overall "Any" row first (cat_rank 0).
tab <- bind_rows(any_pd, by_cat, by_term) %>%
  pivot_wider(names_from = trt, values_from = value, values_fill = "0") %>%
  arrange(cat_rank, term_rank) %>% select(-cat_rank, -term_rank)

ttl <- tfl_titles(num = "14.1.5", type = "Table",
   text = "Important Protocol Deviations",
   pop  = "All Enrolled Participants",
   foot = "MAD: columns = ascending dose cohorts (TRT01A) with placebo pooled, ordered by ascending dose. Row hierarchy: any important deviation, then category (DVCAT), then indented term (DVDECOD). A participant with multiple deviations is counted once at each level (distinct USUBJID). Percentages based on enrolled N per cohort. Important deviations per ADDV IMPDVFL.")

lyt <- basic_table(title = ttl$titles[3], main_footer = ttl$footnotes) %>%
  split_rows_by("characteristic", page_by = FALSE) %>%
  analyze("value", afun = function(x) in_rows(.list = as.list(x)))
# tbl <- build_table(lyt, tab)   ## or gt::gt(tab)
print(tab)
