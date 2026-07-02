################################################################################
# TABLE     : t_ae_overview  (Single Ascending Dose)
# TITLE     : Overview of Treatment-Emergent Adverse Events by Dose Level
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADAE (TRTEMFL == "Y")
# NOTE      : PSEUDOCODE. Each row = participants with >=1 event of a category
#             (n_distinct USUBJID), NOT event rows. n (%) per dose level;
#             % denominator = SAFFL N per dose level from bign(). SAD: parallel
#             cohorts -> column = dose level (dv$trtvar = TRT01A, one single dose
#             per participant). Columns are ORDERED BY ASCENDING DOSE (TRT01AN);
#             placebo is commonly POOLED across cohorts into one column. Single
#             dose -> no accumulation. Categories are non-mutually-exclusive.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SAD")                       # trtvar = TRT01A, trtnvar = TRT01AN

## --- column denominators: SAFFL N per dose level (+ Total) ------------------
## SAD column = single dose received; one treatment per participant -> ADSL is the
## correct participant-level denominator source (no period structure in SAD).
denom <- bign(adam$adsl, trtvar = dv$trtvar, popfl = "SAFFL")

## --- ascending-dose column order (+ optional placebo pooling) ---------------
## Order columns by numeric dose TRT01AN; pool all placebo cohorts to "Placebo".
## TRT01AN is carried through so the report can sort dose columns low->high and
## seat any pooled-placebo column first.
dose_key <- adam$adsl %>% filter(SAFFL == "Y") %>%
  distinct(trt = .data[[dv$trtvar]], dosen = .data[[dv$trtnvar]]) %>%
  mutate(is_pbo = grepl("PLACEBO|PBO", toupper(trt)),
         dose_ord = if_else(is_pbo, -Inf, dosen))      # placebo first, then ascending

## --- treatment-emergent AE analysis set ------------------------------------
adae <- adam$adae %>% filter(SAFFL == "Y", TRTEMFL == "Y")

## "related" set, consistent & case-safe (house rule)
rel_set <- c("RELATED","POSSIBLE","PROBABLE","DEFINITE")

## --- one summary row = distinct participants meeting a category predicate -------
## Each helper counts distinct participants per dose level AND a Total column
## (distinct across all dose levels) under a dplyr filter expr.
ov_row <- function(df, where, label, ord) {
  sub <- df %>% filter(!!where)
  per <- sub %>% group_by(trt = .data[[dv$trtvar]]) %>%
    summarise(nsubj = n_distinct(USUBJID), .groups = "drop")
  tot <- tibble(trt = "Total", nsubj = n_distinct(sub$USUBJID))
  bind_rows(per, tot) %>% mutate(category = label, ord = ord)
}

## --- ordered category stack ------------------------------------------------
## CANONICAL category order (identical to the SAS twin): any / drug-related /
## serious / drug-related serious / severe / disc / dose modification / death.
## Severity test = AESEVN >= 3 (severe or worse) in BOTH languages; seriousness
## AESER; fatal AESDTH or fatal outcome; discontinuation AEACN == "DRUG WITHDRAWN".
overview <- bind_rows(
  ov_row(adae, quote(TRUE),                                       "Participants with any TEAE",                   1),
  ov_row(adae, quote(toupper(AREL) %in% rel_set),                "Participants with drug-related TEAE",          2),
  ov_row(adae, quote(AESER == "Y"),                              "Participants with serious TEAE",               3),
  ov_row(adae, quote(AESER == "Y" & toupper(AREL) %in% rel_set), "Participants with drug-related serious TEAE",  4),
  ov_row(adae, quote(AESEVN >= 3),                               "Participants with severe TEAE",                5),
  ov_row(adae, quote(AEACN == "DRUG WITHDRAWN"),                 "Participants with TEAE leading to discontinuation", 6),
  ov_row(adae, quote(AEACN %in% c("DOSE REDUCED","DRUG INTERRUPTED")), "Participants with TEAE leading to dose modification", 7),
  ov_row(adae, quote(AESDTH == "Y" | toupper(AEOUT) == "FATAL"), "Participants with TEAE leading to death",       8)
)

## --- attach denominators -> n (%), with explicit 0 (0.0%) for empty cells --
## Include the Total column (same as the SAS twin).
doses <- denom %>% pull(trt)            # dose levels + Total
grid  <- tidyr::crossing(category = unique(overview$category), trt = doses) %>%
  left_join(distinct(overview, category, ord), by = "category")

rep <- grid %>%
  left_join(overview, by = c("category","trt","ord")) %>%
  mutate(nsubj = tidyr::replace_na(nsubj, 0L)) %>%
  left_join(denom, by = "trt") %>%
  mutate(value = n_pct(nsubj, N)) %>%
  arrange(ord, trt) %>%
  select(category, ord, trt, value) %>%
  pivot_wider(names_from = trt, values_from = value) %>%
  arrange(ord) %>% select(-ord)
## NB: dose columns should be re-ordered low->high via dose_key$dose_ord at render.

ttl <- tfl_titles(
  num  = "14.3.1",
  type = "Table",
  text = "Overview of Treatment-Emergent Adverse Events by Dose Level",
  pop  = "Safety Population",
  foot = paste("SAD: each column = single ascending dose level (TRT01A), ordered",
               "low to high; placebo may be pooled across cohorts. TEAE =",
               "treatment-emergent AE (TRTEMFL=Y). A participant is counted once per",
               "category; categories are not mutually exclusive. Related = AREL in",
               "{RELATED, POSSIBLE, PROBABLE, DEFINITE}. % = participants in category /",
               "N in dose level. MedDRA v27.0."))

## --- rtables layout (SAD: split columns by dose level, ascending) ----------
# lyt <- basic_table(title = ttl$titles, main_footer = ttl$footnotes) %>%
#   split_cols_by(dv$trtvar) %>%               # order via dose_key (dose_ord)
#   analyze("value", afun = identity)
# tbl <- build_table(lyt, rep); tbl

print(rep)
