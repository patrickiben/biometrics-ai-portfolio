################################################################################
# FIGURE    : f_pk_conc_mean  (SAD - Single Ascending Dose / per-cohort)
# TITLE     : Mean (+/- SD) Plasma Concentration-Time Profiles by Dose Cohort
#             (Linear and Semi-Logarithmic)
# POPULATION: PK Concentration Population (PKFL == "Y")
# INPUT     : ADPC (PARAMCD = analyte concentration; ATPTN nominal time)
# NOTE      : PSEUDOCODE. Per dose cohort x nominal time, two panels:
#             LINEAR panel = ARITHMETIC mean +/- 1 SD; SEMI-LOG panel =
#             GEOMETRIC mean (exp(mean(log(AVAL))) over AVAL > 0), no SD whiskers
#             -- matches the SAS twin and standard PK convention (geometric mean
#             on the semi-log panel). BLQ excluded; analysis records = ANL01FL.
#             SAD: each cohort = one ascending dose group (TRT01A), single dose;
#             profiles overlaid so the dose-ordered separation is visible.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SAD")

pc <- adam$adpc %>%
  filter(PKFL == "Y", ANL01FL == "Y",
         !(AVAL <= 0 | toupper(coalesce(AVALC,"")) == "BLQ"))   # drop BLQ for mean profile

## --- arithmetic mean (+/- SD) AND geometric mean per dose cohort x nominal time -
## order cohorts by dose (TRT01AN) so the legend / overlay reads low -> high dose
prof <- pc %>%
  group_by(trt = .data[[dv$trtvar]], trtn = .data[[dv$trtnvar]], PARAM, t = ATPTN) %>%
  summarise(n       = n(),
            mean    = mean(AVAL),                          # arithmetic (linear panel)
            sd      = sd(AVAL),
            geomean = exp(mean(log(AVAL[AVAL > 0]))),      # geometric (semi-log panel)
            .groups = "drop") %>%
  mutate(lo  = pmax(mean - sd, .Machine$double.eps),  # log-safe lower whisker
         hi  = mean + sd,
         trt = factor(trt, levels = unique(trt[order(trtn)])))   # dose order

ttl <- tfl_titles(num = "14.4.2.1", type = "Figure",
   text = "Mean (+/- SD) Plasma Concentration-Time Profiles by Dose Cohort",
   pop  = "Pharmacokinetic Concentration Population",
   foot = paste("Top: arithmetic mean +/- 1 SD, linear scale.",
                "Bottom: geometric mean (log scale), back-transformed from the mean of",
                "log(concentration) over concentrations > 0, semi-logarithmic scale.",
                "BLQ excluded; analysis records ANL01FL == \"Y\". Nominal sampling times",
                "after the single dose. Each profile = one ascending dose cohort (TRT01A)."))

## linear panel: arithmetic mean +/- SD
p_lin <- ggplot(prof, aes(t, mean, colour = trt, group = trt)) +
  geom_errorbar(aes(ymin = lo, ymax = hi), width = 0.3, alpha = 0.6) +
  geom_line() + geom_point(size = 1.8) +
  labs(x = "Nominal Time (h)", y = "Arithmetic Mean Concentration (+/- SD)",
       colour = "Dose Cohort") +
  theme_bw() + theme(legend.position = "bottom") + ggtitle("Linear")

## semi-log panel: geometric mean on a log10 axis, no SD whiskers
p_log <- ggplot(prof, aes(t, geomean, colour = trt, group = trt)) +
  geom_line() + geom_point(size = 1.8) +
  scale_y_log10() +
  labs(x = "Nominal Time (h)", y = "Geometric Mean Concentration",
       colour = "Dose Cohort") +
  theme_bw() + theme(legend.position = "bottom") + ggtitle("Semi-Logarithmic")

## combine side-by-side (patchwork) with shared caption/title
p <- patchwork::wrap_plots(p_lin, p_log, ncol = 2) +
  patchwork::plot_annotation(title = ttl$titles[3], caption = ttl$footnotes[1])

# ggsave(file.path(env$out, "f_pk_conc_mean.png"), p, width = 11, height = 6, dpi = 300)
print(p)
