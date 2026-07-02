################################################################################
# TABLE     : t_pk_conc_summary  (Parallel-group / per-dose)
# TITLE     : Summary of Plasma Concentrations by Treatment, Nominal Time
# POPULATION: PK Concentration Population (PKFL == "Y")
# INPUT     : ADPC (PARAMCD = analyte concentration; ATPTN nominal sampling time)
# NOTE      : PSEUDOCODE. n, Mean, SD, CV%, Geo Mean, Geo CV%, Median, Min, Max
#             per treatment x nominal time. Geometric stats on the LOG scale
#             (pkstats). BLQ handled per SOP (count + rule), excluded from geo
#             stats (x > 0). Column = TRT01A = dose level (parallel = one trt /
#             participant). Descriptive only -- no between-group inferential test.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("PARALLEL")                 # column = TRT01A (= dose)

## --- analysis records: PK conc population, scheduled timepoints -------------
pc <- adam$adpc %>%
  filter(PKFL == "Y", ANL01FL == "Y") %>%               # primary analysis records
  mutate(blq = (AVAL <= 0 | toupper(coalesce(AVALC, "")) == "BLQ"))
by <- c(dv$trtvar, "PARAM", "ATPTN", "ATPT")            # treatment x analyte x nominal time

## --- BLQ accounting (reported separately; per SOP first/middle/last rule) ---
blq_n <- pc %>% group_by(across(all_of(by))) %>%
  summarise(n_total = n_distinct(USUBJID),
            n_blq   = sum(blq), .groups = "drop")

## --- descriptive + geometric stats on quantifiable values (x > 0) ----------
## pkstats() filters AVAL > 0 internally and computes geo stats on the log scale
cont <- pkstats(pc, var = "AVAL", by = by) %>%
  left_join(blq_n, by = by) %>%
  transmute(across(all_of(by)),
            `n`          = as.character(n),
            `Mean (SD)`  = sprintf("%.3g (%.3g)", mean, sd),
            `CV%`        = sprintf("%.1f", cv),
            `Geo Mean`   = sprintf("%.3g", geomean),
            `Geo CV%`    = sprintf("%.1f", geocv),
            `Median`     = sprintf("%.3g", median),
            `Min, Max`   = sprintf("%.3g, %.3g", min, max),
            `n BLQ`      = sprintf("%d/%d", coalesce(n_blq, 0L), coalesce(n_total, 0L)))

## --- stat rows x treatment cols, blocked by analyte then nominal time -------
tab <- cont %>%
  pivot_longer(c(`n`,`Mean (SD)`,`CV%`,`Geo Mean`,`Geo CV%`,`Median`,`Min, Max`,`n BLQ`),
               names_to = "stat", values_to = "value") %>%
  mutate(stat = factor(stat, levels = c("n","Mean (SD)","CV%","Geo Mean","Geo CV%",
                                        "Median","Min, Max","n BLQ"))) %>%
  arrange(PARAM, ATPTN, stat) %>%
  select(PARAM, ATPT, stat, all_of(dv$trtvar), value) %>%
  pivot_wider(names_from = all_of(dv$trtvar), values_from = value)

ttl <- tfl_titles(num = "14.4.1.2", type = "Table",
   text = "Summary of Plasma Concentrations by Treatment and Nominal Sampling Time",
   pop  = "Pharmacokinetic Concentration Population",
   foot = paste("Geo CV% = 100*sqrt(exp(s^2_log)-1); geometric stats on log scale,",
                "BLQ excluded. CV% arithmetic. Concentrations summarized by nominal time;",
                "actual times used for parameter derivation. Column = dose level."))

## rtables: split_rows_by(PARAM) -> split_rows_by(ATPT) -> analyze(stat rows)
print(tab)
