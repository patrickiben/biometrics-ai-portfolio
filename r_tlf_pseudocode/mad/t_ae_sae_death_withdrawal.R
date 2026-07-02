################################################################################
# TABLE     : t_ae_sae_death_withdrawal  (Multiple Ascending Dose)
# TITLE     : Serious Adverse Events, Deaths, and Adverse Events Leading to
#             Study Drug Discontinuation by System Organ Class and Preferred
#             Term, by Dose Level
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADAE (TRTEMFL == "Y")
# NOTE      : PSEUDOCODE. MAD = parallel ascending-dose cohorts, repeated dosing;
#             one treatment per participant, so column = dose level (dv$trtvar =
#             TRT01A) ordered ascending by TRT01AN. Three stacked panels (SAEs /
#             Deaths / Discontinuations). Counts = PARTICIPANTS (n_distinct USUBJID),
#             NOT event rows. n (%) per dose; % denominator = SAFFL N per dose.
#             Fatal = AESDTH=="Y"; discontinuation = AEACN=="DRUG WITHDRAWN".
#             In MAD the discontinuation panel is read against ascending dose to
#             support dose-escalation / stopping-rule review over the dosing
#             period.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("MAD")                       # trtvar = TRT01A (dose level)

denom <- bign(adam$adsl, trtvar = dv$trtvar, popfl = "SAFFL")

## column (dose) order: ascending by numeric dose TRT01AN
doses <- adam$adsl %>% filter(SAFFL == "Y") %>%
  distinct(trt = .data[[dv$trtvar]], trtn = .data[[dv$trtnvar]]) %>%
  arrange(trtn) %>% pull(trt)

adae <- adam$adae %>% filter(SAFFL == "Y", TRTEMFL == "Y")

## --- generic panel builder: Any -> SOC -> indented PT (distinct participants) ---
## Each panel is the same SOC/PT skeleton restricted by a category predicate.
build_panel <- function(df, where, anylabel, panel) {
  sub <- df %>% filter(!!where)

  any_row <- sub %>% group_by(trt = .data[[dv$trtvar]]) %>%
    summarise(nsubj = n_distinct(USUBJID), .groups = "drop") %>%
    mutate(AESOC = NA_character_, AEDECOD = NA_character_, level = 0L, term = anylabel)

  soc <- aecount(sub, trtvar = dv$trtvar, where = where, byvars = "AESOC") %>%
    mutate(level = 1L, term = AESOC)

  socpt <- aecount(sub, trtvar = dv$trtvar, where = where,
                   byvars = c("AESOC","AEDECOD")) %>%
    mutate(level = 2L, term = paste0("   ", AEDECOD))

  soc_ord <- soc   %>% group_by(AESOC)          %>% summarise(socn = sum(nsubj), .groups = "drop")
  pt_ord  <- socpt %>% group_by(AESOC, AEDECOD) %>% summarise(ptn  = sum(nsubj), .groups = "drop")

  bind_rows(any_row, soc, socpt) %>%
    left_join(soc_ord, by = "AESOC") %>%
    left_join(pt_ord,  by = c("AESOC","AEDECOD")) %>%
    arrange(desc(socn), AESOC, level, desc(ptn)) %>%
    mutate(panel = panel, panel_ord = match(panel, c(
      "Serious Adverse Events",
      "Adverse Events with Fatal Outcome",
      "Adverse Events Leading to Study Drug Discontinuation")))
}

## --- three panels ----------------------------------------------------------
panels <- bind_rows(
  build_panel(adae, quote(AESER == "Y"),
              "Participants with any SAE", "Serious Adverse Events"),
  build_panel(adae, quote(AESDTH == "Y"),
              "Participants with any AE with fatal outcome", "Adverse Events with Fatal Outcome"),
  build_panel(adae, quote(AEACN == "DRUG WITHDRAWN"),
              "Participants with any AE leading to discontinuation",
              "Adverse Events Leading to Study Drug Discontinuation")
)

## --- attach denominators -> n (%), to wide per dose (ascending) ------------
rep <- panels %>%
  left_join(denom, by = "trt") %>%
  mutate(value = n_pct(nsubj, N),
         trt = factor(trt, levels = doses)) %>%        # keep ascending-dose order
  arrange(panel_ord, desc(socn), AESOC, level, desc(ptn)) %>%
  select(panel, panel_ord, term, level, trt, value) %>%
  pivot_wider(names_from = trt, values_from = value)

ttl <- tfl_titles(
  num  = "14.3.1.4",
  type = "Table",
  text = "Serious Adverse Events, Deaths, and AEs Leading to Discontinuation by SOC and Preferred Term, by Dose Level",
  pop  = "Safety Population",
  foot = paste("MAD: parallel ascending-dose cohorts, repeated dosing; columns = dose",
               "level (ascending). SAE = AESER==Y; fatal = AESDTH==Y; discontinuation =",
               "AEACN==DRUG WITHDRAWN. Treatment-emergent only (TRTEMFL=Y). A participant is",
               "counted once at each level within a panel. % = participants / N at dose. MedDRA v27.0."))

## rtables: split_rows_by(panel) outermost; within each, SOC bold, PT indented;
## split_cols_by(dose) ascending.
print(rep)
