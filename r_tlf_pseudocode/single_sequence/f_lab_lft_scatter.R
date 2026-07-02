################################################################################
# FIGURE    : f_lab_lft_scatter  (Single-/Fixed-Sequence DDI)
# TITLE     : Maximum Post-Baseline ALT vs Maximum Total Bilirubin
#             (multiples of ULN) by Period
# POPULATION: Safety Population (SAFFL == "Y"), on-treatment
# INPUT     : ADLB (PARAMCD in ALT, AST, BILI; ratio-to-ULN; APERIOD/APERIODC)
# NOTE      : PSEUDOCODE. Per-participant peak (max) ALT/ULN (x) vs Total Bilirubin/ULN
#             (y) WITHIN PERIOD, both log scale, faceted by period (Period 1 =
#             reference / victim alone, Period 2 = test / victim + perpetrator) so
#             a perpetrator-driven shift is visible. Reference lines at 3xULN (ALT)
#             and 2xULN (bilirubin) are the standard regulatory thresholds.
#             Neutral liver-safety scatter.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SINGLESEQ")                 # byperiod = c("APERIOD","APERIODC")
options(tfl.study = env$study)
perC <- dv$byperiod[2]                           # character period label column

## ratio-to-ULN; prefer ADaM-provided R2ULN, else AVAL / A1HI
lb <- adam$adlb %>%
  filter(SAFFL == "Y", ONTRTFL == "Y", PARAMCD %in% c("ALT","AST","BILI")) %>%
  mutate(per  = .data[[perC]],
         xuln = coalesce(R2ULN, AVAL / A1HI))

## per-participant peak (max) per analyte WITHIN PERIOD, then one row per subj x period
peak <- lb %>% group_by(USUBJID, per, PARAMCD) %>%
  summarise(peak = max(xuln, na.rm = TRUE), .groups = "drop") %>%
  pivot_wider(names_from = PARAMCD, values_from = peak, names_prefix = "p_") %>%
  mutate(p_ALT  = pmax(p_ALT,  0.01),                 # log-safe
         p_BILI = pmax(p_BILI, 0.01),
         flag   = p_ALT >= 3 & p_BILI >= 2)           # both elevated -> label

ttl <- tfl_titles(num = "14.3.5.1", type = "Figure",
   text = "Maximum Post-Baseline ALT vs Maximum Total Bilirubin (multiples of ULN) by Period",
   pop  = "Safety Population",
   foot = paste("Single-fixed-sequence DDI: Period 1 = reference (victim alone),",
                "Period 2 = test (victim + perpetrator). Reference lines: ALT = 3xULN,",
                "Total Bilirubin = 2xULN. Both axes log scale. Each point = one",
                "participant's peak on-treatment value within the period."))

p <- ggplot(peak, aes(p_ALT, p_BILI, colour = per)) +
  geom_vline(xintercept = 3, linetype = "dashed") +
  geom_hline(yintercept = 2, linetype = "dashed") +
  geom_point(size = 2) +
  ggrepel::geom_text_repel(data = ~ filter(.x, flag),
                           aes(label = str_extract(USUBJID, "[^-]+$")), show.legend = FALSE) +
  facet_wrap(~ per) +                                  # one panel per period
  scale_x_log10(limits = c(0.1, 100)) + scale_y_log10(limits = c(0.1, 20)) +
  labs(x = "Peak ALT (xULN)", y = "Peak Total Bilirubin (xULN)",
       colour = "Period", title = ttl$titles[3], caption = ttl$footnotes[1]) +
  theme_bw() + theme(legend.position = "bottom")
# ggsave(file.path(env$out, "f_lab_lft_scatter.png"), p, width = 10, height = 6, dpi = 300)
print(p)
