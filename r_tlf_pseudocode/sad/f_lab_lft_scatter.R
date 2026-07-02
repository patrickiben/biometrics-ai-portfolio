################################################################################
# FIGURE    : f_lab_lft_scatter  (Single Ascending Dose)
# TITLE     : Maximum Post-Baseline ALT vs Maximum Total Bilirubin
#             (multiples of ULN)
# POPULATION: Safety Population (SAFFL == "Y"), on-treatment
# INPUT     : ADLB (PARAMCD in ALT, AST, BILI; ratio-to-ULN)
# NOTE      : PSEUDOCODE. SAD = parallel dose cohorts; colour = DOSE LEVEL
#             (dv$trtvar = TRT01A, ordered by TRT01AN so escalation reads left->
#             right in the legend; placebo pooled). Per-participant peak (max)
#             ALT/ULN (x) vs Total Bilirubin/ULN (y), both log scale. Reference
#             lines at 3xULN (ALT) and 2xULN (bilirubin) are the standard
#             regulatory thresholds. Neutral liver-safety scatter.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SAD")                      # colour = TRT01A/TRT01AN (dose level)

## ratio-to-ULN; prefer ADaM-provided R2ULN, else AVAL / A1HI
lb <- adam$adlb %>%
  filter(SAFFL == "Y", ONTRTFL == "Y", PARAMCD %in% c("ALT","AST","BILI")) %>%
  mutate(xuln = coalesce(R2ULN, AVAL / A1HI))

## per-participant peak (max) per analyte, then one row per participant.
## Carry both the dose label (trt) and its numeric order (trtn) so the dose
## colour scale is ordered by ASCENDING dose, the SAD escalation axis.
peak <- lb %>%
  group_by(USUBJID,
           trt  = .data[[dv$trtvar]],
           trtn = .data[[dv$trtnvar]],
           PARAMCD) %>%
  summarise(peak = max(xuln, na.rm = TRUE), .groups = "drop") %>%
  pivot_wider(names_from = PARAMCD, values_from = peak, names_prefix = "p_") %>%
  mutate(p_ALT  = pmax(p_ALT,  0.01),                 # log-safe
         p_BILI = pmax(p_BILI, 0.01),
         flag   = p_ALT >= 3 & p_BILI >= 2,           # both elevated -> label
         trt    = reorder(trt, trtn))                 # legend in ascending dose order

ttl <- tfl_titles(num = "14.3.4.5", type = "Figure",
   text = "Maximum Post-Baseline ALT vs Maximum Total Bilirubin (multiples of ULN)",
   pop  = "Safety Population",
   foot = paste("Reference lines: ALT = 3xULN, Total Bilirubin = 2xULN. Both axes",
                "log scale. Each point = one participant's peak on-treatment value,",
                "coloured by dose level (placebo pooled), ordered ascending."))

p <- ggplot(peak, aes(p_ALT, p_BILI, colour = trt)) +
  geom_vline(xintercept = 3, linetype = "dashed") +
  geom_hline(yintercept = 2, linetype = "dashed") +
  geom_point(size = 2) +
  ggrepel::geom_text_repel(data = ~ filter(.x, flag),
                           aes(label = str_extract(USUBJID, "[^-]+$")), show.legend = FALSE) +
  scale_x_log10(limits = c(0.1, 100)) + scale_y_log10(limits = c(0.1, 20)) +
  labs(x = "Peak ALT (xULN)", y = "Peak Total Bilirubin (xULN)",
       colour = "Dose Level", title = ttl$titles[3], caption = ttl$footnotes[1]) +
  theme_bw() + theme(legend.position = "bottom")
# ggsave(file.path(env$out, "f_lab_lft_scatter.png"), p, width = 8, height = 6, dpi = 300)
print(p)
