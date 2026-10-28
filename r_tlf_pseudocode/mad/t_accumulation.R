# TABLE: t_accumulation (mad)
# TITLE : Paired Accumulation Ratios and Descriptive Trough Trends
# Runnable analysis with explicit study settings and pre-derived ADaM input.
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
source("../01_analysis_models.R")
dv <- design_vars("MAD")
ttl <- tfl_titles(num = "t_accumulation", type = "Table",
  text = "Paired Accumulation Ratios and Descriptive Trough Trends", pop = "PK parameter and concentration populations",
  foot = "Accumulation is the geometric mean of within-participant final/first occasion ratios, with a paired-log t confidence interval. AUC ratios require confirmation of comparable integration intervals. Selected days, parameter codes, missing pairs and active treatment doses are explicit. Troughs use ATPTN=0 within the configured day window. A slope confidence interval containing zero does not establish steady state.")
result <- tfl_model_accumulation(adam$adpp, adam$adpc)
print(result$ratios)
print(result$troughs)
print(result$slopes)
