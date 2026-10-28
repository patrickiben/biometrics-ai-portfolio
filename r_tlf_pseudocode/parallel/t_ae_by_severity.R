################################################################################
# TABLE     : t_ae_by_severity  (Parallel-group)
# TITLE     : Treatment-Emergent Adverse Events by System Organ Class,
#             Preferred Term, and Maximum Severity
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADAE (TRTEMFL == "Y")
# NOTE      : ANALYSIS TEMPLATE. Counts = PARTICIPANTS (n_distinct USUBJID), NOT event rows.
#             A participant is counted at their MAXIMUM severity within each SOC/PT
#             (worst-case), so within a PT the severity columns are mutually
#             exclusive per participant. n (%) per arm; % denominator = SAFFL N per
#             arm. Parallel: column = TRT01A.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("PARALLEL")                  # trtvar = TRT01A

# Planned safety columns come from the population source, including zero-event arms.
denom <- bign(adam$adsl, dv$trtvar, "SAFFL")
adae <- adam$adae %>% filter(SAFFL == "Y", TRTEMFL == "Y")
rep <- ae_hierarchy(adae, dv$trtvar, denom, severity = TRUE)

ttl <- tfl_titles(
  num  = "14.3.1.2",
  type = "Table",
  text = "Treatment-Emergent Adverse Events by SOC, Preferred Term, and Maximum Severity",
  pop  = "Safety Population",
  foot = paste("A participant is counted once at their MAXIMUM severity within each",
               "SOC and Preferred Term. Severity per investigator (Mild/Moderate/Severe).",
               "% = participants / N in arm. {meddra}."))

## rtables: split_cols_by(TRT01A) then nested split_cols_by(severity);
## split_rows_by(AESOC) with PT analyzed within (indent level 2).
print(rep)
