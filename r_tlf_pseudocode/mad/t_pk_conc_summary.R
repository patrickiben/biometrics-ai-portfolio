################################################################################
# TABLE     : t_pk_conc_summary  (MAD - Multiple Ascending Dose / per-cohort)
# TITLE     : Summary of Plasma Concentrations by Dose Cohort, Day and Nominal Time
# POPULATION: PK Concentration Population (PKFL == "Y")
# INPUT     : ADPC (PARAMCD = analyte concentration; ADY/AVISIT dosing day;
#             ATPTN nominal sampling time within the dosing interval)
# NOTE      : PSEUDOCODE. n, Mean, SD, CV%, Geo Mean, Geo CV%, Median, Min, Max
#             per dose cohort x DOSING DAY x nominal time. Geometric stats on the
#             LOG scale (pkstats). BLQ counted + excluded from geo stats (x > 0).
#             MAD = parallel cohorts, REPEATED daily dosing: column = TRT01A =
#             dose level (one dose level / participant). Unlike SAD, profiles are
#             collected on >1 occasion (e.g. Day 1 single dose vs Day N at steady
#             state) -> day is a row-block so Day 1 vs Day N can be compared and
#             pre-dose troughs read across days. Placebo pooled. Descriptive only.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("MAD")                        # column = TRT01A (= dose cohort)

## --- analysis records: PK conc population, scheduled timepoints -------------
pc <- adam$adpc %>%
  filter(PKFL == "Y", ANL01FL == "Y") %>%                # primary analysis records
  mutate(blq = (AVAL <= 0 | toupper(coalesce(AVALC, "")) == "BLQ"))
## MAD row structure: dose cohort x analyte x dosing DAY x nominal time-in-interval.
## AVISIT/ADY identify the dosing occasion (Day 1, Day N=steady state); ATPTN is the
## nominal time relative to that day's dose (so a 24h tau profile reads cleanly).
by <- c(dv$trtvar, "PARAM", "AVISIT", "ADY", "ATPTN", "ATPT")

## --- BLQ accounting (reported separately; per SOP first/middle/last rule) ---
blq_n <- pc %>% group_by(across(all_of(by))) %>%
  summarise(n_total = n_distinct(USUBJID),
            n_blq   = sum(blq), .groups = "drop")

## --- descriptive + geometric stats on quantifiable values (x > 0) ----------
## pkstats() filters AVAL > 0 internally and computes geo stats on the LOG scale
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

## --- stat rows x dose-cohort cols, blocked by analyte -> day -> nominal time -
tab <- cont %>%
  pivot_longer(c(`n`,`Mean (SD)`,`CV%`,`Geo Mean`,`Geo CV%`,`Median`,`Min, Max`,`n BLQ`),
               names_to = "stat", values_to = "value") %>%
  mutate(stat = factor(stat, levels = c("n","Mean (SD)","CV%","Geo Mean","Geo CV%",
                                        "Median","Min, Max","n BLQ"))) %>%
  arrange(PARAM, ADY, ATPTN, stat) %>%
  select(PARAM, AVISIT, ATPT, stat, all_of(dv$trtvar), value) %>%
  pivot_wider(names_from = all_of(dv$trtvar), values_from = value)

ttl <- tfl_titles(num = "14.4.1.2", type = "Table",
   text = "Summary of Plasma Concentrations by Dose Cohort, Dosing Day and Nominal Time",
   pop  = "Pharmacokinetic Concentration Population",
   foot = paste("Geo CV% = 100*sqrt(exp(s^2_log)-1); geometric stats on log scale,",
                "BLQ excluded. CV% arithmetic. Concentrations summarized by nominal time",
                "within each dosing day; actual times used for parameter derivation.",
                "MAD: column = dose cohort (TRT01A), repeated daily dosing; Day 1 = single",
                "dose, Day N = steady state. Placebo pooled across cohorts per SAP."))

## rtables: split_rows_by(PARAM)->split_rows_by(AVISIT)->split_rows_by(ATPT)->analyze(stat rows)
print(tab)
