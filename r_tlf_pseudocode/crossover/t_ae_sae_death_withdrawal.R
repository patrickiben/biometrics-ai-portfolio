################################################################################
# TABLE     : t_ae_sae_death_withdrawal  (Crossover - 2x2 or Williams)
# TITLE     : Serious Adverse Events, Deaths, and Adverse Events Leading to
#             Withdrawal by System Organ Class and Preferred Term
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADAE (TRTEMFL == "Y"); ADEX for per-treatment denominators
# NOTE      : PSEUDOCODE. Three stacked panels (SAE / Death / Withdrawal). Counts
#             = PARTICIPANTS (n_distinct USUBJID), NOT event rows. Columns =
#             treatment (TRTA), with AE attributed to the treatment in effect at
#             onset. % denominator = participants exposed to that treatment from ADEX
#             (period-bearing), NOT ADSL. SOC/PT ordered by participant freq desc
#             within each panel.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("CROSSOVER")                 # trtvar=TRTA, byperiod=APERIOD/APERIODC

## --- per-TREATMENT denominators from ADEX (participants dosed per TRTA) ----------
denom <- adam$adex %>%
  filter(SAFFL == "Y") %>%
  group_by(trt = .data[[dv$trtvar]]) %>%
  summarise(N = n_distinct(USUBJID), .groups = "drop") %>%
  bind_rows(tibble(trt = "Total",
                   N = n_distinct(adam$adex$USUBJID[adam$adex$SAFFL == "Y"])))

adae <- adam$adae %>% filter(SAFFL == "Y", TRTEMFL == "Y")

## --- generic panel builder: subset -> any/SOC/PT participant counts --------------
panel <- function(df, panel_label, panel_ord) {
  any_te <- bind_rows(
    df %>% group_by(trt = .data[[dv$trtvar]]) %>%
      summarise(nsubj = n_distinct(USUBJID), .groups = "drop"),
    tibble(trt = "Total", nsubj = n_distinct(df$USUBJID))) %>%
    mutate(AESOC = NA_character_, AEDECOD = NA_character_, level = 0L,
           term = paste0("Participants with any ", panel_label))

  soc <- bind_rows(
    df %>% group_by(trt = .data[[dv$trtvar]], AESOC) %>%
      summarise(nsubj = n_distinct(USUBJID), .groups = "drop"),
    df %>% group_by(AESOC) %>%
      summarise(nsubj = n_distinct(USUBJID), .groups = "drop") %>% mutate(trt = "Total")) %>%
    mutate(level = 1L, term = AESOC)

  socpt <- bind_rows(
    df %>% group_by(trt = .data[[dv$trtvar]], AESOC, AEDECOD) %>%
      summarise(nsubj = n_distinct(USUBJID), .groups = "drop"),
    df %>% group_by(AESOC, AEDECOD) %>%
      summarise(nsubj = n_distinct(USUBJID), .groups = "drop") %>% mutate(trt = "Total")) %>%
    mutate(level = 2L, term = paste0("   ", AEDECOD))

  soc_ord <- df %>% group_by(AESOC) %>%
    summarise(socn = n_distinct(USUBJID), .groups = "drop")
  pt_ord  <- df %>% group_by(AESOC, AEDECOD) %>%
    summarise(ptn = n_distinct(USUBJID), .groups = "drop")

  bind_rows(any_te, soc, socpt) %>%
    left_join(denom, by = "trt") %>%
    mutate(value = n_pct(nsubj, N), panel = panel_label, panel_ord = panel_ord) %>%
    left_join(soc_ord, by = "AESOC") %>%
    left_join(pt_ord,  by = c("AESOC","AEDECOD")) %>%
    arrange(desc(socn), AESOC, level, desc(ptn)) %>%
    select(panel, panel_ord, term, level, trt, value)
}

## --- three panels: SAE, Death, AE leading to withdrawal ----------------------
sae   <- panel(adae %>% filter(AESER == "Y"),                "Serious TEAE (SAE)",          1L)
death <- panel(adae %>% filter(AESDTH == "Y"),               "TEAE Leading to Death",       2L)
wd    <- panel(adae %>% filter(AEACN == "DRUG WITHDRAWN"),   "TEAE Leading to Withdrawal",  3L)

rep <- bind_rows(sae, death, wd) %>%
  arrange(panel_ord) %>%
  select(panel, term, level, trt, value) %>%
  pivot_wider(names_from = trt, values_from = value)

ttl <- tfl_titles(num = "14.3.1.5", type = "Table",
   text = "Serious Adverse Events, Deaths, and Adverse Events Leading to Withdrawal by SOC and PT",
   pop  = "Safety Population",
   foot = paste0("A participant is counted once at each level within each panel. Columns = treatment (TRTA). ",
                 "% = participants / N exposed (ADEX). SAE = AESER=Y; Death = AESDTH=Y; Withdrawal = AEACN='DRUG WITHDRAWN'. MedDRA v27.0."))

## rtables: row split on panel -> SOC -> PT; treatment columns + Total
print(rep)
