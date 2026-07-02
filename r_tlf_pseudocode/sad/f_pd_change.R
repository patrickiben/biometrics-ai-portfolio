################################################################################
# FIGURE    : f_pd_change  (Single Ascending Dose)
# TITLE     : Mean (+/- SE) Change from Baseline in Pharmacodynamic Endpoint
#             over Time by Dose Level
# POPULATION: PD-Evaluable Population (PDFL == "Y")
# INPUT     : ADPD (PARAMCD = PD biomarker code; CHG, AVISIT/AVISITN,
#             ATPT/ATPTN)
# NOTE      : PSEUDOCODE. Mean change-from-baseline (CHG) profile over the
#             single-dose PD time course, one line per dose level, error bars =
#             SE. SE = SD / sqrt(distinct participants) at each dose x timepoint
#             (participant-level n, matching the SAS twin). SAD = parallel cohorts,
#             one dose per participant -> grouping = dv$trtvar (TRT01A = dose
#             level; placebo pooled). PD endpoint PARAMCD = PDMARK1 (same as SAS).
#             Nominal time = coalesce(ATPTN, AVISITN), same as the SAS twin.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SAD")                      # grouping = TRT01A (= dose level)

PDCD <- "PDMARK1"                              # PD endpoint of interest (same as SAS twin)

pd <- adam$adpd %>%
  filter(PDFL == "Y", PARAMCD == PDCD, AVISITN > 0, !is.na(CHG)) %>%
  ## nominal time after dose: prefer planned timepoint (ATPTN), else AVISITN
  ## (same coalesce(ATPTN, AVISITN) rule as the SAS twin)
  mutate(reltm = dplyr::coalesce(ATPTN, AVISITN),
         trt = factor(.data[[dv$trtvar]],
                      levels = unique(.data[[dv$trtvar]][order(.data[[dv$trtnvar]])])))

## --- summarise CHG by dose level x nominal time; SE on distinct-participant n -
prof <- pd %>%
  group_by(trt, tpt = reltm) %>%
  summarise(
    n    = n_distinct(USUBJID),
    mean = mean(CHG, na.rm = TRUE),
    sd   = sd(CHG,   na.rm = TRUE),
    se   = sd / sqrt(n),
    .groups = "drop") %>%
  arrange(trt, tpt)

ttl <- tfl_titles(num = "14.4.6.2", type = "Figure",
   text = "Mean (+/- SE) Change from Baseline in Pharmacodynamic Endpoint over Time by Dose Level",
   pop  = "Pharmacodynamic-Evaluable Population",
   foot = paste("Points = mean change from baseline; error bars = +/- 1 SE.",
                "n = PD-evaluable participants with a value at the timepoint (ADPD), not ADSL.",
                "Single ascending dose: one line per dose level (placebo pooled).",
                "Dashed line = no change. Parameter:", PDCD))

p <- ggplot(prof, aes(tpt, mean, colour = trt, group = trt)) +
  geom_hline(yintercept = 0, linetype = "dashed", colour = "grey50") +
  geom_line() +
  geom_point(size = 2) +
  geom_errorbar(aes(ymin = mean - se, ymax = mean + se), width = 0.4) +
  scale_x_continuous(breaks = sort(unique(prof$tpt))) +
  labs(x = "Nominal time post-dose", y = "Change from baseline (mean +/- SE)",
       colour = "Dose level", title = ttl$titles[3], caption = ttl$footnotes[1]) +
  theme_bw() + theme(legend.position = "bottom")
# ggsave(file.path(env$out, "f_pd_change.png"), p, width = 9, height = 6, dpi = 300)
print(p)
