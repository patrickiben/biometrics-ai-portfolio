################################################################################
# TABLE     : t_ada_impact_pk  (Crossover - 2x2 or Williams)
# TITLE     : Impact of Anti-Drug Antibody Status on Plasma PK Exposure by
#             Treatment
# POPULATION: PK Parameter Population (PKFL=="Y") with an ADA status on ADIS
# INPUT     : ADPP (PARAMCD = CMAX, AUCLST, AUCIFO; AVAL) + ADIS (per-treatment
#             treatment-emergent ADA status) ; TRTA / APERIOD / TRTSEQP
# NOTE      : PSEUDOCODE. Compares exposure between treatment-emergent ADA-positive
#             vs ADA-negative participants, WITHIN each treatment (crossover -> status
#             is treatment/period-specific). PK summarised with GEOMETRIC stats on
#             the LOG scale via pkstats() (geomean = exp(mean(log)), geo CV% =
#             100*sqrt(exp(var(log))-1)); Tmax handled as Median (Min, Max) only
#             elsewhere and excluded here. Descriptive only -> small ADA-positive
#             n typical in early phase; no formal test unless SAP specifies.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("CROSSOVER")                 # TRTA + APERIOD + TRTSEQP

## --- per-participant x per-treatment treatment-emergent ADA status from ADIS ----
## key the merge on USUBJID + treatment so the crossover status follows the
## period in which each treatment was received (TRTEMFL = treatment-emergent).
ada_status <- adam$adis %>%
  filter(ADAFL == "Y", PARAMCD == "ADA") %>%    # ADA-evaluable participants; ADA assay
  mutate(trt = .data[[dv$trtvar]]) %>%
  group_by(USUBJID, trt) %>%
  summarise(ada_grp = if_else(any(TRTEMFL == "Y", na.rm = TRUE),
                              "TE ADA-Positive", "ADA-Negative"),
            .groups = "drop")

## --- PK exposure parameters, joined to per-treatment ADA group --------------
pp <- adam$adpp %>%
  filter(PKFL == "Y", PARAMCD %in% c("CMAX","AUCLST","AUCIFO"), AVAL > 0) %>%
  mutate(trt = .data[[dv$trtvar]]) %>%
  left_join(ada_status, by = c("USUBJID", "trt")) %>%
  mutate(ada_grp = coalesce(ada_grp, "ADA-Negative"))   # no ADA record -> negative

## --- geometric PK stats by treatment x ADA group x parameter (log scale) ----
by  <- c("trt", "ada_grp", "PARAMCD", "PARAM")
gp  <- pkstats(pp, var = "AVAL", by = by) %>%
  transmute(
    Treatment   = trt,
    `ADA Group` = ada_grp,
    Parameter   = PARAM,
    n           = as.character(n),
    `Geo Mean`  = sprintf("%.3g", geomean),
    `Geo CV%`   = sprintf("%.1f", geocv),
    `Median`    = sprintf("%.3g", median),
    `Min, Max`  = sprintf("%.3g, %.3g", min, max))

## --- optional descriptive GMR (ADA-pos / ADA-neg) within treatment ----------
## ratio of geometric means; report only when both groups have n >= SAP minimum.
gmr <- pkstats(pp, var = "AVAL", by = by) %>%
  select(trt, ada_grp, PARAM, geomean, n) %>%
  pivot_wider(names_from = ada_grp, values_from = c(geomean, n)) %>%
  mutate(`GMR (Pos/Neg) %` = if_else(
           !is.na(`n_TE ADA-Positive`) & `n_TE ADA-Positive` >= 3 & !is.na(`n_ADA-Negative`),
           sprintf("%.1f", 100 * `geomean_TE ADA-Positive` / `geomean_ADA-Negative`),
           "NC"))

ttl <- tfl_titles(num = "14.5.2.1", type = "Table",
   text = "Impact of Treatment-Emergent ADA Status on Plasma PK Exposure by Treatment",
   pop  = "PK Parameter Population with ADA Status",
   foot = paste("Geometric statistics on the log scale (Geo Mean = exp(mean(ln)); Geo CV% = 100*sqrt(exp(var(ln))-1)).",
                "ADA status is treatment/period-specific (crossover): joined on participant + treatment from ADIS.",
                "Participants without an ADA record are classified ADA-Negative. Descriptive only; GMR = NC when ADA-positive n < 3."))

print(gp)
print(gmr)
