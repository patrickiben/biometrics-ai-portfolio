################################################################################
# TABLE     : t_ae_by_severity  (Crossover - 2x2 or Williams)
# TITLE     : Treatment-Emergent Adverse Events by Maximum Severity,
#             System Organ Class and Preferred Term
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADAE (TRTEMFL == "Y"); ADEX for per-treatment denominators
# NOTE      : PSEUDOCODE. Counts = PARTICIPANTS (n_distinct USUBJID), NOT event rows.
#             A participant is counted ONCE per SOC/PT at their MAXIMUM severity
#             (AESEVN: 1=Mild, 2=Moderate, 3=Severe) for that treatment, so the
#             worst grade governs. Columns = treatment (TRTA) x severity. %
#             denominator = participants exposed to that treatment from ADEX
#             (period-bearing), NOT ADSL.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("CROSSOVER")                 # trtvar=TRTA, byperiod=APERIOD/APERIODC

sev_lab <- c(`1` = "Mild", `2` = "Moderate", `3` = "Severe")

## --- per-TREATMENT denominators from ADEX (participants dosed per TRTA) ----------
denom <- adam$adex %>%
  filter(SAFFL == "Y") %>%
  group_by(trt = .data[[dv$trtvar]]) %>%
  summarise(N = n_distinct(USUBJID), .groups = "drop") %>%
  bind_rows(tibble(trt = "Total",
                   N = n_distinct(adam$adex$USUBJID[adam$adex$SAFFL == "Y"])))

adae <- adam$adae %>% filter(SAFFL == "Y", TRTEMFL == "Y")

## --- collapse to ONE row per participant*treatment*SOC*PT at MAX severity --------
## worst grade per participant within each SOC/PT and treatment governs the count.
worst <- adae %>%
  group_by(USUBJID, trt = .data[[dv$trtvar]], AESOC, AEDECOD) %>%
  summarise(max_sev = max(AESEVN, na.rm = TRUE), .groups = "drop") %>%
  mutate(sev = factor(sev_lab[as.character(max_sev)],
                      levels = c("Mild","Moderate","Severe")))

## --- count distinct participants per treatment x SOC x PT x severity -------------
count_block <- function(byvars, level, term_fun) {
  per <- worst %>%
    group_by(across(all_of(c("trt", byvars, "sev")))) %>%
    summarise(nsubj = n_distinct(USUBJID), .groups = "drop")
  tot <- worst %>%
    group_by(across(all_of(c(byvars, "sev")))) %>%
    summarise(nsubj = n_distinct(USUBJID), .groups = "drop") %>%
    mutate(trt = "Total")
  bind_rows(per, tot) %>% mutate(level = level, term = term_fun(.))
}

soc   <- count_block("AESOC",              1L, function(d) d$AESOC)
socpt <- count_block(c("AESOC","AEDECOD"), 2L, function(d) paste0("   ", d$AEDECOD))

## "Any TEAE" by severity (max across all SOC/PT per participant*treatment)
any_worst <- adae %>%
  group_by(USUBJID, trt = .data[[dv$trtvar]]) %>%
  summarise(max_sev = max(AESEVN, na.rm = TRUE), .groups = "drop") %>%
  mutate(sev = factor(sev_lab[as.character(max_sev)],
                      levels = c("Mild","Moderate","Severe")))
any_te <- bind_rows(
  any_worst %>% group_by(trt, sev) %>%
    summarise(nsubj = n_distinct(USUBJID), .groups = "drop"),
  any_worst %>% group_by(sev) %>%
    summarise(nsubj = n_distinct(USUBJID), .groups = "drop") %>% mutate(trt = "Total")) %>%
  mutate(level = 0L, term = "Participants with any TEAE", AESOC = NA_character_)

## ordering: SOC by overall participant count desc; PT within SOC desc
soc_ord <- adae %>% group_by(AESOC) %>%
  summarise(socn = n_distinct(USUBJID), .groups = "drop")
pt_ord  <- worst %>% group_by(AESOC, AEDECOD) %>%
  summarise(ptn = n_distinct(USUBJID), .groups = "drop")

## --- n (%) per treatment x severity; columns = treatment_severity ------------
rep <- bind_rows(any_te, soc, socpt) %>%
  left_join(denom, by = "trt") %>%
  mutate(value = n_pct(nsubj, N),
         col   = paste(trt, sev, sep = "_")) %>%
  left_join(soc_ord, by = "AESOC") %>%
  left_join(pt_ord,  by = c("AESOC","AEDECOD")) %>%
  arrange(desc(socn), AESOC, level, desc(ptn)) %>%
  select(term, level, col, value) %>%
  pivot_wider(names_from = col, values_from = value)

ttl <- tfl_titles(num = "14.3.1.3", type = "Table",
   text = "Treatment-Emergent Adverse Events by Maximum Severity, System Organ Class and Preferred Term",
   pop  = "Safety Population",
   foot = paste0("A participant is counted once per SOC/PT at their maximum severity for the treatment. ",
                 "Columns = treatment (TRTA) x severity. % = participants / N exposed (ADEX). Severity: 1=Mild, 2=Moderate, 3=Severe. MedDRA v27.0."))

## rtables: nested column split treatment -> severity, row split SOC -> PT
print(rep)
