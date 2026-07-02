################################################################################
# FIGURE    : f_pd_change  (Parallel-group)
# TITLE     : Mean (+/- SE) Change from Baseline in Pharmacodynamic Endpoint
#             over Time by Treatment
# POPULATION: PD-Evaluable Population (PDFL == "Y")
# INPUT     : ADPD (PARAMCD = PD biomarker code; CHG, AVISIT/AVISITN,
#             ATPT/ATPTN)
# NOTE      : PSEUDOCODE. Mean change-from-baseline (CHG) profile by nominal
#             time, one line per treatment, error bars = SE. Parallel-group:
#             one treatment per participant -> grouping = dv$trtvar (TRT01A, = dose
#             level for ascending-dose layouts). n per treatment x time from
#             ADPD (participants with a CHG value), NOT ADSL.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("PARALLEL")

PDCD <- "INHIB"                                # PD endpoint of interest

pd <- adam$adpd %>%
  filter(PDFL == "Y", PARAMCD == PDCD, !is.na(CHG)) %>%
  mutate(trt = .data[[dv$trtvar]])

## --- summarise CHG by treatment x nominal time (ADPD-borne n) ---------------
## prefer planned timepoint (ATPTN) for densely-sampled PD; else AVISITN
prof <- pd %>%
  group_by(trt, tpt = ATPTN, tptc = ATPT) %>%
  summarise(
    n    = n_distinct(USUBJID),
    mean = mean(CHG, na.rm = TRUE),
    sd   = sd(CHG,   na.rm = TRUE),
    se   = sd / sqrt(n),
    .groups = "drop") %>%
  arrange(trt, tpt)

ttl <- tfl_titles(num = "14.4.6.2", type = "Figure",
   text = "Mean (+/- SE) Change from Baseline in Pharmacodynamic Endpoint over Time by Treatment",
   pop  = "Pharmacodynamic-Evaluable Population",
   foot = paste("Points = mean change from baseline; error bars = +/- 1 SE.",
                "n = PD-evaluable participants with a value at the timepoint (ADPD).",
                "Dashed line = no change. Parameter:", PDCD))

p <- ggplot(prof, aes(tpt, mean, colour = trt, group = trt)) +
  geom_hline(yintercept = 0, linetype = "dashed", colour = "grey50") +
  geom_line() +
  geom_point(size = 2) +
  geom_errorbar(aes(ymin = mean - se, ymax = mean + se), width = 0.4) +
  scale_x_continuous(breaks = sort(unique(prof$tpt))) +
  labs(x = "Nominal time post-dose", y = "Change from baseline (mean +/- SE)",
       colour = "Treatment", title = ttl$titles[3], caption = ttl$footnotes[1]) +
  theme_bw() + theme(legend.position = "bottom")
# ggsave(file.path(env$out, "f_pd_change.png"), p, width = 9, height = 6, dpi = 300)
print(p)
