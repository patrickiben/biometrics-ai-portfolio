################################################################################
# TABLE     : t_ada_impact_pk  (Single-/Fixed-Sequence DDI)
# TITLE     : Impact of Anti-Drug Antibody (ADA) Status on Plasma PK Exposure by
#             Period
# POPULATION: PK Population (PKFL == "Y") with ADA result (ADA-evaluable)
# INPUT     : ADPP (PARAMCD = CMAX, AUCLST, AUCIFO, TMAX; AVAL; APERIOD/APERIODC),
#             ADIS (per-PERIOD ADA status via ADAEMFL, matched on USUBJID+APERIOD)
# NOTE      : PSEUDOCODE. DESCRIPTIVE ONLY (matches the SAS twin -- no inferential
#             model). Column = fixed PERIOD (APERIODC; Period 1 = reference,
#             subsequent period(s) = test); within each period, exposure PK
#             parameters summarized by ADA status (positive vs negative). ADA
#             status is matched PER PERIOD (a participant may be ADA-positive in
#             the test period but negative in the reference period) using the
#             ADaM treatment-emergent flag ADAEMFL, NOT a single participant-level
#             label. Geometric stats ON THE LOG scale via pkstats() (never
#             exp(mean(raw))). Tmax = Median (Min, Max) only. Subgroup n typically
#             small -> interpret with caution.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SINGLESEQ")                 # byperiod = c("APERIOD","APERIODC")
options(tfl.study = env$study)
perN <- dv$byperiod[1]; perC <- dv$byperiod[2]  # numeric + character period

## --- per-PERIOD treatment-emergent ADA status from ADIS (matched USUBJID+APERIOD)
## ADA enters PER PERIOD (carry APERIOD) so a single participant-level label does
## not contaminate both period columns. Use ADaM flag ADAEMFL (same as SAS).
ada_status <- adam$adis %>% filter(ADAFL == "Y") %>%
  group_by(USUBJID, APERIOD) %>%
  summarise(ada_em = any(toupper(ADAEMFL) == "Y", na.rm = TRUE), .groups = "drop") %>%
  mutate(ADA = if_else(ada_em, "ADA-positive", "ADA-negative"))

## --- exposure params; merge per-PERIOD ADA status onto each PK record -----------
pp <- adam$adpp %>%
  filter(PKFL == "Y", PARAMCD %in% c("CMAX","AUCLST","AUCIFO","TMAX")) %>%
  left_join(ada_status, by = c("USUBJID", "APERIOD")) %>%  # per-period match
  mutate(per    = .data[[perC]],                  # Period 1 ref / Period 2 test+perp
         ADA    = coalesce(ADA, "ADA status unknown"),
         tmaxfl = PARAMCD == "TMAX")              # Tmax -> median (min,max) only

## ===========================================================================
## DESCRIPTIVE: geometric exposure by PERIOD x ADA status (geo stats on log scale)
## ===========================================================================
by <- c("per", "PARAMCD", "PARAM", "ADA")
gx <- pkstats(pp %>% filter(!tmaxfl, AVAL > 0), var = "AVAL", by = by) %>%
  transmute(per, PARAM, ADA,
            `n`         = as.character(n),
            `Mean`      = sprintf("%.3g", mean),
            `SD`        = sprintf("%.3g", sd),
            `CV%`       = sprintf("%.1f", cv),
            `Geo Mean`  = sprintf("%.3g", geomean),
            `Geo CV%`   = sprintf("%.1f", geocv),
            `Median`    = sprintf("%.3g", median),
            `Min, Max`  = sprintf("%.3g, %.3g", min, max)) %>%
  pivot_longer(c(`n`,`Mean`,`SD`,`CV%`,`Geo Mean`,`Geo CV%`,`Median`,`Min, Max`),
               names_to = "stat", values_to = "value")

## --- Tmax: Median (Min, Max) only -------------------------------------------
tmax_tab <- pp %>% filter(tmaxfl) %>%
  group_by(per, PARAM, ADA) %>%
  summarise(value = sprintf("%.2f (%.2f, %.2f)",
                            median(AVAL, na.rm = TRUE),
                            min(AVAL, na.rm = TRUE),
                            max(AVAL, na.rm = TRUE)),
            .groups = "drop") %>%
  mutate(stat = "Median (Min, Max)")

desc_tab <- bind_rows(gx, tmax_tab) %>%
  unite("colkey", per, ADA, sep = " | ", remove = FALSE) %>%
  select(PARAM, stat, colkey, value) %>%
  pivot_wider(names_from = colkey, values_from = value)

ttl <- tfl_titles(num = "14.5.2.1", type = "Table",
   text = "Impact of Anti-Drug Antibody (ADA) Status on Plasma PK Exposure by Period",
   pop  = "Pharmacokinetic Population with ADA Result",
   foot = paste("Single-fixed-sequence DDI: Period 1 = reference (victim alone),",
                "subsequent period(s) = test (victim + perpetrator). Exposure",
                "parameters summarized by ADA status (positive/negative) within",
                "each fixed period; ADA status matched PER PERIOD (ADAEMFL,",
                "treatment-emergent). Geo stats on the log scale (exp(mean(log)),",
                "Geo CV% = 100*sqrt(exp(var(log))-1)). Tmax: Median (Min, Max).",
                "DESCRIPTIVE subgroup comparison (no inferential test); subgroup n",
                "may be small -- interpret with caution."))

## render: param blocks (rows = statistics) x [period x ADA status] columns
print(desc_tab)
