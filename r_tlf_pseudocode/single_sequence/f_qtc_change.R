################################################################################
# FIGURE    : f_qtc_change  (Single-/Fixed-Sequence DDI)
# TITLE     : Mean (90% CI) Change from Baseline in QTcF by Timepoint and
#             Treatment Period
# POPULATION: Safety Population (SAFFL == "Y"), post-baseline
# INPUT     : ADEG (PARAMCD == "QTCF"; CHG from period baseline)
# NOTE      : PSEUDOCODE. DESCRIPTIVE (matches the SAS twin -- no inferential
#             model). Mean (+/-90% CI) CHG in QTcF from the PERIOD baseline over
#             nominal post-dose timepoints (x = ATPTN), one line per PERIOD
#             (dv$byperiod = APERIODC: Period 1 = reference/victim alone, Period 2
#             = test/victim + perpetrator). Horizontal reference lines at 0, 30,
#             and 60 ms (ICH E14 central-tendency thresholds), matching the SAS
#             twin's reference lines / x-axis / footnote.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SINGLESEQ")                 # byperiod = c("APERIOD","APERIODC")
perC <- dv$byperiod[2]

eg <- adam$adeg %>%
  filter(SAFFL == "Y", ANL01FL == "Y", PARAMCD == "QTCF",
         AVISITN > 0, !is.na(CHG)) %>%
  mutate(per = .data[[perC]])

## --- mean change + 90% CI of CHG by period x nominal timepoint (descriptive) -
mc <- eg %>%
  group_by(ATPTN, ATPT, per) %>%
  summarise(n    = sum(!is.na(CHG)),
            mean = mean(CHG, na.rm = TRUE),
            se   = sd(CHG, na.rm = TRUE) / sqrt(pmax(n, 1)),
            .groups = "drop") %>%
  mutate(tcrit = qt(0.95, df = pmax(n - 1, 1)),     # two-sided 90% CI (t-based)
         lo = mean - tcrit * se,
         hi = mean + tcrit * se)

ttl <- tfl_titles(num = "14.3.8.3", type = "Figure",
   text = "Mean (90% CI) Change from Baseline in QTcF by Timepoint and Treatment Period",
   pop  = "Safety Population",
   foot = paste("Points = period mean change from period baseline (QTcF,",
                "Fridericia); bars = 90% CI. Period 1 = reference (victim alone),",
                "Period 2 = test (victim + perpetrator). Horizontal reference",
                "lines at 0, 30, and 60 ms (ICH E14 central-tendency thresholds).",
                "One profile per treatment period (single-/fixed-sequence);",
                "descriptive."))

pd <- position_dodge(width = 0.3)
p <- ggplot(mc, aes(x = ATPTN, y = mean, colour = per, group = per)) +
  geom_hline(yintercept = 0,  linetype = "dashed") +
  geom_hline(yintercept = 30, linetype = "dotted", colour = "grey40") +  # ICH E14
  geom_hline(yintercept = 60, linetype = "dotted", colour = "grey40") +  # ICH E14
  geom_errorbar(aes(ymin = lo, ymax = hi), width = 0.2, position = pd) +
  geom_line(position = pd) + geom_point(size = 2, position = pd) +
  scale_x_continuous(breaks = sort(unique(mc$ATPTN)),
                     labels = function(b) mc$ATPT[match(b, mc$ATPTN)]) +
  labs(x = "Nominal time post-dose (h)", y = "Mean change in QTcF (ms), 90% CI",
       colour = "Period", title = ttl$titles[3], caption = ttl$footnotes[1]) +
  theme_bw() + theme(legend.position = "bottom",
                     axis.text.x = element_text(angle = 45, hjust = 1))
# ggsave(file.path(env$out, "f_qtc_change.png"), p, width = 9, height = 6, dpi = 300)
print(p)
