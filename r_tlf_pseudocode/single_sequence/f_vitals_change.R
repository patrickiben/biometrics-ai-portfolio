################################################################################
# FIGURE    : f_vitals_change  (Single-/Fixed-Sequence DDI)
# TITLE     : Mean (+/-SE) Change from Baseline in Vital Signs by Visit and Period
# POPULATION: Safety Population (SAFFL == "Y"), post-baseline
# INPUT     : ADVS (PARAMCD in SYSBP, DIABP, PULSE, TEMP, RESP)
# NOTE      : PSEUDOCODE. Mean change from baseline (CHG) with +/-1 SE error bars
#             over scheduled post-baseline visits, one line per PERIOD
#             (dv$byperiod = APERIODC: Period 1 = reference/victim alone,
#             Period 2 = test/victim + perpetrator), faceted by parameter.
#             Within-participant by-period view; CHG is from the period-specific
#             baseline carried on ADVS. NO randomized sequence.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SINGLESEQ")                 # byperiod = c("APERIOD","APERIODC")
perC <- dv$byperiod[2]

## post-baseline analysis records (CHG defined); scheduled timepoints only
vs <- adam$advs %>%
  filter(SAFFL == "Y", ANL01FL == "Y", !is.na(CHG),
         PARAMCD %in% c("SYSBP","DIABP","PULSE","TEMP","RESP")) %>%
  mutate(per    = .data[[perC]],                      # one line per period
         PARAM  = factor(PARAM),
         AVISIT = factor(AVISIT, levels = unique(AVISIT[order(AVISITN)])))

## mean +/- SE of change by period x param x visit
sumdat <- vs %>%
  group_by(PARAM, AVISIT, AVISITN, per) %>%
  summarise(n    = sum(!is.na(CHG)),
            mean = mean(CHG, na.rm = TRUE),
            se   = sd(CHG, na.rm = TRUE) / sqrt(pmax(n, 1)),
            .groups = "drop") %>%
  mutate(lo = mean - se, hi = mean + se)

ttl <- tfl_titles(num = "14.3.7.2", type = "Figure",
   text = "Mean (+/-SE) Change from Baseline in Vital Signs by Visit and Period",
   pop  = "Safety Population",
   foot = paste("Points = period mean change from baseline; error bars = +/-1 SE.",
                "Period 1 = reference (victim alone), Period 2 = test (victim +",
                "perpetrator). Baseline = period-specific pre-dose value.",
                "Dashed line = no change."))

pd <- position_dodge(width = 0.3)
p <- ggplot(sumdat, aes(x = AVISIT, y = mean, colour = per, group = per)) +
  geom_hline(yintercept = 0, linetype = "dashed") +
  geom_errorbar(aes(ymin = lo, ymax = hi), width = 0.2, position = pd) +
  geom_line(position = pd) +
  geom_point(size = 2, position = pd) +
  facet_wrap(~ PARAM, scales = "free_y") +
  labs(x = "Visit", y = "Mean change from baseline (+/-SE)",
       colour = "Period", title = ttl$titles[3], caption = ttl$footnotes[1]) +
  theme_bw() +
  theme(legend.position = "bottom",
        axis.text.x = element_text(angle = 45, hjust = 1))
# ggsave(file.path(env$out, "f_vitals_change.png"), p, width = 10, height = 7, dpi = 300)
print(p)
