################################################################################
# TABLE     : t_protocol_deviations  (Parallel-group)
# TITLE     : Important Protocol Deviations
# POPULATION: All Enrolled Participants (ENRLFL == "Y")
# INPUT     : ADDV (protocol deviation domain) / ADSL for flags
# NOTE      : PSEUDOCODE. Participants with >=1 deviation = distinct USUBJID
#             (NOT deviation rows). % denominator = enrolled N per arm from
#             bign(). Columns = treatment arms (TRT01A) + Total. Category->Term
#             hierarchy (DVCAT->DVDECOD) matches the SAS twin. Parallel-group:
#             one treatment per participant; no period/sequence split.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("PARALLEL")                 # -> trtvar = TRT01A, trtnvar = TRT01AN

## ADSL drives the column denominators (enrolled N per arm)
adsl <- adam$adsl %>% filter(ENRLFL == "Y")
denom <- bign(adsl, trtvar = dv$trtvar, popfl = "ENRLFL")

## protocol deviations; carry treatment + important-deviation flag from ADDV
pd <- adam$addv %>%
  filter(toupper(IMPDVFL) == "Y")   # important deviations only (IMPDVFL)

## --- helper: participants with >=1 deviation in a subset -> n (%) row ---------
## counts DISTINCT participants, % vs population N per arm + Total
pd_row <- function(df, label, ord, indent = FALSE) {
  per <- df %>% group_by(trt = .data[[dv$trtvar]]) %>%
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
  arrange(desc(nn)) %>% mutate(ord = 1 + row_number() / 100)

by_cat <- purrr::pmap_dfr(cat_order, function(DVCAT, nn, ord)
  pd_row(pd %>% filter(DVCAT == !!DVCAT), DVCAT, ord, indent = TRUE))

## --- by category*term (DVCAT*DVDECOD) — distinct participants per term --------
## indented one level below its category, ordered within category by frequency.
term_order <- pd %>% group_by(DVCAT, DVDECOD) %>%
  summarise(nn = n_distinct(USUBJID), .groups = "drop") %>%
  left_join(cat_order %>% select(DVCAT, cat_ord = ord), by = "DVCAT") %>%
  arrange(cat_ord, desc(nn)) %>%
  group_by(DVCAT) %>% mutate(ord = cat_ord + row_number() / 10000) %>% ungroup()

by_term <- purrr::pmap_dfr(term_order, function(DVCAT, DVDECOD, nn, cat_ord, ord)
  pd_row(pd %>% filter(DVCAT == !!DVCAT, DVDECOD == !!DVDECOD),
         paste0("    ", DVDECOD), ord, indent = TRUE))

## --- stack rows x treatment columns, render --------------------------------
tab <- bind_rows(any_pd, by_cat, by_term) %>%
  pivot_wider(names_from = trt, values_from = value, values_fill = "0") %>%
  arrange(ord) %>% select(-ord)

ttl <- tfl_titles(num = "14.1.5", type = "Table",
   text = "Important Protocol Deviations",
   pop  = "All Enrolled Participants",
   foot = "A participant with multiple deviations is counted once at each level (distinct USUBJID). Percentages based on enrolled N per arm. Important deviations per ADDV IMPDVFL.")

lyt <- basic_table(title = ttl$titles[3], main_footer = ttl$footnotes) %>%
  split_rows_by("characteristic", page_by = FALSE) %>%
  analyze("value", afun = function(x) in_rows(.list = as.list(x)))
# tbl <- build_table(lyt, tab)   ## or gt::gt(tab)
print(tab)
