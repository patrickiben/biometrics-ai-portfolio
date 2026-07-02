################################################################################
# FIGURE    : f_pkpd_overlay  (Single Ascending Dose)
# TITLE     : Mean Plasma Concentration and Pharmacodynamic Response over Time
#             by Dose Level (Dual-Axis Overlay)
# POPULATION: PK + PD-Evaluable Population (PKFL == "Y" and PDFL == "Y")
# INPUT     : ADPC (AVAL = concentration), ADPD (AVAL = PD response), matched on
#             nominal time
# NOTE      : PSEUDOCODE. Overlays mean PK concentration-time with mean PD
#             response over time, faceted by DOSE LEVEL. To match the SAS twin
#             and PK convention, CONCENTRATION is on a SEMI-LOG (log10) axis and
#             PD is LINEAR. ggplot dual axes must share one transform, so the
#             overlay is drawn as TWO STACKED, X-ALIGNED panels (patchwork):
#             top = mean concentration with scale_y_log10(); bottom = mean PD
#             response on a linear axis; both share the nominal-time x-axis.
#             SAD = parallel cohorts, one dose per participant -> facet/group =
#             dv$trtvar (TRT01A = dose level; placebo pooled). Single dose ->
#             one concentration peak per panel; the temporal lag of effect
#             behind exposure is visible across ascending cohorts. Descriptive
#             temporal alignment of exposure vs effect; NOT a fitted PK/PD model.
#             n per dose x time from the respective ADaM domain (ADPC/ADPD).
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SAD")                      # facet = TRT01A (= dose level)

PCCD <- "CONC"       # parent analyte concentration PARAMCD in ADPC (matches SAS)
PDCD <- "PDMARK1"    # PD biomarker PARAMCD in ADPD (matches SAS)

## consistent dose-level ordering (numeric) for both domains' facets
dose_levels <- adam$adpc %>%
  filter(PKFL == "Y") %>%
  distinct(trt = .data[[dv$trtvar]], dosen = .data[[dv$trtnvar]]) %>%
  arrange(dosen) %>% pull(trt)

## --- mean PK concentration by dose level x nominal time (ADPC) --------------
pk <- adam$adpc %>%
  filter(PKFL == "Y", PARAMCD == PCCD, !is.na(AVAL), AVAL > 0) %>%
  group_by(trt = .data[[dv$trtvar]], tpt = ATPTN) %>%
  summarise(n = n_distinct(USUBJID), conc = mean(AVAL, na.rm = TRUE), .groups = "drop") %>%
  mutate(trt = factor(trt, levels = dose_levels))

## --- mean PD response by dose level x nominal time (ADPD) -------------------
pd <- adam$adpd %>%
  filter(PDFL == "Y", PARAMCD == PDCD, !is.na(AVAL)) %>%
  group_by(trt = .data[[dv$trtvar]], tpt = ATPTN) %>%
  summarise(n = n_distinct(USUBJID), resp = mean(AVAL, na.rm = TRUE), .groups = "drop") %>%
  mutate(trt = factor(trt, levels = dose_levels))

ttl <- tfl_titles(num = "14.4.5.1", type = "Figure",
   text = "Mean Plasma Concentration and Pharmacodynamic Response over Time by Dose Level",
   pop  = "PK- and PD-Evaluable Population",
   foot = paste("Top panel (semi-log) = mean concentration (", PCCD,
                "); bottom panel (linear) = mean PD response (", PDCD,
                "). Means over PK-/PD-evaluable participants at each nominal time (ADPC/ADPD).",
                "Single ascending dose: one column per dose level (placebo pooled).",
                "Descriptive temporal overlay, not a fitted PK/PD model."))

## top: concentration on a semi-log (log10) y-axis, faceted by dose level
p_pk <- ggplot(pk, aes(tpt, conc, colour = trt, group = trt)) +
  geom_line() + geom_point(size = 1.8) +
  facet_wrap(~ trt, nrow = 1) +
  scale_y_log10() +
  labs(x = NULL, y = sprintf("Mean concentration (%s), log scale", PCCD), colour = "Dose level") +
  theme_bw() + theme(legend.position = "none")

## bottom: PD response on a linear y-axis, same dose-level facets / x-axis
p_pd <- ggplot(pd, aes(tpt, resp, colour = trt, group = trt)) +
  geom_line(linetype = "longdash") + geom_point(size = 1.8, shape = 17) +
  facet_wrap(~ trt, nrow = 1) +
  scale_x_continuous(breaks = sort(unique(c(pk$tpt, pd$tpt)))) +
  labs(x = "Nominal time post-dose", y = sprintf("Mean PD response (%s)", PDCD),
       colour = "Dose level") +
  theme_bw() + theme(legend.position = "bottom")

## two stacked, x-aligned panels sharing the nominal-time axis
p <- patchwork::wrap_plots(p_pk, p_pd, ncol = 1, heights = c(1, 1)) +
  patchwork::plot_annotation(title = ttl$titles[3], caption = ttl$footnotes[1])
# ggsave(file.path(env$out, "f_pkpd_overlay.png"), p, width = 10, height = 7, dpi = 300)
print(p)
