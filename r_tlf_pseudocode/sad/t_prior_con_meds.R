################################################################################
# TABLE     : t_prior_con_meds  (Single Ascending Dose)
# TITLE     : Prior and Concomitant Medications by Drug Class and Dose Cohort
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADCM  (WHODrug-coded medications; ATC class + preferred name)
# NOTE      : PSEUDOCODE. Two sections (Prior, Concomitant) via ADCM timing
#             flags. Participants with >=1 medication = distinct USUBJID
#             (NOT med rows). % denominator = Safety N per dose cohort from
#             bign(). SAD = parallel dose cohorts; column = DOSE LEVEL (TRT01A),
#             placebo pooled. Single dose -> no period/sequence split.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SAD")                       # -> trtvar = TRT01A (dose level), trtnvar = TRT01AN

## column denominators (N=) per dose cohort + Total from ADSL
adsl  <- adam$adsl %>%
  filter(SAFFL == "Y") %>%
  mutate(dose_col = if_else(toupper(.data[[dv$trtvar]]) == "PLACEBO" | .data[[dv$trtnvar]] == 0,
                            "Placebo", .data[[dv$trtvar]]))
denom <- adsl %>%
  group_by(trt = dose_col) %>%
  summarise(N = n_distinct(USUBJID), .groups = "drop") %>%
  bind_rows(tibble(trt = "Total", N = n_distinct(adsl$USUBJID)))

## ADCM with timing flags: PREFL = prior (started before first dose),
## ONTRTFL = concomitant (taken during treatment). Both can be "Y".
cm <- adam$adcm %>%
  filter(SAFFL == "Y") %>%
  mutate(dose_col = if_else(toupper(.data[[dv$trtvar]]) == "PLACEBO" | .data[[dv$trtnvar]] == 0,
                            "Placebo", .data[[dv$trtvar]]))

## --- helper: distinct-participant n (%) by ATC class then preferred name ------
## counts DISTINCT participants per cell; % vs Safety N per cohort + Total. Order
## ATC class by overall participant frequency desc; meds within class desc.
cm_section <- function(df, section_label) {
  if (nrow(df) == 0) return(tibble())
  ## "Any medication" overall row (distinct participants)
  any_row <- {
    per <- df %>% group_by(trt = dose_col) %>%
      summarise(n = n_distinct(USUBJID), .groups = "drop")
    bind_rows(per, tibble(trt = "Total", n = n_distinct(df$USUBJID))) %>%
      right_join(denom, by = "trt") %>%
      mutate(n = coalesce(n, 0L), value = sprintf("%d (%.1f%%)", n, 100*n/N),
             characteristic = paste0(section_label, ": any medication"),
             ord = 0, level = 1)
  } %>% select(trt, characteristic, ord, level, value)

  ## ATC class ordering by overall distinct-participant frequency
  cls_order <- df %>% group_by(CMCLAS) %>%
    summarise(nn = n_distinct(USUBJID), .groups = "drop") %>%
    arrange(desc(nn)) %>% mutate(cord = row_number())

  rows <- purrr::pmap_dfr(cls_order, function(CMCLAS, nn, cord) {
    sub <- df %>% filter(CMCLAS == !!CMCLAS)
    ## class header row (distinct participants in class)
    hdr_per <- sub %>% group_by(trt = dose_col) %>%
      summarise(n = n_distinct(USUBJID), .groups = "drop")
    hdr <- bind_rows(hdr_per, tibble(trt = "Total", n = n_distinct(sub$USUBJID))) %>%
      right_join(denom, by = "trt") %>%
      mutate(n = coalesce(n, 0L), value = sprintf("%d (%.1f%%)", n, 100*n/N),
             characteristic = CMCLAS, ord = cord, level = 2) %>%
      select(trt, characteristic, ord, level, value)
    ## preferred-name rows within class (distinct participants), freq desc
    pt_order <- sub %>% group_by(CMDECOD) %>%
      summarise(nn = n_distinct(USUBJID), .groups = "drop") %>%
      arrange(desc(nn)) %>% mutate(pord = row_number())
    pts <- purrr::pmap_dfr(pt_order, function(CMDECOD, nn, pord) {
      s2 <- sub %>% filter(CMDECOD == !!CMDECOD)
      p  <- s2 %>% group_by(trt = dose_col) %>%
        summarise(n = n_distinct(USUBJID), .groups = "drop")
      bind_rows(p, tibble(trt = "Total", n = n_distinct(s2$USUBJID))) %>%
        right_join(denom, by = "trt") %>%
        mutate(n = coalesce(n, 0L), value = sprintf("%d (%.1f%%)", n, 100*n/N),
               characteristic = paste0("  ", CMDECOD),
               ord = cord + pord/100, level = 3) %>%
        select(trt, characteristic, ord, level, value)
    })
    bind_rows(hdr, pts)
  })
  bind_rows(any_row, rows) %>% mutate(section = section_label)
}

## --- Prior and Concomitant sections ---------------------------------------
prior <- cm_section(cm %>% filter(PREFL   == "Y"), "Prior")
conmed<- cm_section(cm %>% filter(ONTRTFL == "Y"), "Concomitant")

## --- stack sections (rows) x dose-cohort columns, render -------------------
## Ordered factor so Prior precedes Concomitant (matches the SAS secord=1/2),
## NOT alphabetical (which would put Concomitant first).
tab <- bind_rows(prior, conmed) %>%
  mutate(section = factor(section, levels = c("Prior", "Concomitant"))) %>%
  pivot_wider(names_from = trt, values_from = value, values_fill = "0") %>%
  arrange(section, ord) %>% select(-ord, -level)

ttl <- tfl_titles(num = "14.1.6", type = "Table",
   text = "Prior and Concomitant Medications by Drug Class and Dose Cohort",
   pop  = "Safety Population",
   foot = "SAD: columns = ascending dose cohorts (TRT01A) with placebo pooled. Participants counted once per class / medication (distinct USUBJID). Percentages based on Safety Population N per cohort. WHODrug Global Bxx coding; ATC class = CMCLAS.")

lyt <- basic_table(title = ttl$titles[3], main_footer = ttl$footnotes) %>%
  split_rows_by("section", page_by = TRUE) %>%
  split_rows_by("characteristic", page_by = FALSE) %>%
  analyze("value", afun = function(x) in_rows(.list = as.list(x)))
# tbl <- build_table(lyt, tab)   ## or gt::gt(tab)
print(tab)
