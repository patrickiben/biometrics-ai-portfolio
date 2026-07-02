################################################################################
# TABLE     : t_pk_param_by_period  (Single-/fixed-sequence DDI)
# TITLE     : Summary of Plasma PK Parameters of the Victim Drug by Period
#             (with Per-Period Dosed N)
# POPULATION: PK Parameter Population (PKFL == "Y")
# INPUT     : ADPP (PARAMCD/PARAM; AVAL; APERIOD/APERIODC) ;
#             ADEX (per-period dosing -> denominators)
# NOTE      : PSEUDOCODE. Descriptive PK parameter summary by study PERIOD --
#             Period 1 = victim alone (reference), Period 2 = victim + perpetrator
#             (test). In a single-/fixed-sequence DDI there is NO randomized
#             sequence, so PERIOD is the only by-structure and it carries the
#             treatment contrast. This table is the diagnostic that screens for a
#             PERIOD / time-trend effect, which -- because the design has no
#             sequence term -- is CONFOUNDED with the DDI effect in the formal
#             ratio model (t_be_anova.R). House rule: PER-PERIOD denominators come
#             from a PERIOD-BEARING source (ADEX participants dosed per APERIOD with
#             SAFFL=="Y") -- NEVER from one-row-per-participant ADSL. Geometric stats
#             on the LOG scale; Tmax = Median (Min, Max) ONLY.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SINGLESEQ")                 # by-structure = study PERIOD

## --- per-period denominators from ADEX (period-bearing), NOT ADSL ----------
## Participants actually dosed in each study period; SAFFL == "Y". This is the N for
## the column header / context, keyed on the SAME period variable as ADPP.
denom <- adam$adex %>%
  filter(SAFFL == "Y") %>%
  group_by(period = .data[[dv$byperiod[1]]],
           periodc = .data[[dv$byperiod[2]]]) %>%
  summarise(N = n_distinct(USUBJID), .groups = "drop")

## --- PK parameter records, summarised WITHIN period -----------------------
pp <- adam$adpp %>%
  filter(PKFL == "Y") %>%
  mutate(period  = .data[[dv$byperiod[1]]],
         periodc = .data[[dv$byperiod[2]]])
by <- c("period", "periodc", "PARAMCD", "PARAM")

## non-Tmax: arithmetic + geometric (pkstats -> log scale, AVAL > 0)
cont <- pkstats(pp %>% filter(PARAMCD != "TMAX"), var = "AVAL", by = by) %>%
  transmute(across(all_of(by)),
            n           = as.character(n),
            `Mean (SD)` = sprintf("%.3g (%.3g)", mean, sd),
            `CV%`       = sprintf("%.1f", cv),
            `Geo Mean`  = sprintf("%.3g", geomean),
            `Geo CV%`   = sprintf("%.1f", geocv),
            `Median`    = sprintf("%.3g", median),
            `Min, Max`  = sprintf("%.3g, %.3g", min, max)) %>%
  pivot_longer(c(`n`,`Mean (SD)`,`CV%`,`Geo Mean`,`Geo CV%`,`Median`,`Min, Max`),
               names_to = "stat", values_to = "value")

## Tmax: Median (Min, Max) ONLY
tmax <- pp %>% filter(PARAMCD == "TMAX") %>%
  group_by(across(all_of(by))) %>%
  summarise(med = median(AVAL), min = min(AVAL), max = max(AVAL), .groups = "drop") %>%
  transmute(across(all_of(by)), stat = "Median (Min, Max)",
            value = sprintf("%.2f (%.2f, %.2f)", med, min, max))

## --- build column key = PERIOD; attach per-period dosed N to the header ----
hdr <- denom %>%
  mutate(col = sprintf("%s (N=%d)", periodc, N)) %>%
  select(period, col)

tab <- bind_rows(cont, tmax) %>%
  left_join(hdr, by = "period") %>%
  arrange(PARAM, period) %>%
  select(PARAM, stat, col, value) %>%
  pivot_wider(names_from = col, values_from = value)   # columns = Reference / Test period

ttl <- tfl_titles(num = "14.4.4.3", type = "Table",
   text = "Summary of Plasma Pharmacokinetic Parameters of the Victim Drug by Period",
   pop  = "Pharmacokinetic Parameter Population",
   foot = paste("Parameters summarised WITHIN study period; Period 1 = victim alone (reference),",
                "Period 2 = victim + perpetrator (test); fixed-sequence design (no randomized sequence).",
                "Per-period N = participants dosed per APERIOD from ADEX (SAFFL=Y), not ADSL.",
                "Period/time-trend is confounded with the DDI effect (no sequence term) -- the formal",
                "Test-vs-Reference ratio + 90% CI is in t_be_anova.R. Geometric stats on the log scale;",
                "Tmax = Median (Min, Max)."))

## render: rtables split_rows_by(PARAM) -> analyze(stat), columns = period
print(tab)
