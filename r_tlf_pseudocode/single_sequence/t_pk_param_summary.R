################################################################################
# TABLE     : t_pk_param_summary  (Single-/fixed-sequence DDI)
# TITLE     : Summary of Plasma PK Parameters of the Victim Drug by Period
#             (Reference vs Test)
# POPULATION: PK Parameter Population (PKFL == "Y")
# INPUT     : ADPP (PARAMCD = CMAX, TMAX, AUCLST, AUCIFO, T12, CL, VZ, ...)
# NOTE      : PSEUDOCODE. n, Mean, SD, CV%, Geo Mean, Geo CV%, Median, Min, Max.
#             Geometric stats on the LOG scale. Tmax/Tmax,ss (TMAX, TMAXSS) =
#             Median (Min, Max) ONLY and EXCLUDED from the geometric block (in
#             both languages). Single-/fixed-sequence DDI: column = study PERIOD
#             (dv$byperiod) -- Period 1 = victim alone (reference), Period 2 =
#             victim + perpetrator (test). There is NO randomized sequence, so
#             parameters are summarised within period, not pooled across a
#             sequence. The formal Test-vs-Reference comparison (ratio + 90% CI)
#             lives in t_be_anova.R; this is the descriptive companion.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SINGLESEQ")                 # column = study PERIOD (no sequence)

## Tmax-type parameters: Median (Min, Max) only, excluded from the geometric block
tmax_cds <- c("TMAX", "TMAXSS")

pp <- adam$adpp %>% filter(PKFL == "Y") %>%
  mutate(period  = .data[[dv$byperiod[1]]],     # APERIOD numeric sort key
         periodc = .data[[dv$byperiod[2]]])      # APERIODC label: Reference / Test
by <- c("period", "periodc", "PARAMCD", "PARAM")

## --- non-Tmax parameters: arithmetic + geometric (pkstats does log scale) --
cont <- pkstats(pp %>% filter(!PARAMCD %in% tmax_cds), var = "AVAL", by = by) %>%
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

## --- Tmax / Tmax,ss: Median (Min, Max) ONLY -------------------------------
tmax <- pp %>% filter(PARAMCD %in% tmax_cds) %>%
  group_by(across(all_of(by))) %>%
  summarise(med = median(AVAL), min = min(AVAL), max = max(AVAL), .groups = "drop") %>%
  transmute(across(all_of(by)), stat = "Median (Min, Max)",
            value = sprintf("%.2f (%.2f, %.2f)", med, min, max))

## --- stack params (rows) x PERIOD (cols) ----------------------------------
tab <- bind_rows(cont, tmax) %>%
  arrange(PARAM, period) %>%
  select(PARAM, stat, periodc, value) %>%
  pivot_wider(names_from = periodc, values_from = value)   # columns = Reference / Test period

ttl <- tfl_titles(num = "14.4.4.1", type = "Table",
   text = "Summary of Plasma Pharmacokinetic Parameters of the Victim Drug by Period",
   pop  = "Pharmacokinetic Parameter Population",
   foot = paste("CV% arithmetic; Geo CV% = 100*sqrt(exp(s^2_log)-1). Tmax: Median (Min, Max).",
                "Columns = study PERIOD: Period 1 = victim alone (reference),",
                "Period 2 = victim + perpetrator (test); fixed-sequence design (no randomized sequence).",
                "N excludes BLQ-driven non-estimable parameters."))

## render: rtables split_rows_by(PARAM), analyze(stat); or gt grouped by PARAM
print(tab)
