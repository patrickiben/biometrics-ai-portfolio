################################################################################
# FIGURE    : f_lab_change  (Crossover - 2x2 or Williams)
# TITLE     : Mean (+/- SE) Change from Baseline in Laboratory Analytes
#             Over Time by Treatment
# POPULATION: Safety Population (SAFFL == "Y"), analysis records (ANL01FL=="Y")
# INPUT     : ADLB (PARAMCD; CHG, AVISIT/AVISITN, ANL01FL)
# NOTE      : PSEUDOCODE. Mean change-from-baseline (+/- SE) by nominal visit,
#             one line per ACTUAL treatment (dv$trtvar = TRTA). Crossover:
#             within-participant, so each participant contributes to every treatment
#             line; visits are the per-period nominal lab schedule (AVISITN).
#             Faceted by analyte. Error bars = SE = SD/sqrt(n).
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("CROSSOVER")                 # trtvar = TRTA ; byperiod = APERIOD/APERIODC

## analytes to display (one facet each) -- liver-function panel, matches SAS twin
analytes <- c("ALT","AST","BILI","CREAT","ALP","GGT")

lb <- adam$adlb %>%
  filter(SAFFL == "Y", ANL01FL == "Y", AVISITN > 0,
         PARAMCD %in% analytes, !is.na(CHG)) %>%
  mutate(trt   = .data[[dv$trtvar]],
         visit = AVISIT,
         vn    = AVISITN)

## mean +/- SE change-from-baseline by treatment x analyte x visit
chg <- lb %>%
  group_by(PARAM, trt, vn, visit) %>%
  summarise(n    = sum(!is.na(CHG)),
            mean = mean(CHG, na.rm = TRUE),
            sd   = sd(CHG,   na.rm = TRUE),
            se   = sd / sqrt(pmax(n, 1)),
            .groups = "drop") %>%
  arrange(PARAM, trt, vn)

ttl <- tfl_titles(num = "14.3.4.5", type = "Figure",
   text = "Mean (+/- SE) Change from Baseline in Laboratory Analytes Over Time by Treatment",
   pop  = "Safety Population",
   foot = "Points = mean change from within-period baseline (post-baseline analysis records, ANL01FL='Y', AVISITN>0); error bars = +/- 1 SE (SD/sqrt(n)). Crossover within-participant: each participant contributes to every treatment received. Source: ADLB (CHG).")

pd <- position_dodge(width = 0.3)
p <- ggplot(chg, aes(x = reorder(visit, vn), y = mean,
                     colour = trt, group = trt)) +
  geom_hline(yintercept = 0, linetype = "dotted") +
  geom_line(position = pd) +
  geom_point(position = pd, size = 1.8) +
  geom_errorbar(aes(ymin = mean - se, ymax = mean + se),
                width = 0.2, position = pd) +
  facet_wrap(~ PARAM, scales = "free_y") +
  labs(x = "Nominal Visit", y = "Mean Change from Baseline (+/- SE)",
       colour = "Treatment", title = ttl$titles[3], caption = ttl$footnotes[1]) +
  theme_bw() +
  theme(legend.position = "bottom",
        axis.text.x = element_text(angle = 45, hjust = 1))
# ggsave(file.path(env$out, "f_lab_change.png"), p, width = 10, height = 7, dpi = 300)
print(p)
