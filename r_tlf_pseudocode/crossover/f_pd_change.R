# FIGURE: f_pd_change (crossover)
# TITLE : Pharmacodynamic Change from Baseline over Time
# Runnable analysis with explicit study settings and pre-derived ADaM input.
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
source("../01_analysis_models.R")
dv <- design_vars("CROSSOVER")
ttl <- tfl_titles(num = "14.2.6.2", type = "Figure",
  text = "Pharmacodynamic Change from Baseline over Time", pop = "PD-evaluable population",
  foot = "Mean supplied change from baseline with plus/minus one standard error; n is the number of participants at each time. Periods and days remain separate. With fewer than two participants the standard error is not estimable.")
pd <- tfl_model_pd_data(adam$adpd, dv)
prof <- pd %>% group_by(trt, period, ADY, AVISIT, AVISITN, ATPTN) %>%
  summarise(n = sum(is.finite(CHG)), mean = if (n) mean(CHG[is.finite(CHG)]) else NA_real_,
    se = if (n > 1L) sd(CHG[is.finite(CHG)])/sqrt(n) else NA_real_, .groups = "drop") %>%
  mutate(panel = paste("Period", period, "Day", ADY, AVISIT))
print(prof)
p <- ggplot(prof, aes(ATPTN, mean, colour = trt, group = trt)) +
  geom_hline(yintercept = 0, linetype = "dashed", colour = "grey50") +
  geom_line() + geom_point(size = 1.5) +
  geom_errorbar(aes(ymin = mean - se, ymax = mean + se), width = .15, na.rm = TRUE) +
  facet_wrap(~ panel) + labs(x = "Nominal time after dose (hours)", y = paste("Change from baseline (", unique(pd$AVALU), ")"),
    colour = "Treatment", title = ttl$titles[3], caption = stringr::str_wrap(ttl$footnotes[1], 120)) +
  theme_bw() + theme(legend.position = "bottom")
print(p)
