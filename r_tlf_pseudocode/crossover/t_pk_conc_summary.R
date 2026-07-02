################################################################################
# TABLE     : t_pk_conc_summary  (Crossover - 2x2 or Williams)
# TITLE     : Summary of Plasma Drug Concentrations by Treatment and
#             Nominal Time Point
# POPULATION: PK Concentration Population (PKFL == "Y")
# INPUT     : ADPC (AVAL = concentration; ATPTN/ATPT = nominal time; APERIOD)
# NOTE      : PSEUDOCODE. Concentration summary by treatment x nominal time:
#             n, Mean, SD, CV%, Geo Mean, Geo CV%, Median, Min, Max. Geometric
#             stats ON THE LOG SCALE via pkstats() (x > 0 only). Crossover:
#             treatment column = dv$trtvar (TRTA, the actual treatment received
#             that period) so each TRTA column aggregates the same drug across
#             whichever period participants received it in. BLQ handling per SAP
#             (e.g. pre-dose BLQ -> 0, embedded BLQ -> 1/2 LLOQ) is assumed
#             already applied upstream in ADPC; non-numeric/BLQ rows excluded
#             from geometric stats by the x > 0 guard.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("CROSSOVER")                 # TRTA + APERIOD + TRTSEQP

## --- concentration analysis records --------------------------------------
## Keep PK-evaluable rows; ATPTN is the numeric nominal-time sort key, ATPT the
## display label. Treatment column is the ACTUAL treatment (dv$trtvar = TRTA),
## NOT the planned sequence, so a given drug's profile pools across periods.
pc <- adam$adpc %>%
  filter(PKFL == "Y", !is.na(ATPTN)) %>%
  mutate(trt = .data[[dv$trtvar]])

by <- c("trt", "ATPTN", "ATPT")

## --- descriptive + geometric stats (pkstats -> log scale, x > 0) ----------
## pkstats() filters AVAL > 0 internally; BLQ-as-0 rows therefore drop out of
## geometric stats (expected). n here = n contributing to geo stats.
cont <- pkstats(pc, var = "AVAL", by = by) %>%
  transmute(
    trt, ATPTN, ATPT,
    n           = as.character(n),
    `Mean (SD)` = sprintf("%.3g (%.3g)", mean, sd),
    `CV%`       = sprintf("%.1f", cv),
    `Geo Mean`  = sprintf("%.3g", geomean),
    `Geo CV%`   = sprintf("%.1f", geocv),
    `Median`    = sprintf("%.3g", median),
    `Min, Max`  = sprintf("%.3g, %.3g", min, max))

## --- n scheduled / n BLQ per cell (reporting context, optional row) --------
## Report the full denominator (scheduled samples) alongside the geo-stat n so a
## reader can see how many were BLQ. Distinct participants per treatment x timepoint.
counts <- pc %>%
  group_by(trt, ATPTN, ATPT) %>%
  summarise(
    n_sched = n_distinct(USUBJID),
    n_blq   = sum(AVAL <= 0 | is.na(AVAL)),
    .groups = "drop") %>%
  transmute(trt, ATPTN, ATPT,
            `n (sched)` = as.character(n_sched),
            `n BLQ`     = as.character(n_blq))

## --- assemble: rows = timepoint x stat, columns = treatment ---------------
long <- cont %>%
  left_join(counts, by = c("trt", "ATPTN", "ATPT")) %>%
  arrange(ATPTN, trt) %>%
  pivot_longer(
    cols = c(`n (sched)`, `n`, `n BLQ`, `Mean (SD)`, `CV%`,
             `Geo Mean`, `Geo CV%`, `Median`, `Min, Max`),
    names_to = "stat", values_to = "value") %>%
  mutate(stat = factor(stat, levels = c(
    "n (sched)", "n", "n BLQ", "Mean (SD)", "CV%",
    "Geo Mean", "Geo CV%", "Median", "Min, Max")))

tab <- long %>%
  select(ATPTN, ATPT, stat, trt, value) %>%
  pivot_wider(names_from = trt, values_from = value) %>%
  arrange(ATPTN, stat)

ttl <- tfl_titles(num = "14.4.1.1", type = "Table",
   text = "Summary of Plasma Drug Concentrations by Treatment and Nominal Time",
   pop  = "Pharmacokinetic Concentration Population",
   foot = paste("Geometric stats on the log scale (concentrations > 0 only);",
                "Geo CV% = 100*sqrt(exp(s^2_log)-1). Treatment = actual treatment received (TRTA).",
                "BLQ samples handled per SAP upstream; n BLQ shown for context."))

## render: rtables (split_rows_by ATPT then analyze stat) or gt grouped by time
print(tab)
