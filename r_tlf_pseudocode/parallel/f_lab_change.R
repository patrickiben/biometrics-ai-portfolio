################################################################################
# FIGURE    : f_lab_change  (Parallel-group)
# TITLE     : Mean (+/- SD) Change from Baseline in Laboratory Values Over Time
#             by Treatment
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADLB (PARAMCD/PARAM, CHG, AVISIT/AVISITN, ANL01FL)
# NOTE      : PSEUDOCODE. Mean change from baseline (CHG) by scheduled visit,
#             one panel per analyte, one line/colour per treatment arm (= dose
#             level), error bars = +/- 1 SD. Parallel-group: arms overlaid on a
#             common time axis (between-group, descriptive). n shown per point.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("PARALLEL")                 # colour/line = TRT01A (= dose)

## post-baseline analysis records (one per participant/param/visit via ANL01FL)
lb <- adam$adlb %>%
  filter(SAFFL == "Y", ANL01FL == "Y", AVISITN > 0, !is.na(CHG),
         PARAMCD %in% c("ALT","AST","BILI","CREAT","K","HGB","WBC","PLAT")) %>%
  mutate(trt = .data[[dv$trtvar]])

## --- mean +/- SD of change, per param x visit x arm ------------------------
summ <- descstat(lb, var = "CHG", by = c("PARAMCD","PARAM","AVISITN","AVISIT", dv$trtvar)) %>%
  transmute(PARAM, AVISITN, AVISIT, trt = .data[[dv$trtvar]],
            n, mean, sd,
            lo = mean - sd, hi = mean + sd) %>%
  arrange(PARAM, AVISITN)

ttl <- tfl_titles(num = "14.3.4.4", type = "Figure",
   text = "Mean (+/- SD) Change from Baseline in Laboratory Values Over Time",
   pop  = "Safety Population",
   foot = paste("Points = arithmetic mean change from baseline by scheduled visit;",
                "error bars = +/- 1 SD; arms (dose levels) overlaid. Descriptive,",
                "between-group (parallel). Visits with n < 3 may be suppressed per SAP."))

## --- faceted line plot: x = visit (ordered by AVISITN), y = mean CHG -------
p <- ggplot(summ, aes(x = reorder(AVISIT, AVISITN), y = mean,
                      colour = trt, group = trt)) +
  geom_hline(yintercept = 0, linetype = "dotted") +
  geom_line(position = position_dodge(width = 0.3)) +
  geom_point(position = position_dodge(width = 0.3), size = 1.8) +
  geom_errorbar(aes(ymin = lo, ymax = hi),
                width = 0.2, position = position_dodge(width = 0.3)) +
  facet_wrap(~ PARAM, scales = "free_y") +
  labs(x = "Scheduled Visit", y = "Mean Change from Baseline (+/- SD)",
       colour = "Treatment", title = ttl$titles[3], caption = ttl$footnotes[1]) +
  theme_bw() +
  theme(legend.position = "bottom", axis.text.x = element_text(angle = 45, hjust = 1))
# ggsave(file.path(env$out, "f_lab_change.png"), p, width = 10, height = 7, dpi = 300)
print(p)
