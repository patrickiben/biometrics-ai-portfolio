################################################################################
# FIGURE    : f_pk_conc_mean  (Parallel-group / per-dose)
# TITLE     : Mean (+SD) Plasma Concentration-Time Profiles by Treatment
#             (Linear and Semi-Logarithmic)
# POPULATION: PK Concentration Population (PKFL == "Y")
# INPUT     : ADPC (PARAMCD = analyte concentration; ATPTN nominal time)
# NOTE      : PSEUDOCODE. Linear panel = arithmetic mean +/- SD; semi-log panel =
#             GEOMETRIC mean (exp(mean(log(AVAL))) over AVAL>0), no SD whiskers,
#             per PK convention. Matches the SAS twin. Parallel: each treatment =
#             one dose group (TRT01A); profiles overlaid.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("PARALLEL")

pc <- adam$adpc %>%
  filter(PKFL == "Y", ANL01FL == "Y",
         !(AVAL <= 0 | toupper(coalesce(AVALC,"")) == "BLQ"))   # drop BLQ for mean profile

## --- arithmetic mean/SD + GEOMETRIC mean per treatment x nominal time --------
## (BLQ/AVAL<=0 already removed above, so log() domain is safe; AVAL>0 guarded.)
prof <- pc %>%
  group_by(trt = .data[[dv$trtvar]], PARAM, t = ATPTN) %>%
  summarise(n       = n(),
            mean    = mean(AVAL),
            sd      = sd(AVAL),
            geomean = exp(mean(log(AVAL[AVAL > 0]))),   # geometric mean (log-scale)
            .groups = "drop") %>%
  mutate(lo = pmax(mean - sd, .Machine$double.eps),   # SD lower whisker (linear)
         hi = mean + sd)

ttl <- tfl_titles(num = "14.4.2.1", type = "Figure",
   text = "Mean (+SD) Plasma Concentration-Time Profiles by Treatment",
   pop  = "Pharmacokinetic Concentration Population",
   foot = paste("Left panel: arithmetic mean +/- 1 SD, linear scale.",
                "Right panel: geometric mean on the semi-log scale (concentrations > 0),",
                "no SD whiskers. BLQ excluded. Nominal sampling times.",
                "Each profile = one dose group (TRT01A)."))

## linear panel = arithmetic mean +/- SD
p_lin <- ggplot(prof, aes(t, mean, colour = trt, group = trt)) +
  geom_errorbar(aes(ymin = lo, ymax = hi), width = 0.3, alpha = 0.6) +
  geom_line() + geom_point(size = 1.8) +
  labs(x = "Nominal Time (h)", y = "Arithmetic Mean Concentration (+/- SD)",
       colour = "Treatment") +
  theme_bw() + theme(legend.position = "bottom") + ggtitle("Linear")

## semi-log panel = GEOMETRIC mean on log10 axis, no SD whiskers
p_log <- ggplot(prof, aes(t, geomean, colour = trt, group = trt)) +
  geom_line() + geom_point(size = 1.8) +
  scale_y_log10() +
  labs(x = "Nominal Time (h)", y = "Geometric Mean Concentration",
       colour = "Treatment") +
  theme_bw() + theme(legend.position = "bottom") + ggtitle("Semi-Logarithmic")

## combine side-by-side (patchwork) with shared caption/title
p <- patchwork::wrap_plots(p_lin, p_log, ncol = 2) +
  patchwork::plot_annotation(title = ttl$titles[3], caption = ttl$footnotes[1])

# ggsave(file.path(env$out, "f_pk_conc_mean.png"), p, width = 11, height = 6, dpi = 300)
print(p)
