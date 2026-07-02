################################################################################
# TABLE     : t_pk_param_summary  (MAD - Multiple Ascending Dose / per-cohort)
# TITLE     : Summary of Plasma PK Parameters by Dose Cohort and Dosing Day
# POPULATION: PK Parameter Population (PKFL == "Y")
# INPUT     : ADPP (PARAMCD = CMAX, TMAX, AUCLST, AUCTAU, CMAXSS, CMINSS, CTROUGH,
#             T12, CLFO/CLSS, VZFO, RAC parameters, ...)
# NOTE      : PSEUDOCODE. n, Mean, SD, CV%, Geo Mean, Geo CV%, Median, Min, Max
#             by dose cohort (TRT01A) x dosing day (AVISIT: Day 1 / Day N).
#             Geometric stats on the LOG scale (pkstats). Tmax = Median (Min, Max)
#             ONLY. MAD = parallel cohorts, REPEATED dosing: Day 1 carries single-
#             dose parameters (Cmax, AUClast/AUCinf); Day N carries STEADY-STATE
#             parameters (AUCtau, Cmax,ss, Cmin,ss, Ctrough, CL/F,ss). Accumulation
#             ratios (Rac) summarized separately in t_accumulation.R. Column =
#             dose level, placebo pooled.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("MAD")                       # column = TRT01A (= dose cohort)

## Parameters split by occasion:
##   Day 1  (single dose)  : CMAX, TMAX, AUCLST, AUCIFO, T12, LAMZ
##   Day N  (steady state) : CMAXSS, TMAXSS, AUCTAU, CMINSS, CTROUGH, CAVGSS, FLPTAU,
##                           T12, CLSS, VSSF (RACMAX/RACAUC in t_accumulation)
## Both TMAX (single dose) and TMAXSS (steady state) are Median (Min, Max) only.
pp <- adam$adpp %>%
  filter(PKFL == "Y",
         PARAMCD %in% c("CMAX","TMAX","AUCLST","AUCIFO","T12","LAMZ",
                        "CMAXSS","TMAXSS","AUCTAU","CMINSS","CTROUGH","CAVGSS",
                        "FLPTAU","CLSS","VSSF"))
by <- c(dv$trtvar, "AVISIT", "PARAMCD", "PARAM")          # cohort x dosing day x parameter

## --- non-Tmax parameters: arithmetic + geometric (pkstats does log scale) --
## TMAX and TMAXSS excluded from the geometric block (median-only, like the SAS twin)
cont <- pkstats(pp %>% filter(!PARAMCD %in% c("TMAX","TMAXSS")), var = "AVAL", by = by) %>%
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

## --- Tmax / Tmax,ss: Median (Min, Max) ONLY (per dosing day) ---------------
tmax <- pp %>% filter(PARAMCD %in% c("TMAX","TMAXSS")) %>%
  group_by(across(all_of(by))) %>%
  summarise(med = median(AVAL), min = min(AVAL), max = max(AVAL), .groups = "drop") %>%
  transmute(across(all_of(by)), stat = "Median (Min, Max)",
            value = sprintf("%.2f (%.2f, %.2f)", med, min, max))

## --- stack params (rows, blocked by dosing day) x dose-cohort (cols) -------
tab <- bind_rows(cont, tmax) %>%
  select(AVISIT, PARAM, all_of(dv$trtvar), stat, value) %>%
  arrange(AVISIT, PARAM) %>%
  pivot_wider(names_from = all_of(dv$trtvar), values_from = value)

ttl <- tfl_titles(num = "14.4.1.1", type = "Table",
   text = "Summary of Plasma Pharmacokinetic Parameters by Dose Cohort and Dosing Day",
   pop  = "Pharmacokinetic Parameter Population",
   foot = paste("CV% arithmetic; Geo CV% = 100*sqrt(exp(s^2_log)-1). Geometric stats on log scale.",
                "Tmax / Tmax,ss: Median (Min, Max). N excludes BLQ-driven non-estimable parameters.",
                "MAD: Day 1 = single-dose parameters; Day N = steady-state parameters",
                "(AUCtau, Cmax,ss, Cmin,ss, Ctrough, CL/F,ss). Accumulation ratios (Rac)",
                "in t_accumulation.R. Column = dose cohort (TRT01A), placebo pooled."))

## rtables: split_rows_by(AVISIT) -> split_rows_by(PARAM) -> analyze(stat rows)
print(tab)
