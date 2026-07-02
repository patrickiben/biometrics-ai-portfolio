################################################################################
# FIGURE    : f_pk_conc_mean  (Crossover - 2x2 or Williams)
# TITLE     : Mean (+/- SD) Plasma Drug Concentration vs Time by Treatment
#             (Linear and Semilog)
# POPULATION: PK Concentration Population (PKFL == "Y")
# INPUT     : ADPC (AVAL = concentration; ATPTN nominal time; APERIOD; TRTA)
# NOTE      : PSEUDOCODE. Mean +/- SD concentration-time profile, one curve per
#             treatment, overlaid (within-participant crossover -> compare TRTA
#             profiles directly). Two panels: linear y and semilog (log10) y.
#             LINEAR panel = arithmetic mean +/- SD; SEMILOG panel = geometric
#             mean (exp(mean(log AVAL)) over AVAL>0, no SD whiskers) on the log10
#             axis, per PK convention. BLQ -> 0 for the linear arithmetic mean and
#             n (PK profile convention); those BLQ-as-0 rows then drop out of the
#             semilog/geometric panel via the >0 filter. Per-analyte (PARAMCD).
#             Nominal time on x (ATPTN).
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("CROSSOVER")                 # TRTA + APERIOD + TRTSEQP

pc <- adam$adpc %>%
  filter(PKFL == "Y", !is.na(ATPTN)) %>%        # drop missing nominal time
  mutate(
    trt  = .data[[dv$trtvar]],                  # actual treatment = curve grouping
    AVAL = if_else(!is.na(AVALC) & toupper(AVALC) == "BLQ", 0, AVAL))  # BLQ -> 0

## --- arithmetic mean +/- SD per treatment x analyte x nominal time (linear) ---
arith <- pc %>%
  group_by(PARAMCD, trt, ATPTN) %>%
  summarise(
    n    = sum(!is.na(AVAL)),
    mean = mean(AVAL, na.rm = TRUE),
    sd   = sd(AVAL,   na.rm = TRUE),
    .groups = "drop") %>%
  mutate(lo = pmax(mean - sd, 0), hi = mean + sd) %>%   # clamp lower whisker at 0
  arrange(PARAMCD, trt, ATPTN)

## --- geometric mean per treatment x analyte x nominal time (semilog, log scale)
## pkstats geo on the log scale (>0 only) so BLQ-as-0 rows drop out; plot on log10 y.
geo <- pkstats(pc, var = "AVAL", by = c("PARAMCD", "trt", "ATPTN")) %>%
  select(PARAMCD, trt, ATPTN, geomean) %>%
  arrange(PARAMCD, trt, ATPTN)

## --- linear panel ---------------------------------------------------------
p_lin <- ggplot(arith, aes(ATPTN, mean, colour = trt, group = trt)) +
  geom_line() +
  geom_point() +
  geom_errorbar(aes(ymin = lo, ymax = hi), width = 0.4, alpha = 0.6) +
  labs(x = "Nominal Time Post-Dose (h)", y = "Mean (+/- SD) Concentration",
       colour = "Treatment", title = "Linear") +
  theme_bw()

## --- semilog panel (geometric mean, log10 y) ------------------------------
p_log <- ggplot(geo %>% filter(geomean > 0),
                aes(ATPTN, geomean, colour = trt, group = trt)) +
  geom_line() +
  geom_point() +
  scale_y_log10() +
  labs(x = "Nominal Time Post-Dose (h)", y = "Geometric Mean Concentration (log scale)",
       colour = "Treatment", title = "Semilog") +
  theme_bw()

ttl <- tfl_titles(num = "14.4.2.1", type = "Figure",
   text = "Mean (+/- SD) Plasma Drug Concentration vs Time by Treatment (Linear and Semilog)",
   pop  = "Pharmacokinetic Concentration Population",
   foot = paste("Linear panel: arithmetic mean +/- SD (BLQ set to 0; lower whisker clamped at 0).",
                "Semilog panel: geometric mean on log scale (concentrations > 0).",
                "Curves grouped by actual treatment (TRTA), overlaid across periods. Nominal sampling times."))

## render: patchwork::wrap_plots(p_lin, p_log) or cowplot::plot_grid; add titles
## as caption/subtitle from ttl. ggsave(file.path(env$out, "f_pk_conc_mean.png"), ...)
print(p_lin)
print(p_log)
