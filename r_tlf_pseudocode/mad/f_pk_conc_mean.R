################################################################################
# FIGURE    : f_pk_conc_mean  (MAD - Multiple Ascending Dose / per-cohort)
# TITLE     : Mean (+/- SD) Plasma Concentration-Time Profiles by Dose Cohort and
#             Dosing Day (Linear and Semi-Logarithmic)
# POPULATION: PK Concentration Population (PKFL == "Y")
# INPUT     : ADPC (PARAMCD = analyte concentration; ADY/AVISIT dosing day;
#             ATPTN nominal time within the interval)
# NOTE      : PSEUDOCODE. Mean +/- SD per dose cohort x dosing day x nominal time,
#             on linear and semilog (log10 y) panels. LINEAR panel = arithmetic
#             mean +/- SD; SEMILOG panel = geometric mean (exp(mean(log AVAL)) over
#             AVAL>0), no SD whiskers -- per PK convention. MAD: profiles collected
#             on >1 occasion -> Day 1 (single dose) vs Day N (steady state) shown as
#             line type while colour = dose cohort (TRT01A, ordered low -> high), so
#             accumulation between Day 1 and Day N is visible per cohort. BLQ dropped.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("MAD")

pc <- adam$adpc %>%
  filter(PKFL == "Y", ANL01FL == "Y",
         !(AVAL <= 0 | toupper(coalesce(AVALC,"")) == "BLQ"))   # drop BLQ for mean profile

## --- mean (+/- SD) per dose cohort x dosing day x nominal time (one analyte) -
## colour = dose cohort ordered by TRT01AN; linetype = dosing day (Day 1 vs Day N)
prof <- pc %>%
  group_by(trt = .data[[dv$trtvar]], trtn = .data[[dv$trtnvar]],
           PARAM, day = AVISIT, t = ATPTN) %>%
  summarise(n       = n(),
            mean    = mean(AVAL),                          # arithmetic mean (linear panel)
            sd      = sd(AVAL),
            geomean = exp(mean(log(AVAL[AVAL > 0]))),      # geometric mean (semilog panel), AVAL>0
            .groups = "drop") %>%
  mutate(lo  = pmax(mean - sd, .Machine$double.eps),  # log-safe lower whisker (linear panel)
         hi  = mean + sd,
         trt = factor(trt, levels = unique(trt[order(trtn)])),  # dose order
         day = factor(day))                                     # Day 1 ... Day N

ttl <- tfl_titles(num = "14.4.2.1", type = "Figure",
   text = "Mean (+/- SD) Plasma Concentration-Time Profiles by Dose Cohort and Dosing Day",
   pop  = "Pharmacokinetic Concentration Population",
   foot = paste("Left panel: arithmetic mean +/- 1 SD, linear scale.",
                "Right panel: geometric mean on the semi-log panel (concentrations > 0), no SD whiskers.",
                "BLQ excluded. Nominal sampling times within the dosing interval. Colour = dose cohort",
                "(TRT01A); line type = dosing day (Day 1 single dose vs Day N steady state)."))

## LINEAR panel: arithmetic mean +/- SD
p_lin <- ggplot(prof, aes(t, mean, colour = trt, linetype = day, group = interaction(trt, day))) +
  geom_errorbar(aes(ymin = lo, ymax = hi), width = 0.3, alpha = 0.5) +
  geom_line() + geom_point(size = 1.6) +
  labs(x = "Nominal Time (h)", y = "Arithmetic Mean Concentration (+/- SD)",
       colour = "Dose Cohort", linetype = "Dosing Day") +
  theme_bw() + theme(legend.position = "bottom") +
  ggtitle("Linear")

## SEMILOG panel: GEOMETRIC mean on a log10 axis, no SD whiskers (PK convention)
p_log <- ggplot(prof, aes(t, geomean, colour = trt, linetype = day, group = interaction(trt, day))) +
  geom_line() + geom_point(size = 1.6) +
  scale_y_log10() +
  labs(x = "Nominal Time (h)", y = "Geometric Mean Concentration",
       colour = "Dose Cohort", linetype = "Dosing Day") +
  theme_bw() + theme(legend.position = "bottom") +
  ggtitle("Semi-Logarithmic")

## combine side-by-side (patchwork) with shared caption/title
p <- patchwork::wrap_plots(p_lin, p_log, ncol = 2) +
  patchwork::plot_annotation(title = ttl$titles[3], caption = ttl$footnotes[1])

## alt deliverable: facet_wrap(~ trt) one panel per cohort (Day 1 vs Day N overlaid)
# ggsave(file.path(env$out, "f_pk_conc_mean.png"), p, width = 11, height = 6, dpi = 300)
print(p)
