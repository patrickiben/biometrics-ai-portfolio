################################################################################
# FIGURE    : f_qtc_change  (Parallel-group)
# TITLE     : Mean (+/-SE) Change from Baseline in QTcF by Visit/Timepoint
# POPULATION: Safety Population (SAFFL == "Y"), post-baseline
# INPUT     : ADEG (PARAMCD == "QTCF")
# NOTE      : PSEUDOCODE. Mean change-from-baseline (CHG) QTcF with +/-1 SE error
#             bars over nominal post-baseline timepoints, one line per treatment
#             arm. Reference lines at 0 and +10 ms (the mean-effect threshold of
#             regulatory interest for a mean change-from-baseline QTc figure).
#             Parallel: between-arm comparison, colour = dv$trtvar (TRT01A).
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("PARALLEL")

## post-baseline QTcF analysis records (CHG defined)
eg <- adam$adeg %>%
  filter(SAFFL == "Y", ANL01FL == "Y", PARAMCD == "QTCF", !is.na(CHG)) %>%
  mutate(trt = .data[[dv$trtvar]],
         tp  = factor(AVISIT, levels = unique(AVISIT[order(AVISITN)])))
  ## (use ATPT/ATPTN ordering for rich PK-day timepoint plots if collected)

## mean +/- SE of change by arm x timepoint
sumdat <- eg %>%
  group_by(trt, tp) %>%
  summarise(n    = sum(!is.na(CHG)),
            mean = mean(CHG, na.rm = TRUE),
            se   = sd(CHG, na.rm = TRUE) / sqrt(n),
            .groups = "drop") %>%
  mutate(lo = mean - se, hi = mean + se)

ttl <- tfl_titles(num = "14.3.5.3", type = "Figure",
   text = "Mean (+/-SE) Change from Baseline in QTcF by Visit/Timepoint",
   pop  = "Safety Population",
   foot = "QTcF = Fridericia-corrected QT. Points = arm mean change; error bars = +/-1 SE. Reference lines at 0 and +10 ms. Baseline = pre-dose.")

pd <- position_dodge(width = 0.3)
p <- ggplot(sumdat, aes(x = tp, y = mean, colour = trt, group = trt)) +
  geom_hline(yintercept = 0,  linetype = "dashed") +
  geom_hline(yintercept = 10, linetype = "dotted", colour = "grey50") +   # +10 ms mean-effect threshold
  geom_errorbar(aes(ymin = lo, ymax = hi), width = 0.2, position = pd) +
  geom_line(position = pd) +
  geom_point(size = 2, position = pd) +
  labs(x = "Visit / timepoint", y = "Mean change in QTcF from baseline (+/-SE), ms",
       colour = "Treatment", title = ttl$titles[3], caption = ttl$footnotes[1]) +
  theme_bw() +
  theme(legend.position = "bottom",
        axis.text.x = element_text(angle = 45, hjust = 1))
# ggsave(file.path(env$out, "f_qtc_change.png"), p, width = 9, height = 6, dpi = 300)
print(p)
