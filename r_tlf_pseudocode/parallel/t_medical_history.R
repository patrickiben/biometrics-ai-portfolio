################################################################################
# TABLE     : t_medical_history  (Parallel-group)
# TITLE     : Medical History by System Organ Class and Preferred Term
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADMH  (MedDRA-coded medical/surgical history)
# NOTE      : PSEUDOCODE. Participant-level: participants with >=1 condition = distinct
#             USUBJID (NOT history rows). % denominator = Safety N per arm from
#             bign(). SOC ordered by overall participant frequency desc, PT within
#             SOC desc. Columns = treatment arms (TRT01A) + Total. Parallel-
#             group: one treatment per participant, no period/sequence split.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("PARALLEL")                 # -> trtvar = TRT01A, trtnvar = TRT01AN

## column denominators (N=) per arm + Total from ADSL
adsl  <- adam$adsl %>% filter(SAFFL == "Y")
denom <- bign(adsl, trtvar = dv$trtvar, popfl = "SAFFL")

## ongoing/relevant medical history; MHOCCUR=="Y" present conditions
mh <- adam$admh %>% filter(SAFFL == "Y", toupper(MHOCCUR) == "Y" | is.na(MHOCCUR))

## --- distinct-participant n (%) row helper (vs Safety N per arm + Total) ------
mh_row <- function(df, label, ord, indent = FALSE) {
  per <- df %>% group_by(trt = .data[[dv$trtvar]]) %>%
    summarise(n = n_distinct(USUBJID), .groups = "drop")
  bind_rows(per, tibble(trt = "Total", n = n_distinct(df$USUBJID))) %>%
    right_join(denom, by = "trt") %>%
    mutate(n = coalesce(n, 0L), value = sprintf("%d (%.1f%%)", n, 100*n/N),
           characteristic = if (indent) paste0("  ", label) else label,
           ord = ord) %>%
    select(trt, characteristic, ord, value)
}

## --- "any medical history" overall row (distinct participants) ----------------
any_mh <- mh_row(mh, "Participants with any medical history", 0)

## --- SOC ordered by overall distinct-participant frequency desc ---------------
soc_order <- mh %>% group_by(MHBODSYS) %>%
  summarise(nn = n_distinct(USUBJID), .groups = "drop") %>%
  arrange(desc(nn)) %>% mutate(sord = row_number())

bysoc <- purrr::pmap_dfr(soc_order, function(MHBODSYS, nn, sord) {
  sub <- mh %>% filter(MHBODSYS == !!MHBODSYS)
  hdr <- mh_row(sub, MHBODSYS, sord, indent = FALSE)        # SOC header (distinct subj)
  ## PT within SOC, freq desc
  pt_order <- sub %>% group_by(MHDECOD) %>%
    summarise(nn = n_distinct(USUBJID), .groups = "drop") %>%
    arrange(desc(nn)) %>% mutate(pord = row_number())
  pts <- purrr::pmap_dfr(pt_order, function(MHDECOD, nn, pord)
    mh_row(sub %>% filter(MHDECOD == !!MHDECOD), MHDECOD,
           sord + pord/100, indent = TRUE))
  bind_rows(hdr, pts)
})

## --- stack rows x treatment columns, render --------------------------------
tab <- bind_rows(any_mh, bysoc) %>%
  pivot_wider(names_from = trt, values_from = value, values_fill = "0") %>%
  arrange(ord) %>% select(-ord)

ttl <- tfl_titles(num = "14.1.7", type = "Table",
   text = "Medical History by System Organ Class and Preferred Term",
   pop  = "Safety Population",
   foot = "Participants counted once per SOC / PT (distinct USUBJID). Percentages based on Safety Population N per arm. MedDRA v27.0; SOC ordered by overall frequency.")

lyt <- basic_table(title = ttl$titles[3], main_footer = ttl$footnotes) %>%
  split_rows_by("characteristic", page_by = FALSE) %>%
  analyze("value", afun = function(x) in_rows(.list = as.list(x)))
# tbl <- build_table(lyt, tab)   ## or gt::gt(tab)
print(tab)
