# TABLE: t_cqtc_hysteresis (mad)
# TITLE : Exploratory Concentration-QTc Delay Diagnostic
# Runnable analysis with explicit study settings and pre-derived ADaM input.
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
source("../01_analysis_models.R")
dv <- design_vars("MAD")
ttl <- tfl_titles(num = "t_cqtc_hysteresis", type = "Table",
  text = "Exploratory Concentration-QTc Delay Diagnostic", pop = "Safety ECG and PK concentration populations",
  foot = "Exploratory signed closed-loop areas from participant-scaled concentrations and direct-effect model residuals. Complete common nominal-time profiles are required; actual PK times determine path order. Shared placebo-profile variation is included through an approximate Welch-Satterthwaite calculation. The Day -1 diagnostic is available only for complete baseline profiles. This custom diagnostic is not a regulatory C-QTc analysis; significance alone does not establish delay or clinical risk. Emax uses positive EC50 and rejects unstable fits. Dose mapping, profile days and model form are prespecified settings.")
prepared <- tfl_model_cqtc_data(adam$adpc, adam$adeg, mad = TRUE)
result <- tfl_model_cqtc(prepared)
print(result$summary)
print(result$coefficients)
print(result$participants)
