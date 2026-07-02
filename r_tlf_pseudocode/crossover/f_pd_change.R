################################################################################
# FIGURE    : f_pd_change  (Crossover - 2x2 or Williams)
# TITLE     : Mean (+/- SE) Change from Baseline in Pharmacodynamic Biomarker
#             Over Time by Treatment
# POPULATION: Pharmacodynamic Population (PDFL == "Y" on ADPD)
# INPUT     : ADPD (PARAMCD = PD biomarker; CHG = change from baseline; AVISIT/
#             AVISITN; APERIOD; TRTA)
# NOTE      : PSEUDOCODE. Within-participant crossover -> profile lines are by TRTA
#             (treatment received in period), so each participant contributes to
#             both/all treatment curves. Mean CHG (+/- SE) vs nominal VISIT, one
#             colored line per treatment. Baseline is the PERIOD-SPECIFIC
#             baseline carried on ADPD (BASE/CHG), respecting any washout reset.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("CROSSOVER")                 # TRTA + APERIOD + TRTSEQP

PARAM_CD <- "PDMARK1"                            # target PD biomarker (match SAS)

## --- PD-evaluable, post-baseline change records -----------------------------
## ADPD already carries period-specific BASE and CHG (= AVAL - BASE); do NOT
## re-derive baseline. Keep post-baseline visits (AVISITN>0), matching SAS.
pd <- adam$adpd %>%
  filter(PDFL == "Y", PARAMCD == PARAM_CD, AVISITN > 0, !is.na(CHG)) %>%
  mutate(trt = .data[[dv$trtvar]])

## --- mean +/- SE of CHG by treatment x nominal visit ------------------------
sumf <- pd %>%
  group_by(trt = .data[[dv$trtvar]], AVISITN, AVISIT) %>%
  summarise(n    = sum(!is.na(CHG)),
            mean = mean(CHG, na.rm = TRUE),
            se   = sd(CHG, na.rm = TRUE) / sqrt(sum(!is.na(CHG))),
            .groups = "drop") %>%
  mutate(lo = mean - se, hi = mean + se)

ttl <- tfl_titles(num = "14.2.6.2", type = "Figure",
   text = sprintf("Mean (+/- SE) Change from Baseline in Pharmacodynamic Biomarker (%s) by Treatment", PARAM_CD),
   pop  = "Pharmacodynamic Population",
   foot = paste("Each line = a treatment (TRTA) averaged across the participants who received it in any period.",
                "Change from the period-specific baseline (CHG on ADPD; post-baseline visits, AVISITN>0). Error bars = +/- 1 SE.",
                "Crossover: every participant contributes to each treatment curve."))

p <- ggplot(sumf, aes(AVISITN, mean, colour = trt, group = trt)) +
  geom_hline(yintercept = 0, linetype = "dotted") +
  geom_line() +
  geom_point(size = 1.8) +
  geom_errorbar(aes(ymin = lo, ymax = hi), width = 0.15) +
  scale_x_continuous(breaks = sort(unique(sumf$AVISITN)),
                     labels = function(b) sumf$AVISIT[match(b, sumf$AVISITN)]) +
  labs(x = "Nominal Visit", y = "Mean Change from Baseline (+/- SE)",
       colour = "Treatment", title = ttl$titles[3], caption = ttl$footnotes[1]) +
  theme_bw() + theme(legend.position = "bottom",
                     axis.text.x = element_text(angle = 45, hjust = 1))
# ggsave(file.path(env$out, "f_pd_change.png"), p, width = 9, height = 6, dpi = 300)
print(p)
