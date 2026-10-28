# FIGURE: f_pkpd_overlay (mad)
# TITLE : Aligned PK Concentration and PD Response Profiles
# Runnable analysis with explicit study settings and pre-derived ADaM input.
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
source("../01_analysis_models.R")
dv <- design_vars("MAD")
ttl <- tfl_titles(num = "f_pkpd_overlay", type = "Figure",
  text = "Aligned PK Concentration and PD Response Profiles", pop = "PK- and PD-evaluable populations",
  foot = "Means are computed independently in the PK and PD populations at each nominal time. Separate panels retain original units and avoid arbitrary rescaling. This temporal comparison is descriptive, with no fitted PK/PD relationship or steady-state conclusion.")
profiles <- tfl_model_overlay(adam$adpc, adam$adpd, dv)
print(profiles)
p <- ggplot(profiles, aes(time, mean, colour = trt, group = interaction(trt, period, ADY))) +
  geom_line() + geom_point(size = 1.5) +
  facet_grid(series ~ panel, scales = "free_y") +
  labs(x = "Nominal time after dose (hours)", y = "Mean in original units", colour = "Treatment",
    title = ttl$titles[3], caption = stringr::str_wrap(ttl$footnotes[1], 120)) +
  theme_bw() + theme(legend.position = "bottom")
print(p)
