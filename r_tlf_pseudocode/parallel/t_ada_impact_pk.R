################################################################################
# TABLE     : t_ada_impact_pk  (Parallel-group)
# TITLE     : Impact of Anti-Drug Antibody Status on Plasma PK Exposure by
#             Treatment
# POPULATION: PK Parameter + ADA-Evaluable Population (PKFL == "Y" and ADIS-
#             evaluable)
# INPUT     : ADPP (PARAMCD = CMAX, AUCLST, AUCIFO, ...), ADIS (participant-level
#             treatment-emergent ADA status)
# NOTE      : PSEUDOCODE. Cross-classifies PK exposure parameters by treatment
#             and treatment-emergent ADA status (ADA-positive vs ADA-negative).
#             Geometric stats ON THE LOG scale via pkstats() (geomean =
#             exp(mean(log)), geo CV% = 100*sqrt(exp(var(log))-1)) -- never
#             exp(mean(raw)). Descriptive only (subgroup n typically small);
#             no formal ADA x exposure test. Parallel-group: one treatment per
#             participant -> column = dv$trtvar (TRT01A, = dose for ascending-dose).
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("PARALLEL")

## --- participant-level treatment-emergent ADA status from ADIS (not re-derived) -
ada_status <- adam$adis %>% filter(ADAFL == "Y") %>%
  group_by(USUBJID) %>%
  summarise(ada_te = any(toupper(TEADAFL) == "Y", na.rm = TRUE), .groups = "drop") %>%
  mutate(ADA = if_else(ada_te, "ADA-positive", "ADA-negative"))

## --- exposure parameters; merge ADA status onto each participant's PK params ----
pp <- adam$adpp %>%
  filter(PKFL == "Y", PARAMCD %in% c("CMAX","AUCLST","AUCIFO")) %>%
  inner_join(ada_status, by = "USUBJID") %>%        # PK x ADA evaluable only
  mutate(trt = .data[[dv$trtvar]])

by <- c("trt", "PARAMCD", "PARAM", "ADA")

## --- geometric exposure stats on the LOG scale (pkstats) -------------------
gx <- pkstats(pp, var = "AVAL", by = by) %>%
  transmute(trt, PARAM, ADA,
            `n`         = as.character(n),
            `Geo Mean`  = sprintf("%.3g", geomean),
            `Geo CV%`   = sprintf("%.1f", geocv),
            `Median`    = sprintf("%.3g", median),
            `Min, Max`  = sprintf("%.3g, %.3g", min, max)) %>%
  pivot_longer(c(`n`,`Geo Mean`,`Geo CV%`,`Median`,`Min, Max`),
               names_to = "stat", values_to = "value")

## --- layout: parameter/stat rows x (treatment | ADA status) columns --------
tab <- gx %>%
  unite("colkey", trt, ADA, sep = " | ", remove = FALSE) %>%
  select(PARAM, stat, colkey, value) %>%
  pivot_wider(names_from = colkey, values_from = value)

ttl <- tfl_titles(num = "14.5.2.1", type = "Table",
   text = "Impact of Anti-Drug Antibody Status on Plasma PK Exposure by Treatment",
   pop  = "PK Parameter and ADA-Evaluable Population",
   foot = paste("Geometric mean / Geo CV% on the log scale (exp(mean(log)),",
                "100*sqrt(exp(var(log))-1)). ADA status = treatment-emergent (ADIS).",
                "Descriptive only; subgroup n may be small -- interpret with caution.",
                "No formal ADA x exposure statistical test."))

## rtables/gt rendering; parameter blocks, treatment x ADA-status columns
print(tab)
