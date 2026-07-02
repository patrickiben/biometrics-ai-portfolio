################################################################################
# TABLE     : t_pk_param_by_period  (Crossover - 2x2 or Williams)
# TITLE     : Summary of Plasma PK Parameters by Treatment and Period
# POPULATION: PK Parameter Population (PKFL == "Y")
# INPUT     : ADPP (PARAMCD/PARAM; AVAL; TRTA; APERIOD/APERIODC) ;
#             ADEX (per-period dosing -> denominators)
# NOTE      : PSEUDOCODE. Descriptive PK parameter summary cross-classified by
#             TREATMENT x PERIOD -- the diagnostic that exposes a potential
#             PERIOD EFFECT (e.g. carryover / time trend) ahead of the formal
#             mixed model in t_be_anova.R, where period is a fixed effect.
#             Crossover-specific because parameters are summarised within each
#             APERIOD, not pooled. House rule: PER-PERIOD denominators come from
#             a PERIOD-BEARING source (ADEX participants dosed per APERIOD with
#             SAFFL=="Y") -- NEVER from one-row-per-participant ADSL. Geometric
#             stats on the LOG scale; Tmax = Median (Min, Max) ONLY.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("CROSSOVER")                 # TRTA + APERIOD/APERIODC

## --- per-period denominators from ADEX (period-bearing), NOT ADSL ----------
## Participants actually dosed in each treatment x period; SAFFL == "Y". This is the
## N for the column header / context, keyed on the SAME period variable as ADPP.
denom <- adam$adex %>%
  filter(SAFFL == "Y") %>%
  group_by(trt = .data[[dv$trtvar]], APERIOD, APERIODC) %>%
  summarise(N = n_distinct(USUBJID), .groups = "drop")

## --- PK parameter records, summarised WITHIN period -----------------------
pp <- adam$adpp %>%
  filter(PKFL == "Y") %>%
  mutate(trt = .data[[dv$trtvar]])
by <- c("trt", "APERIOD", "APERIODC", "PARAMCD", "PARAM")

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

## --- build column key = treatment + period; attach N to the header label --
hdr <- denom %>%
  mutate(col = sprintf("%s / %s (N=%d)", trt, APERIODC, N)) %>%
  select(trt, APERIOD, col)

tab <- bind_rows(cont, tmax) %>%
  left_join(hdr, by = c("trt", "APERIOD")) %>%
  arrange(PARAM, APERIOD, trt) %>%
  select(PARAM, stat, col, value) %>%
  pivot_wider(names_from = col, values_from = value)

ttl <- tfl_titles(num = "14.4.4.3", type = "Table",
   text = "Summary of Plasma Pharmacokinetic Parameters by Treatment and Period",
   pop  = "Pharmacokinetic Parameter Population",
   foot = paste("Parameters summarised WITHIN period to screen for period/carryover effects;",
                "the formal test (period as fixed effect) is in t_be_anova.R.",
                "Per-period N = participants dosed per APERIOD from ADEX (SAFFL=Y), not ADSL.",
                "Geometric stats on the log scale; Tmax = Median (Min, Max)."))

## render: rtables split_rows_by PARAM -> analyze stat, columns = treatment/period
print(tab)
