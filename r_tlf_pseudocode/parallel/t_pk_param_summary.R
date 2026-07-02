################################################################################
# TABLE     : t_pk_param_summary  (Parallel-group / per-dose)
# TITLE     : Summary of Plasma PK Parameters by Treatment
# POPULATION: PK Parameter Population (PKFL == "Y")
# INPUT     : ADPP (PARAMCD = CMAX, TMAX, AUCLST, AUCIFO, T12, CL, VZ, ...)
# NOTE      : PSEUDOCODE. n, Mean, SD, CV%, Geo Mean, Geo CV%, Median, Min, Max.
#             Geometric stats on the LOG scale. Tmax = Median (Min, Max) ONLY.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("PARALLEL")                 # column = TRT01A (= dose)

pp <- adam$adpp %>% filter(PKFL == "Y")
by <- c(dv$trtvar, "PARAMCD", "PARAM")

## --- non-Tmax parameters: arithmetic + geometric (pkstats does log scale) --
cont <- pkstats(pp %>% filter(PARAMCD != "TMAX"), var = "AVAL", by = by) %>%
  transmute(across(all_of(by)),
            n               = as.character(n),
            `Mean (SD)`     = sprintf("%.3g (%.3g)", mean, sd),
            `CV%`           = sprintf("%.1f", cv),
            `Geo Mean`      = sprintf("%.3g", geomean),
            `Geo CV%`       = sprintf("%.1f", geocv),
            `Median`        = sprintf("%.3g", median),
            `Min, Max`      = sprintf("%.3g, %.3g", min, max)) %>%
  pivot_longer(c(`n`,`Mean (SD)`,`CV%`,`Geo Mean`,`Geo CV%`,`Median`,`Min, Max`),
               names_to = "stat", values_to = "value")

## --- Tmax: Median (Min, Max) ONLY -----------------------------------------
tmax <- pp %>% filter(PARAMCD == "TMAX") %>%
  group_by(across(all_of(by))) %>%
  summarise(med = median(AVAL), min = min(AVAL), max = max(AVAL), .groups = "drop") %>%
  transmute(across(all_of(by)), stat = "Median (Min, Max)",
            value = sprintf("%.2f (%.2f, %.2f)", med, min, max))

## --- stack params (rows) x treatment (cols) -------------------------------
tab <- bind_rows(cont, tmax) %>%
  select(PARAM, .data[[dv$trtvar]], stat, value) %>%
  pivot_wider(names_from = all_of(dv$trtvar), values_from = value)

ttl <- tfl_titles(num = "14.4.1.1", type = "Table",
   text = "Summary of Plasma Pharmacokinetic Parameters",
   pop  = "Pharmacokinetic Parameter Population",
   foot = "CV% arithmetic; Geo CV% = 100*sqrt(exp(s^2_log)-1). Tmax: Median (Min, Max). N excludes BLQ-driven non-estimable parameters.")

print(tab)
