################################################################################
# TABLE     : t_protocol_deviations  (Single Ascending Dose)
# TITLE     : Important Protocol Deviations by Category and Dose Cohort
# POPULATION: All Enrolled Participants (ENRLFL == "Y")
# INPUT     : ADDV  (protocol deviation domain) + ADSL flags
# NOTE      : PSEUDOCODE. Participants with >=1 deviation = distinct USUBJID
#             (NOT deviation rows). % denominator = enrolled N per dose cohort
#             from bign(). SAD = parallel dose cohorts; column = DOSE LEVEL
#             (TRT01A), placebo pooled. Single dose -> one treatment per participant,
#             NO period/sequence split. Important deviations per ADDV IMPDVFL
#             (strict; no is.na fallback) -- matches the SAS twin. Three-level row
#             hierarchy: Any important deviation -> DVCAT category -> indented
#             DVDECOD term (category ordered by overall participant count desc; term
#             within category desc), identical to the SAS twin's DVCAT*DVDECOD tier.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SAD")                       # -> trtvar = TRT01A (dose level), trtnvar = TRT01AN

## ADSL drives the column denominators (enrolled N per dose cohort)
adsl <- adam$adsl %>%
  filter(ENRLFL == "Y") %>%
  mutate(dose_col = if_else(toupper(.data[[dv$trtvar]]) == "PLACEBO" | .data[[dv$trtnvar]] == 0,
                            "Placebo", .data[[dv$trtvar]]))
denom <- adsl %>%
  group_by(trt = dose_col) %>%
  summarise(N = n_distinct(USUBJID), .groups = "drop") %>%
  bind_rows(tibble(trt = "Total", N = n_distinct(adsl$USUBJID)))

## protocol deviations; carry dose cohort + important-deviation flag from ADDV
pd <- adam$addv %>%
  filter(toupper(IMPDVFL) == "Y") %>%                       # strict important deviations (IMPDVFL)
  mutate(dose_col = if_else(toupper(.data[[dv$trtvar]]) == "PLACEBO" | .data[[dv$trtnvar]] == 0,
                            "Placebo", .data[[dv$trtvar]]))

## --- helper: participants with >=1 deviation in a subset -> n (%) row ---------
## counts DISTINCT participants, % vs population N per cohort + Total
pd_row <- function(df, label, ord, indent = FALSE) {
  per <- df %>% group_by(trt = dose_col) %>%
    summarise(n = n_distinct(USUBJID), .groups = "drop")
  bind_rows(per, tibble(trt = "Total", n = n_distinct(df$USUBJID))) %>%
    right_join(denom, by = "trt") %>%
    mutate(n = coalesce(n, 0L),
           value = sprintf("%d (%.1f%%)", n, 100 * n / N),
           characteristic = if (indent) paste0("  ", label) else label,
           ord = ord) %>%
    select(trt, characteristic, ord, value)
}

## --- overall "any important deviation" row (distinct participants) ------------
any_pd <- pd_row(pd, "Participants with >=1 important protocol deviation", 1)

## --- by deviation category (DVCAT) — distinct participants per category -------
## Order categories by overall participant frequency (desc) for readability.
cat_order <- pd %>% group_by(DVCAT) %>%
  summarise(nn = n_distinct(USUBJID), .groups = "drop") %>%
  arrange(desc(nn)) %>% mutate(cat_ord = row_number())

## --- by category*term (DVCAT*DVDECOD) — distinct participants per term --------
## Term within category ordered by overall participant frequency (desc), mirroring
## the SAS twin's DVCAT*DVDECOD tier (matches t_ae_by_soc_pt SOC->PT idiom).
term_order <- pd %>% group_by(DVCAT, DVDECOD) %>%
  summarise(tn = n_distinct(USUBJID), .groups = "drop")

## assemble Any -> Category (level 1) -> indented Term (level 2), each as n (%) per
## dose cohort. ord = category rank . term rank within category, so arrange() keeps
## every term directly beneath its parent category.
by_cat <- purrr::pmap_dfr(cat_order, function(DVCAT, nn, cat_ord) {
  this_cat <- DVCAT
  cat_row  <- pd_row(pd %>% filter(DVCAT == this_cat), this_cat,
                     cat_ord + 0 / 1000, indent = TRUE)
  terms    <- term_order %>% filter(DVCAT == this_cat) %>%
    arrange(desc(tn)) %>% mutate(term_rank = row_number())
  term_rows <- purrr::pmap_dfr(terms, function(DVCAT, DVDECOD, tn, term_rank)
    pd_row(pd %>% filter(DVCAT == this_cat, DVDECOD == !!DVDECOD),
           paste0("  ", DVDECOD), cat_ord + term_rank / 1000, indent = TRUE))
  bind_rows(cat_row, term_rows)
})

## --- stack rows x dose-cohort columns, render ------------------------------
tab <- bind_rows(any_pd %>% mutate(ord = 0), by_cat) %>%
  pivot_wider(names_from = trt, values_from = value, values_fill = "0") %>%
  arrange(ord) %>% select(-ord)

ttl <- tfl_titles(num = "14.1.5", type = "Table",
   text = "Important Protocol Deviations by Category and Dose Cohort",
   pop  = "All Enrolled Participants",
   foot = "SAD: columns = ascending dose cohorts (TRT01A) with placebo pooled. Participants counted once per category (distinct USUBJID). Percentages based on enrolled N per cohort. Important deviations per ADDV IMPDVFL.")

lyt <- basic_table(title = ttl$titles[3], main_footer = ttl$footnotes) %>%
  split_rows_by("characteristic", page_by = FALSE) %>%
  analyze("value", afun = function(x) in_rows(.list = as.list(x)))
# tbl <- build_table(lyt, tab)   ## or gt::gt(tab)
print(tab)
