################################################################################
# TABLE     : t_ae_overview  (Parallel-group)
# TITLE     : Overview of Treatment-Emergent Adverse Events
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADAE (TRTEMFL == "Y")
# NOTE      : PSEUDOCODE. Each row = participants with >=1 event of a category
#             (n_distinct USUBJID), NOT event rows. n (%) per arm; % denominator
#             = SAFFL N per arm from bign(). Parallel: column = TRT01A (one
#             treatment per participant). Categories are non-mutually-exclusive
#             (a participant may appear in several rows).
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("PARALLEL")                  # trtvar = TRT01A, trtnvar = TRT01AN

## --- column denominators: SAFFL N per arm (+ Total) -------------------------
denom <- bign(adam$adsl, trtvar = dv$trtvar, popfl = "SAFFL")

## --- treatment-emergent AE analysis set ------------------------------------
adae <- adam$adae %>% filter(SAFFL == "Y", TRTEMFL == "Y")

## "related" set, consistent & case-safe (house rule)
rel_set <- c("RELATED","POSSIBLE","PROBABLE","DEFINITE")

## --- one summary row = distinct participants meeting a category predicate -------
## Each helper counts distinct participants per arm AND a Total column (distinct
## across all arms), matching the SAS twin's Total column.
ov_row <- function(df, where, label, ord) {
  sub <- df %>% filter(!!where)
  per <- sub %>% group_by(trt = .data[[dv$trtvar]]) %>%
    summarise(nsubj = n_distinct(USUBJID), .groups = "drop")
  bind_rows(per, tibble(trt = "Total", nsubj = n_distinct(sub$USUBJID))) %>%
    mutate(category = label, ord = ord)
}

## --- ordered category stack (order matches the SAS twin) -------------------
## Severity uses AESEVN (1=Mild,2=Moderate,3=Severe; severe = AESEVN>=3);
## seriousness AESER; fatal AESDTH; discontinuation AEACN == "DRUG WITHDRAWN".
overview <- bind_rows(
  ov_row(adae, quote(TRUE),                                       "Participants with any TEAE",                       1),
  ov_row(adae, quote(toupper(AREL) %in% rel_set),                "Participants with drug-related TEAE",              2),
  ov_row(adae, quote(AESER == "Y"),                              "Participants with serious TEAE",                   3),
  ov_row(adae, quote(AESER == "Y" & toupper(AREL) %in% rel_set), "Participants with drug-related serious TEAE",      4),
  ov_row(adae, quote(AESEVN >= 3),                               "Participants with severe TEAE",                    5),
  ov_row(adae, quote(AEACN == "DRUG WITHDRAWN"),                 "Participants with TEAE leading to discontinuation",6),
  ov_row(adae, quote(AEACN %in% c("DOSE REDUCED","DRUG INTERRUPTED")), "Participants with TEAE leading to dose modification", 7),
  ov_row(adae, quote(AESDTH == "Y" | toupper(AEOUT) == "FATAL"), "Participants with TEAE leading to death",          8)
)

## --- attach denominators -> n (%), with explicit 0 (0.0%) for empty cells --
## include the Total column so the layout matches the SAS twin.
arms <- denom %>% pull(trt)            # arms + Total
grid <- tidyr::crossing(category = unique(overview$category), trt = arms) %>%
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

ttl <- tfl_titles(
  num  = "14.3.1",
  type = "Table",
  text = "Overview of Treatment-Emergent Adverse Events",
  pop  = "Safety Population",
  foot = paste("TEAE = treatment-emergent AE (TRTEMFL=Y). A participant is counted",
               "once per category; categories are not mutually exclusive.",
               "Related = AREL in {RELATED, POSSIBLE, PROBABLE, DEFINITE}.",
               "% = participants in category / N in arm. MedDRA v27.0."))

## --- rtables layout (parallel: split columns by treatment) -----------------
# lyt <- basic_table(title = ttl$titles, main_footer = ttl$footnotes) %>%
#   split_cols_by(dv$trtvar) %>%
#   analyze("value", afun = identity)
# tbl <- build_table(lyt, rep); tbl

print(rep)
