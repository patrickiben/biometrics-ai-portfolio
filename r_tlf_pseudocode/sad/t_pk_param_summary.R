################################################################################
# TABLE     : t_pk_param_summary  (SAD - Single Ascending Dose / per-cohort)
# TITLE     : Summary of Plasma PK Parameters by Dose Cohort
# POPULATION: PK Parameter Population (PKFL == "Y")
# INPUT     : ADPP (PARAMCD = CMAX, TMAX, AUCLST, AUCIFO, T12, CLFO, VZFO, ...)
# NOTE      : PSEUDOCODE. n, Mean, SD, CV%, Geo Mean, Geo CV%, Median, Min, Max.
#             Geometric stats on the LOG scale (pkstats). Tmax = Median (Min,Max)
#             ONLY. SAD = parallel cohorts: column = TRT01A = dose level, single
#             dose (no accumulation, no steady state). Dose-normalized exposure
#             (e.g. Cmax/dose, AUC/dose) can be added as extra blocks to preview
#             dose-proportionality; formal power model -> t_dose_proportionality.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SAD")                        # column = TRT01A (= dose cohort)

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

## --- stack params (rows) x dose-cohort (cols), dose-ordered -----------------
ord <- adam$adpp %>% filter(PKFL == "Y") %>%
  distinct(trt = .data[[dv$trtvar]], trtn = .data[[dv$trtnvar]]) %>%
  arrange(trtn) %>% pull(trt)

tab <- bind_rows(cont, tmax) %>%
  rename(trt = all_of(dv$trtvar)) %>%
  mutate(trt = factor(trt, levels = ord)) %>%          # ascending dose order
  select(PARAM, trt, stat, value) %>%
  pivot_wider(names_from = trt, values_from = value)

ttl <- tfl_titles(num = "14.4.1.1", type = "Table",
   text = "Summary of Plasma Pharmacokinetic Parameters by Dose Cohort",
   pop  = "Pharmacokinetic Parameter Population",
   foot = paste("CV% arithmetic; Geo CV% = 100*sqrt(exp(s^2_log)-1). Tmax: Median (Min, Max).",
                "N excludes BLQ-driven non-estimable parameters. Column = dose cohort,",
                "single dose (no accumulation). Dose-proportionality assessed in",
                "t_dose_proportionality (power model)."))

## rtables: split_rows_by(PARAM) -> analyze(stat rows); columns ordered by dose
print(tab)
