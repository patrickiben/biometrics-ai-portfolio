################################################################################
# TABLE     : t_pk_param_summary  (Crossover - 2x2 or Williams)
# TITLE     : Summary of Plasma PK Parameters by Treatment
# POPULATION: PK Parameter Population (PKFL == "Y")
# INPUT     : ADPP (PARAMCD = CMAX, TMAX, AUCLST, AUCIFO, T12, CL, VZ, ...)
# NOTE      : PSEUDOCODE. n, Mean, SD, CV%, Geo Mean, Geo CV%, Median, Min, Max.
#             Geometric stats on the LOG scale. Tmax = Median (Min, Max) ONLY.
#             Crossover: column = dv$trtvar (TRTA, actual treatment). Each TRTA
#             column pools that treatment's parameters across whichever period it
#             was received in (within-participant design). The formal Test-vs-
#             Reference comparison (GMR + 90% CI) lives in t_be_anova.R; this is
#             the descriptive companion.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("CROSSOVER")                 # column = TRTA (actual treatment)

pp <- adam$adpp %>% filter(PKFL == "Y") %>%
  mutate(trt = .data[[dv$trtvar]])              # re-point column to crossover TRTA
by <- c("trt", "PARAMCD", "PARAM")

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
  select(PARAM, trt, stat, value) %>%
  pivot_wider(names_from = trt, values_from = value)

ttl <- tfl_titles(num = "14.4.4.1", type = "Table",
   text = "Summary of Plasma Pharmacokinetic Parameters by Treatment",
   pop  = "Pharmacokinetic Parameter Population",
   foot = paste("CV% arithmetic; Geo CV% = 100*sqrt(exp(s^2_log)-1). Tmax: Median (Min, Max).",
                "Column = actual treatment (TRTA), pooled across periods.",
                "N excludes BLQ-driven non-estimable parameters."))

## render: rtables split_rows_by PARAM, analyze stat; or gt grouped by PARAM
print(tab)
