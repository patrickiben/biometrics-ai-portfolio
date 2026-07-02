################################################################################
# TABLE     : t_ada_summary  (Crossover - 2x2 or Williams)
# TITLE     : Summary of Anti-Drug Antibody (ADA) Incidence by Treatment and
#             Period
# POPULATION: ADA-Evaluable Population (participants with >=1 ADA result on ADIS)
# INPUT     : ADIS (PARAMCD = ADA / NAB status; AVALC = Positive/Negative;
#             ABLFL baseline flag; APERIOD/APERIODC; TRTA; TRTSEQP)
# NOTE      : PSEUDOCODE. Incidence = DISTINCT PARTICIPANTS (n_distinct(USUBJID)),
#             never row counts. Denominator = ADA-evaluable participants PER TREATMENT
#             and PER PERIOD taken from ADIS (period-bearing source), NOT ADSL.
#             Categories follow the standard ADA cascade:
#               - Baseline ADA-positive (pre-existing)
#               - Treatment-induced (baseline neg -> post-baseline pos)
#               - Treatment-boosted (baseline pos -> >= titer-fold rise)
#               - Treatment-emergent = induced + boosted
#               - NAb-positive among ADA-positive
#             Crossover: report by TRTA so each treatment's emergence is separable;
#             washout makes a participant ADA-status carry-over a key footnote.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("CROSSOVER")                 # TRTA + APERIOD + TRTSEQP

## --- ADA-evaluable records (binding ADA assay) ------------------------------
ada <- adam$adis %>%
  filter(ADAFL == "Y", PARAMCD == "ADA") %>%   # ADA-evaluable participants; ADA assay
  mutate(trt    = .data[[dv$trtvar]],
         pos    = toupper(AVALC) == "POSITIVE")

## --- per-treatment ADA-evaluable denominator from ADIS (NOT ADSL) -----------
denom <- ada %>%
  group_by(trt) %>%
  summarise(N = n_distinct(USUBJID), .groups = "drop") %>%
  bind_rows(tibble(trt = "Total", N = n_distinct(ada$USUBJID)))

## --- participant-level ADA status per treatment (baseline vs post-baseline) -----
## ADIS carries the emergent classification; if not, derive from baseline +
## post-baseline status and the titer-fold rule. Use ADaM flags when present:
##   TRTEMFL = treatment-emergent ADA ; the boosted/induced split via ABLFL.
status <- ada %>%
  group_by(trt, USUBJID) %>%
  summarise(
    base_pos = any(ABLFL == "Y" & pos, na.rm = TRUE),
    post_pos = any(ABLFL != "Y" & pos, na.rm = TRUE),
    emergent = any(TRTEMFL == "Y", na.rm = TRUE),     # ADaM-flagged TE-ADA
    .groups = "drop") %>%
  mutate(induced = !base_pos &  post_pos,
         boosted =  base_pos &  emergent)

## --- NAb-positive among ADA-positive (neutralizing assay on ADIS) -----------
nab <- adam$adis %>%
  filter(PARAMCD == "NAB", toupper(AVALC) == "POSITIVE") %>%
  mutate(trt = .data[[dv$trtvar]]) %>%
  group_by(trt) %>%
  summarise(nab_pos = n_distinct(USUBJID), .groups = "drop")

## --- count DISTINCT PARTICIPANTS per category, n (%) with bign-style denom ------
cat_counts <- status %>%
  group_by(trt) %>%
  summarise(
    `Baseline ADA-positive`     = n_distinct(USUBJID[base_pos]),
    `Treatment-induced ADA`     = n_distinct(USUBJID[induced]),
    `Treatment-boosted ADA`     = n_distinct(USUBJID[boosted]),
    `Treatment-emergent ADA`    = n_distinct(USUBJID[induced | boosted]),
    .groups = "drop") %>%
  left_join(nab, by = "trt") %>%
  left_join(denom, by = "trt") %>%
  pivot_longer(c(`Baseline ADA-positive`, `Treatment-induced ADA`,
                 `Treatment-boosted ADA`, `Treatment-emergent ADA`),
               names_to = "Category", values_to = "n") %>%
  mutate(disp = n_pct(n, N)) %>%                 # n (xx.x%) on per-treatment N
  select(trt, Category, disp) %>%
  pivot_wider(names_from = trt, values_from = disp)

ttl <- tfl_titles(num = "14.5.1.1", type = "Table",
   text = "Summary of Anti-Drug Antibody Incidence by Treatment",
   pop  = "ADA-Evaluable Population",
   foot = paste("Counts = distinct participants; % denominator = ADA-evaluable participants per treatment from ADIS.",
                "Treatment-induced = baseline negative to post-baseline positive; treatment-boosted =",
                "baseline positive with protocol-defined titer-fold rise; emergent = induced + boosted.",
                "Crossover: a participant ADA-positive in an earlier period may carry status across washout (see SAP)."))

print(cat_counts)
