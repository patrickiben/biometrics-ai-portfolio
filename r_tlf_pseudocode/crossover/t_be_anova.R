# TABLE: t_be_anova (crossover)
# TITLE : PK Exposure Ratio: Test versus Reference
# Runnable analysis with explicit study settings and pre-derived ADaM input.
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
source("../01_analysis_models.R")
dv <- design_vars("CROSSOVER")
ttl <- tfl_titles(num = "t_be_anova", type = "Table",
  text = "PK Exposure Ratio: Test versus Reference", pop = "PK parameter population",
  foot = "Log-scale mixed model; explicit Test minus Reference contrast; Satterthwaite degrees of freedom from lmerTest. Exactly two periods and complete positive pairs are required; excluded participants and fit warnings are shown. Bounds and confidence are user specified. Numerical inclusion in bounds is not a regulatory conclusion. Supported design: non-replicate randomized 2x2 crossover with sequence and period fixed effects.")
tab <- tfl_model_be(adam$adpp, "CROSSOVER")
print(tab)
