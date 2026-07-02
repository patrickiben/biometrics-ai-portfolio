################################################################################
# FIGURE    : f_lab_change  (Single-/Fixed-Sequence DDI)
# TITLE     : Mean (+/- SE) Change from Baseline in Laboratory Values Over Time
#             by Period
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADLB (PARAMCD/PARAM, CHG, AVISIT/AVISITN, APERIOD/APERIODC, ANL01FL)
# NOTE      : PSEUDOCODE. Mean change from baseline (CHG) by scheduled visit, one
#             panel per analyte, one line/colour per PERIOD (Period 1 = reference /
#             victim alone, Period 2 = test / victim + perpetrator), error bars =
#             +/- 1 SE (standard error of the mean) -- one dispersion stat, same as
#             the SAS twin. Single-fixed-sequence: periods overlaid on a common
#             visit axis. Analysis records via ANL01FL & AVISITN > 0 (matching
#             SAS). Same analyte PARAMCD panel as SAS (ALT/AST/CREAT/K).
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SINGLESEQ")                 # colour/line = period (APERIODC)
options(tfl.study = env$study)
perC <- dv$byperiod[2]                           # character period label column

## post-baseline analysis records (one per participant/param/visit/period via ANL01FL)
## Same analyte panel as the SAS twin.
lb <- adam$adlb %>%
  filter(SAFFL == "Y", ANL01FL == "Y", AVISITN > 0, !is.na(CHG),
         PARAMCD %in% c("ALT","AST","CREAT","K")) %>%
  mutate(per = .data[[perC]])

## --- mean +/- SE of change, per param x visit x PERIOD ---------------------
summ <- descstat(lb, var = "CHG", by = c("PARAMCD","PARAM","AVISITN","AVISIT", perC)) %>%
  transmute(PARAM, AVISITN, AVISIT, per = .data[[perC]],
            n, mean, sd,
            se = sd / sqrt(pmax(n, 1)),                 # standard error of the mean
            lo = mean - se, hi = mean + se) %>%
  arrange(PARAM, AVISITN)

ttl <- tfl_titles(num = "14.3.4.4", type = "Figure",
   text = "Mean (+/- SE) Change from Baseline in Laboratory Values Over Time by Period",
   pop  = "Safety Population",
   foot = paste("Single-fixed-sequence DDI: Period 1 = reference (victim alone),",
                "Period 2 = test (victim + perpetrator). Points = arithmetic mean",
                "change from baseline by scheduled visit; error bars = +/- 1 SE;",
                "periods overlaid. Descriptive. Visits with n < 3 may be suppressed",
                "per SAP."))

## --- faceted line plot: x = visit (ordered by AVISITN), y = mean CHG, by PERIOD
p <- ggplot(summ, aes(x = reorder(AVISIT, AVISITN), y = mean,
                      colour = per, group = per)) +
  geom_hline(yintercept = 0, linetype = "dotted") +
  geom_line(position = position_dodge(width = 0.3)) +
  geom_point(position = position_dodge(width = 0.3), size = 1.8) +
  geom_errorbar(aes(ymin = lo, ymax = hi),
                width = 0.2, position = position_dodge(width = 0.3)) +
  facet_wrap(~ PARAM, scales = "free_y") +
  labs(x = "Scheduled Visit", y = "Mean Change from Baseline (+/- SD)",
       colour = "Period", title = ttl$titles[3], caption = ttl$footnotes[1]) +
  theme_bw() +
  theme(legend.position = "bottom", axis.text.x = element_text(angle = 45, hjust = 1))
# ggsave(file.path(env$out, "f_lab_change.png"), p, width = 10, height = 7, dpi = 300)
print(p)
