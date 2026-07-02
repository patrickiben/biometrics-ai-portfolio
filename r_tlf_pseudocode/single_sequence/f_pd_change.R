################################################################################
# FIGURE    : f_pd_change  (Single-/Fixed-Sequence DDI)
# TITLE     : Mean (+/- SE) Change from Baseline in Pharmacodynamic Endpoint
#             over Time by Period
# POPULATION: PD-Evaluable Population (PDFL == "Y")
# INPUT     : ADPD (PARAMCD = PD biomarker code; CHG, AVISIT/AVISITN,
#             ATPT/ATPTN, APERIOD/APERIODC)
# NOTE      : PSEUDOCODE. Mean change-from-baseline (CHG) profile by nominal
#             time, one line per PERIOD, error bars = SE. PERIOD figure ->
#             grouping = dv$byperiod (APERIOD/APERIODC): Period 1 = reference
#             (victim alone), Period 2 = test (victim + perpetrator). NO
#             randomized sequence. n per period x time from ADPD (participants with a
#             CHG value at that period x time), NOT ADSL.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SINGLESEQ")                 # byperiod = c("APERIOD","APERIODC")
options(tfl.study = env$study)
perC <- dv$byperiod[2]                          # character period label

PDCD <- "INHIB"                                # PD endpoint of interest

pd <- adam$adpd %>%
  filter(PDFL == "Y", PARAMCD == PDCD, !is.na(CHG)) %>%
  mutate(per = .data[[perC]])                  # Period 1 ref / Period 2 test+perp

## --- summarise CHG by PERIOD x nominal time (ADPD-borne n) ------------------
## prefer planned timepoint (ATPTN) for densely-sampled PD; else AVISITN.
## A participant contributes to both periods -> n counted per period x time.
prof <- pd %>%
  group_by(per, tpt = ATPTN, tptc = ATPT) %>%
  summarise(
    n    = n_distinct(USUBJID),
    mean = mean(CHG, na.rm = TRUE),
    sd   = sd(CHG,   na.rm = TRUE),
    se   = sd / sqrt(n),
    .groups = "drop") %>%
  arrange(per, tpt)

ttl <- tfl_titles(num = "14.4.6.2", type = "Figure",
   text = "Mean (+/- SE) Change from Baseline in Pharmacodynamic Endpoint over Time by Period",
   pop  = "Pharmacodynamic-Evaluable Population",
   foot = paste("Single-fixed-sequence DDI: Period 1 = reference (victim alone),",
                "Period 2 = test (victim + perpetrator). Points = mean change from",
                "baseline; error bars = +/- 1 SE. n = PD-evaluable participants with a",
                "value at the period x timepoint (ADPD). Dashed line = no change.",
                "Parameter:", PDCD))

p <- ggplot(prof, aes(tpt, mean, colour = per, group = per)) +
  geom_hline(yintercept = 0, linetype = "dashed", colour = "grey50") +
  geom_line() +
  geom_point(size = 2) +
  geom_errorbar(aes(ymin = mean - se, ymax = mean + se), width = 0.4) +
  scale_x_continuous(breaks = sort(unique(prof$tpt))) +
  labs(x = "Nominal time post-dose", y = "Change from baseline (mean +/- SE)",
       colour = "Period", title = ttl$titles[3], caption = ttl$footnotes[1]) +
  theme_bw() + theme(legend.position = "bottom")
# ggsave(file.path(env$out, "f_pd_change.png"), p, width = 9, height = 6, dpi = 300)
print(p)
