################################################################################
# TABLE     : t_pk_conc_summary  (Single-/fixed-sequence DDI)
# TITLE     : Summary of Plasma Concentrations of the Victim Drug by Period
#             (Reference vs Test) and Nominal Time Point
# POPULATION: PK Concentration Population (PKFL == "Y")
# INPUT     : ADPC (AVAL = concentration; ATPTN/ATPT = nominal time; APERIOD)
# NOTE      : PSEUDOCODE. n, Mean, SD, CV%, Geo Mean, Geo CV%, Median, Min, Max
#             per PERIOD x nominal time. Geometric stats ON THE LOG SCALE via
#             pkstats() (x > 0 only). Single-/fixed-sequence DDI: there is NO
#             randomized sequence, so concentrations are summarised by study
#             PERIOD -- Period 1 = victim alone (reference), Period 2 = victim +
#             perpetrator (test). The treatment column is therefore the PERIOD
#             (dv$byperiod), not a sequence. BLQ handling (pre-dose BLQ -> 0,
#             embedded BLQ -> 1/2 LLOQ) is assumed applied upstream in ADPC; the
#             x > 0 guard drops BLQ rows from geometric stats.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SINGLESEQ")                 # period via dv$byperiod (no sequence)

## --- concentration analysis records --------------------------------------
## Single-sequence: aggregate by study PERIOD (reference vs test), keyed on the
## SAME period variable carried on ADPP/ADPC. ATPTN = numeric nominal-time sort
## key; ATPT = display label.
pc <- adam$adpc %>%
  filter(PKFL == "Y", !is.na(ATPTN)) %>%
  mutate(period  = .data[[dv$byperiod[1]]],     # APERIOD numeric sort key
         periodc = .data[[dv$byperiod[2]]])      # APERIODC label (Reference/Test)

by <- c("period", "periodc", "PARAM", "ATPTN", "ATPT")

## --- descriptive + geometric stats (pkstats -> log scale, x > 0) ----------
cont <- pkstats(pc, var = "AVAL", by = by) %>%
  transmute(across(all_of(by)),
            n           = as.character(n),
            `Mean (SD)` = sprintf("%.3g (%.3g)", mean, sd),
            `CV%`       = sprintf("%.1f", cv),
            `Geo Mean`  = sprintf("%.3g", geomean),
            `Geo CV%`   = sprintf("%.1f", geocv),
            `Median`    = sprintf("%.3g", median),
            `Min, Max`  = sprintf("%.3g, %.3g", min, max))

## --- n scheduled / n BLQ per cell (reporting context) ----------------------
## Full denominator (scheduled samples) alongside the geo-stat n so the reader
## sees how many were BLQ. Distinct participants per period x timepoint.
counts <- pc %>%
  group_by(across(all_of(by))) %>%
  summarise(n_sched = n_distinct(USUBJID),
            n_blq   = sum(AVAL <= 0 | is.na(AVAL) |
                          toupper(coalesce(AVALC, "")) == "BLQ"),
            .groups = "drop") %>%
  transmute(across(all_of(by)),
            `n (sched)` = as.character(n_sched),
            `n BLQ`     = as.character(n_blq))

## --- assemble: rows = analyte x timepoint x stat, columns = PERIOD ---------
long <- cont %>%
  left_join(counts, by = by) %>%
  pivot_longer(c(`n (sched)`,`n`,`n BLQ`,`Mean (SD)`,`CV%`,`Geo Mean`,
                 `Geo CV%`,`Median`,`Min, Max`),
               names_to = "stat", values_to = "value") %>%
  mutate(stat = factor(stat, levels = c("n (sched)","n","n BLQ","Mean (SD)","CV%",
                                        "Geo Mean","Geo CV%","Median","Min, Max"))) %>%
  arrange(PARAM, ATPTN, period, stat)

tab <- long %>%
  select(PARAM, ATPT, stat, periodc, value) %>%
  pivot_wider(names_from = periodc, values_from = value)   # columns = Reference / Test period

ttl <- tfl_titles(num = "14.4.1.1", type = "Table",
   text = "Summary of Plasma Concentrations of the Victim Drug by Period and Nominal Time",
   pop  = "Pharmacokinetic Concentration Population",
   foot = paste("Geometric stats on the log scale (concentrations > 0 only);",
                "Geo CV% = 100*sqrt(exp(s^2_log)-1). Columns = study PERIOD:",
                "Period 1 = victim alone (reference), Period 2 = victim + perpetrator (test).",
                "Fixed-sequence design -- no randomized sequence. BLQ handled per SAP upstream."))

## render: rtables split_rows_by(PARAM) -> split_rows_by(ATPT) -> analyze(stat)
print(tab)
