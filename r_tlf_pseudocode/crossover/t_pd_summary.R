# TABLE: t_pd_summary (crossover)
# TITLE : Pharmacodynamic Endpoints by Treatment, Period, Day, Visit and Time
# Runnable analysis with explicit study settings and pre-derived ADaM input.
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
source("../01_analysis_models.R")
dv <- design_vars("CROSSOVER")
ttl <- tfl_titles(num = "t_pd_summary", type = "Table",
  text = "Pharmacodynamic Endpoints by Treatment, Period, Day, Visit and Time", pop = "PD-evaluable population",
  foot = "Descriptive summaries of supplied ADaM values and baseline changes. Counts are participants with finite values at each analysis time; missing counts are separate. Repeated days and periods remain separate. No clinical conclusion is implied.")
pd <- tfl_model_pd_data(adam$adpd, dv)
tab <- tfl_model_pd_summary(pd)
print(tab)
