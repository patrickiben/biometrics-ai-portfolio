################################################################################
# FIGURE    : f_pk_conc_mean  (Single-/fixed-sequence DDI)
# TITLE     : Mean (+/- SD) Plasma Concentration-Time Profiles of the Victim Drug
#             by Period (Reference vs Test) (Linear and Semi-Logarithmic)
# POPULATION: PK Concentration Population (PKFL == "Y")
# INPUT     : ADPC (AVAL = concentration; ATPTN nominal time; APERIOD)
# NOTE      : PSEUDOCODE. LINEAR panel = arithmetic mean +/- SD; SEMI-LOG panel =
#             GEOMETRIC mean (no SD whiskers) per PK convention. Per PERIOD x
#             nominal time. Single-/fixed-sequence DDI: the two overlaid profiles
#             are the SAME victim drug in Period 1 (alone, reference) vs Period 2
#             (with perpetrator, test) -- the visual DDI read-out. Colour/group =
#             PERIOD (dv$byperiod), not a sequence. ONE BLQ rule (BLQ excluded)
#             and the ANL01FL=="Y" analysis-record flag, both matching the SAS twin.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SINGLESEQ")                 # period via dv$byperiod (no sequence)

pc <- adam$adpc %>%
  filter(PKFL == "Y", ANL01FL == "Y",
         !(AVAL <= 0 | toupper(coalesce(AVALC,"")) == "BLQ")) %>%   # drop BLQ for mean profile
  mutate(period = .data[[dv$byperiod[2]]])      # APERIODC label: Reference / Test

## --- per period x nominal time: arithmetic mean +/- SD AND geometric mean ----
## (one analyte; loop for more). Geometric mean = exp(mean(log AVAL)) over AVAL>0
## (AVAL already filtered to AVAL > 0 / non-BLQ above; guard inside the mean).
prof <- pc %>%
  group_by(period, PARAM, t = ATPTN) %>%
  summarise(n       = n(),
            mean    = mean(AVAL),
            sd      = sd(AVAL),
            geomean = exp(mean(log(AVAL[AVAL > 0]))),   # geometric mean
            .groups = "drop") %>%
  mutate(lo = pmax(mean - sd, .Machine$double.eps),   # log-safe lower whisker
         hi = mean + sd)

ttl <- tfl_titles(num = "14.4.2.1", type = "Figure",
   text = "Mean Plasma Concentration-Time Profiles of the Victim Drug by Period",
   pop  = "Pharmacokinetic Concentration Population",
   foot = paste("Linear panel: arithmetic mean (points) +/- 1 SD (whiskers).",
                "Semi-log panel: geometric mean (no SD whiskers). BLQ excluded.",
                "Nominal sampling times. Profiles = same victim drug, Period 1 alone",
                "(reference) vs Period 2 with perpetrator (test); fixed-sequence",
                "design (no randomized sequence)."))

## linear panel: arithmetic mean +/- SD whiskers
p_lin <- ggplot(prof, aes(t, mean, colour = period, group = period)) +
  geom_errorbar(aes(ymin = lo, ymax = hi), width = 0.3, alpha = 0.6) +
  geom_line() + geom_point(size = 1.8) +
  labs(x = "Nominal Time (h)", y = "Arithmetic Mean Concentration", colour = "Period") +
  theme_bw() + theme(legend.position = "bottom") + ggtitle("Linear")

## semi-log panel: GEOMETRIC mean on log10 axis, no SD whiskers (matches SAS)
p_log <- ggplot(prof, aes(t, geomean, colour = period, group = period)) +
  geom_line() + geom_point(size = 1.8) +
  scale_y_log10() +
  labs(x = "Nominal Time (h)", y = "Geometric Mean Concentration (log scale)",
       colour = "Period") +
  theme_bw() + theme(legend.position = "bottom") + ggtitle("Semi-Logarithmic")

## combine side-by-side (patchwork) with shared caption/title
p <- patchwork::wrap_plots(p_lin, p_log, ncol = 2) +
  patchwork::plot_annotation(title = ttl$titles[3], caption = ttl$footnotes[1])

# ggsave(file.path(env$out, "f_pk_conc_mean.png"), p, width = 11, height = 6, dpi = 300)
print(p)
