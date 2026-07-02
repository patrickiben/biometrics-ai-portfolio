################################################################################
# TABLE     : t_ae_by_severity  (Multiple Ascending Dose)
# TITLE     : Treatment-Emergent Adverse Events by System Organ Class,
#             Preferred Term, and Maximum Severity, by Dose Level
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADAE (TRTEMFL == "Y")
# NOTE      : PSEUDOCODE. MAD = parallel ascending-dose cohorts, repeated dosing;
#             one treatment per participant, so column = dose level (dv$trtvar =
#             TRT01A) ordered ascending by TRT01AN. Counts = PARTICIPANTS
#             (n_distinct USUBJID), NOT event rows. A participant is counted at their
#             MAXIMUM severity within each SOC/PT (worst-case), so within a PT the
#             severity columns are mutually exclusive per participant. n (%) per dose;
#             % denominator = SAFFL N per dose.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("MAD")                       # trtvar = TRT01A (dose level)

denom <- bign(adam$adsl, trtvar = dv$trtvar, popfl = "SAFFL")

## column (dose) order: ascending by numeric dose TRT01AN
doses <- adam$adsl %>% filter(SAFFL == "Y") %>%
  distinct(trt = .data[[dv$trtvar]], trtn = .data[[dv$trtnvar]]) %>%
  arrange(trtn) %>% pull(trt)

sev_lab <- c(`1` = "Mild", `2` = "Moderate", `3` = "Severe")

adae <- adam$adae %>% filter(SAFFL == "Y", TRTEMFL == "Y") %>%
  mutate(trt = .data[[dv$trtvar]])

## --- collapse to WORST severity per participant within SOC & PT -----------------
## Within a PT a participant contributes once, at their max AESEVN (severity is an
## intensity scale 1<2<3, so max() is the correct worst-case here -- unlike lab
## ANRIND, which is NOT ordinal and must use the furthest-from-NORMAL rule).
worst_pt <- adae %>%
  group_by(trt, AESOC, AEDECOD, USUBJID) %>%
  summarise(maxsev = max(AESEVN, na.rm = TRUE), .groups = "drop")

worst_soc <- adae %>%
  group_by(trt, AESOC, USUBJID) %>%
  summarise(maxsev = max(AESEVN, na.rm = TRUE), .groups = "drop")

worst_any <- adae %>%
  group_by(trt, USUBJID) %>%
  summarise(maxsev = max(AESEVN, na.rm = TRUE), .groups = "drop")

## --- participant counts by severity at each level (distinct participants) ----------
cnt <- function(df, byvars, level, termfun) {
  df %>% group_by(across(all_of(c("trt", byvars))), sev = maxsev) %>%
    summarise(nsubj = n_distinct(USUBJID), .groups = "drop") %>%
    mutate(level = level, term = termfun(cur_data_all()))
}
any_rows <- cnt(worst_any, character(0), 0L, function(d) "Participants with any TEAE")
soc_rows <- cnt(worst_soc, "AESOC",       1L, function(d) d$AESOC)
pt_rows  <- cnt(worst_pt,  c("AESOC","AEDECOD"), 2L, function(d) paste0("   ", d$AEDECOD))

## --- ordering: SOC by overall participant freq desc; PT within SOC desc ---------
soc_ord <- worst_soc %>% group_by(AESOC) %>%
  summarise(socn = n_distinct(USUBJID), .groups = "drop")
pt_ord  <- worst_pt  %>% group_by(AESOC, AEDECOD) %>%
  summarise(ptn = n_distinct(USUBJID), .groups = "drop")

## --- assemble: long over (term x dose x severity) -> wide ((dose,sev)) ------
rep <- bind_rows(any_rows, soc_rows, pt_rows) %>%
  left_join(denom, by = "trt") %>%
  mutate(value = n_pct(nsubj, N),
         sevlab = factor(sev_lab[as.character(sev)],
                         levels = c("Mild","Moderate","Severe")),
         trt = factor(trt, levels = doses)) %>%        # keep ascending-dose order
  left_join(soc_ord, by = "AESOC") %>%
  left_join(pt_ord,  by = c("AESOC","AEDECOD")) %>%
  arrange(desc(socn), AESOC, level, desc(ptn), trt, sevlab) %>%
  select(term, level, trt, sevlab, value) %>%
  pivot_wider(names_from = c(trt, sevlab), values_from = value,
              names_sep = " / ")

ttl <- tfl_titles(
  num  = "14.3.1.2",
  type = "Table",
  text = "Treatment-Emergent Adverse Events by SOC, Preferred Term, and Maximum Severity, by Dose Level",
  pop  = "Safety Population",
  foot = paste("MAD: parallel ascending-dose cohorts, repeated dosing; columns = dose",
               "level (ascending), nested by severity. A participant is counted once at their",
               "MAXIMUM severity within each SOC and Preferred Term. Severity per",
               "investigator (Mild/Moderate/Severe). % = participants / N at dose. MedDRA v27.0."))

## rtables: split_cols_by(dose, ascending) then nested split_cols_by(severity);
## split_rows_by(AESOC) with PT analyzed within (indent level 2).
print(rep)
