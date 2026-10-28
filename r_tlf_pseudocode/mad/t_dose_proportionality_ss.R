# TABLE: t_dose_proportionality_ss (mad)
# TITLE : PK Dose Proportionality: Prespecified Power Model
# Runnable analysis with explicit study settings and pre-derived ADaM input.
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
source("../01_analysis_models.R")
dv <- design_vars("MAD")
ttl <- tfl_titles(num = "14.4.5.2", type = "Table",
  text = "PK Dose Proportionality: Prespecified Power Model", pop = "PK parameter population",
  foot = "Ordinary least squares of log exposure on log actual dose. Treatment ordering codes are never doses. Critical slope bounds use the dose range of each parameter analysis. One record per participant and parameter; nonpositive values and placebo are excluded with counts. Specified bounds and confidence are reported; fit assumptions and study suitability require review.")
tab <- tfl_model_dose_proportionality(adam$adpp, mad = TRUE)
print(tab)
