################################################################################
# FIGURE    : f_qtc_change  (Multiple Ascending Dose)
# TITLE     : Mean (+/-95% CI) Change from Baseline in QTcF by Timepoint
# POPULATION: Safety Population (SAFFL == "Y"), post-baseline
# INPUT     : ADEG (PARAMCD == "QTCF"; CHG, ATPT/ATPTN)
# NOTE      : PSEUDOCODE. DESCRIPTIVE mean change-from-baseline (CHG) QTcF with
#             +/-95% CI error bars over NOMINAL POST-DOSE TIMEPOINTS (ATPTN)
#             spanning the repeat-dosing period, one line per dose cohort.
#             Horizontal reference lines at the ICH E14 thresholds of 30 ms and
#             60 ms (plus a 0 line). No model is fitted; the figure is purely
#             descriptive. MAD = parallel dose cohorts; between-cohort comparison,
#             colour = dv$trtvar (TRT01A = dose level; placebo pooled). Day 1 vs
#             steady-state day timepoints carry any dose- and accumulation-driven
#             QTc effect.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("MAD")

## post-baseline QTcF analysis records (CHG defined)
eg <- adam$adeg %>%
  filter(SAFFL == "Y", ANL01FL == "Y", PARAMCD == "QTCF", ATPTN > 0, !is.na(CHG)) %>%
  mutate(trt = .data[[dv$trtvar]],              # dose-level cohort (placebo pooled)
         tp  = factor(ATPT, levels = unique(ATPT[order(ATPTN)])))   # nominal post-dose timepoint

## DESCRIPTIVE mean +/- 95% CI of change by cohort x nominal timepoint
sumdat <- eg %>%
  group_by(trt, tp) %>%
  summarise(n    = sum(!is.na(CHG)),
            mean = mean(CHG, na.rm = TRUE),
            se   = sd(CHG, na.rm = TRUE) / sqrt(n),
            .groups = "drop") %>%
  mutate(lo = mean - qt(0.975, df = pmax(n - 1, 1)) * se,    # 95% CI of the mean
         hi = mean + qt(0.975, df = pmax(n - 1, 1)) * se)

ttl <- tfl_titles(num = "14.3.6.3", type = "Figure",
   text = "Mean (+/-95% CI) Change from Baseline in QTcF by Timepoint",
   pop  = "Safety Population",
   foot = paste("QTcF = Fridericia-corrected QT. Points = descriptive dose-cohort mean change;",
                "error bars = 95% CI of the mean. Horizontal reference lines at 0, 30 and 60 ms",
                "(ICH E14 thresholds). X-axis = nominal post-dose timepoints (ATPTN).",
                "Baseline = pre-first-dose. Timepoints span the repeat-dosing period",
                "(placebo pooled). No model is fitted; the figure is descriptive."))

pd <- position_dodge(width = 0.3)
p <- ggplot(sumdat, aes(x = tp, y = mean, colour = trt, group = trt)) +
  geom_hline(yintercept = 0,  linetype = "solid") +
  geom_hline(yintercept = 30, linetype = "dotted", colour = "grey50") +   # 30 ms ICH E14 threshold
  geom_hline(yintercept = 60, linetype = "dotted", colour = "grey50") +   # 60 ms ICH E14 threshold
  geom_errorbar(aes(ymin = lo, ymax = hi), width = 0.2, position = pd) +
  geom_line(position = pd) +
  geom_point(size = 2, position = pd) +
  labs(x = "Nominal Post-dose Timepoint", y = "Mean change in QTcF from baseline (+/-95% CI), ms",
       colour = "Dose cohort", title = ttl$titles[3], caption = ttl$footnotes[1]) +
  theme_bw() +
  theme(legend.position = "bottom",
        axis.text.x = element_text(angle = 45, hjust = 1))
# ggsave(file.path(env$out, "f_qtc_change.png"), p, width = 9, height = 6, dpi = 300)
print(p)
