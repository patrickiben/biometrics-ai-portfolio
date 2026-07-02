################################################################################
# FIGURE    : f_lab_lft_scatter  (Crossover - 2x2 or Williams)
# TITLE     : Maximum Post-Baseline ALT vs Maximum Total Bilirubin
#             (multiples of ULN)
# POPULATION: Safety Population (SAFFL == "Y"), on-treatment
# INPUT     : ADLB (PARAMCD in ALT, AST, BILI; ratio-to-ULN R2ULN or AVAL/A1HI)
# NOTE      : PSEUDOCODE. Per-participant peak (max) ALT/ULN (x) vs Total
#             Bilirubin/ULN (y), both log scale. Crossover: within-participant, so a
#             participant's peak is taken WITHIN each treatment period and the point
#             is colored by ACTUAL treatment (dv$trtvar = TRTA); the same
#             participant can appear once per treatment. Reference lines at 3xULN
#             (ALT) and 2xULN (bilirubin) are the standard regulatory
#             thresholds. Neutral liver-safety scatter.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("CROSSOVER")                 # trtvar = TRTA ; byperiod = APERIOD/APERIODC

## ratio-to-ULN; prefer ADaM-provided R2ULN, else AVAL / A1HI (guard A1HI)
lb <- adam$adlb %>%
  filter(SAFFL == "Y", ONTRTFL == "Y", PARAMCD %in% c("ALT","AST","BILI")) %>%
  mutate(trt    = .data[[dv$trtvar]],
         period = .data[[dv$byperiod[2]]],
         xuln   = coalesce(R2ULN, ifelse(!is.na(A1HI), AVAL / A1HI, NA_real_)))

## per-participant peak (max) per analyte WITHIN treatment, then one row per
## participant x treatment (crossover within-participant peaks)
peak <- lb %>%
  group_by(USUBJID, trt, PARAMCD) %>%
  summarise(peak = max(xuln, na.rm = TRUE), .groups = "drop") %>%
  pivot_wider(names_from = PARAMCD, values_from = peak, names_prefix = "p_") %>%
  mutate(p_ALT  = pmax(p_ALT,  0.01),                 # log-safe
         p_BILI = pmax(p_BILI, 0.01),
         flag   = p_ALT >= 3 & p_BILI >= 2)           # both elevated -> label

ttl <- tfl_titles(num = "14.3.4.4", type = "Figure",
   text = "Maximum Post-Baseline ALT vs Maximum Total Bilirubin (multiples of ULN)",
   pop  = "Safety Population",
   foot = "Reference lines: ALT = 3xULN, Total Bilirubin = 2xULN. Both axes log scale. Each point = one participant's peak on-treatment value within a treatment period; colored by treatment.")

p <- ggplot(peak, aes(p_ALT, p_BILI, colour = trt)) +
  geom_vline(xintercept = 3, linetype = "dashed") +
  geom_hline(yintercept = 2, linetype = "dashed") +
  geom_point(size = 2) +
  ggrepel::geom_text_repel(data = ~ filter(.x, flag),
                           aes(label = str_extract(USUBJID, "[^-]+$")), show.legend = FALSE) +
  scale_x_log10(limits = c(0.1, 100)) + scale_y_log10(limits = c(0.1, 20)) +
  labs(x = "Peak ALT (xULN)", y = "Peak Total Bilirubin (xULN)",
       colour = "Treatment", title = ttl$titles[3], caption = ttl$footnotes[1]) +
  theme_bw() + theme(legend.position = "bottom")
# ggsave(file.path(env$out, "f_lab_lft_scatter.png"), p, width = 8, height = 6, dpi = 300)
print(p)
