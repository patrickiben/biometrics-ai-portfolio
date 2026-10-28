################################################################################
# TABLE     : t_ae_by_severity  (Crossover - 2x2 or Williams)
# TITLE     : Treatment-Emergent Adverse Events by Maximum Severity,
#             System Organ Class and Preferred Term
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADAE (TRTEMFL == "Y"); ADEX for per-treatment denominators
# NOTE      : ANALYSIS TEMPLATE. Counts = PARTICIPANTS (n_distinct USUBJID), NOT event rows.
#             A participant is counted ONCE per SOC/PT at their MAXIMUM severity
#             (AESEVN: 1=Mild, 2=Moderate, 3=Severe) for that treatment, so the
#             worst grade governs. Columns = treatment (TRTA) x severity. %
#             denominator = participants exposed to that treatment from ADEX
#             (period-bearing), NOT ADSL.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("CROSSOVER")                 # trtvar=TRTA, byperiod=APERIOD/APERIODC

# Planned safety columns come from the population source, including zero-event arms.
denom <- bign(adam$adex, dv$trtvar, "SAFFL")
adae <- adam$adae %>% filter(SAFFL == "Y", TRTEMFL == "Y")
rep <- ae_hierarchy(adae, dv$trtvar, denom, severity = TRUE)

ttl <- tfl_titles(num = "14.3.1.3", type = "Table",
   text = "Treatment-Emergent Adverse Events by Maximum Severity, System Organ Class and Preferred Term",
   pop  = "Safety Population",
   foot = paste0("A participant is counted once per SOC/PT at their maximum severity for the treatment. ",
                 "Columns = treatment (TRTA) x severity. % = participants / N exposed (ADEX). Severity: 1=Mild, 2=Moderate, 3=Severe. {meddra}."))

## rtables: nested column split treatment -> severity, row split SOC -> PT
print(rep)
