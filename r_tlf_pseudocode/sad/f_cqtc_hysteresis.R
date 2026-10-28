# FIGURE: f_cqtc_hysteresis (sad)
# TITLE : Exploratory Mean Concentration-QTc Loop Profiles
# Runnable analysis with explicit study settings and pre-derived ADaM input.
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
source("../01_analysis_models.R")
dv <- design_vars("SAD")
ttl <- tfl_titles(num = "f_cqtc_hysteresis", type = "Figure",
  text = "Exploratory Mean Concentration-QTc Loop Profiles", pop = "Safety ECG and PK concentration populations",
  foot = "ddQTcF is the individual supplied QTcF change minus the same-day time-matched placebo mean. Error bars include active-participant variance plus the placebo mean variance. Arrows follow nominal time; a dotted line closes the polygon. This descriptive figure does not establish a drug effect or regulatory conclusion.")
prepared <- tfl_model_cqtc_data(adam$adpc, adam$adeg, mad = FALSE)
profile <- tfl_model_cqtc_profile(prepared)
print(profile)
closer <- profile %>% group_by(trt, day) %>% summarise(x = last(concentration), y = last(mean), xend = first(concentration), yend = first(mean), .groups = "drop")
p <- ggplot(profile, aes(concentration, mean)) +
  geom_hline(yintercept = 0, colour = "grey60") +
  geom_errorbar(aes(ymin = mean - se, ymax = mean + se), width = 0, colour = "grey45") +
  geom_path(arrow = grid::arrow(length = grid::unit(2, "mm"), type = "closed")) +
  geom_segment(data = closer, aes(x = x, y = y, xend = xend, yend = yend), linetype = "dotted") +
  geom_point(size = 1.5) + facet_grid(day ~ trt, scales = "free_x") +
  labs(x = paste("Mean concentration:", tfl_model_setting("pk_parameter", "CONC"), "(", prepared$concentration_unit, ")"), y = "Mean ddQTcF (ms) +/- SE",
    title = ttl$titles[3], caption = stringr::str_wrap(ttl$footnotes[1], 120)) + theme_bw()
print(p)
