################################################################################
# FIGURE    : f_cqtc_hysteresis  (Single Ascending Dose)
# TITLE     : Mean (+/-SE) ddQTcF versus Mean Plasma Concentration in Time Order
#             (Hysteresis Loop) by Dose
# POPULATION: C-QTc Analysis Set (PKFL == "Y" and SAFFL == "Y"), active doses
# INPUT     : ADEG (PARAMCD == "QTCF"; CHG, ATPTN), ADPC (PARAMCD == "CONC";
#             AVAL, ATPTN), time-matched on nominal post-dose time
# NOTE      : PSEUDOCODE. Descriptive companion to t_cqtc_hysteresis (the signed
#             loop-area check run before the C-QTc analysis). ddQTcF = individual
#             dQTcF (CHG) minus the time-matched placebo mean dQTcF at the same
#             nominal time (placebo pooled across cohorts); use the C-QTc analysis
#             dataset's ddQTcF instead if the ADaM specification carries one. One
#             panel per dose; points = mean concentration (x) and mean ddQTcF (y)
#             at each nominal time, joined IN TIME ORDER with arrows, vertical
#             bars = +/- 1 SE of ddQTcF. A counterclockwise loop suggests the
#             effect lags concentration; the figure is not the test (see Table
#             14.3.5.5). Single dose -> the Day 1 post-dose profile, closed back to
#             predose. Descriptive only; no model is drawn.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SAD")                       # TRT01A = dose level; TRT01AN = dose

PCCD <- "CONC"                                    # parent analyte PARAMCD in ADPC

## ---- dQTcF and the time-matched placebo mean ---------------------------------
eg <- adam$adeg %>%
  filter(SAFFL == "Y", ANL01FL == "Y", PARAMCD == "QTCF", !is.na(CHG)) %>%
  transmute(USUBJID, trt = .data[[dv$trtvar]], dose = .data[[dv$trtnvar]], ATPTN, CHG)
pbo <- eg %>% filter(dose == 0) %>%
  group_by(ATPTN) %>% summarise(pbo_chg = mean(CHG), .groups = "drop")
ddq <- eg %>% filter(dose > 0) %>%
  inner_join(pbo, by = "ATPTN") %>%
  mutate(ddqtcf = CHG - pbo_chg)                  # ddQTcF, ms

## ---- time-matched concentrations (C-QTc analysis set) -------------------------
pc <- adam$adpc %>%
  filter(PKFL == "Y", PARAMCD == PCCD, !is.na(AVAL)) %>%
  transmute(USUBJID, ATPTN, conc = AVAL)          # BLQ already 0 in ADaM per the SAP
cq <- ddq %>% inner_join(pc, by = c("USUBJID", "ATPTN"))

## ---- mean concentration and mean (SE) ddQTcF per dose x nominal time ---------
loop <- cq %>%
  group_by(trt, dose, ATPTN) %>%
  summarise(n    = n_distinct(USUBJID),
            conc = mean(conc),
            mean = mean(ddqtcf),
            se   = sd(ddqtcf) / sqrt(n),
            .groups = "drop") %>%
  arrange(dose, ATPTN) %>%
  mutate(trt = factor(trt, levels = unique(trt[order(dose)])))
## closing segment: last nominal time back to predose, drawn dotted
closer <- loop %>% group_by(trt) %>%
  summarise(x = last(conc), y = last(mean), xend = first(conc), yend = first(mean), .groups = "drop")

ttl <- tfl_titles(num = "14.3.5.4", type = "Figure",
   text = "Mean (+/-SE) ddQTcF versus Mean Plasma Concentration in Time Order (Hysteresis Loop) by Dose",
   pop  = "C-QTc Analysis Set",
   foot = paste("ddQTcF = change from baseline in QTcF minus the time-matched placebo mean (placebo pooled).",
                "Points = means at each nominal post-dose time, joined in time order (arrows); bars = +/-1 SE;",
                "dotted segment closes the path from the last time back to predose.",
                "A counterclockwise loop suggests the effect lags concentration; Table 14.3.5.5 gives the test.",
                "Descriptive only."))

p <- ggplot(loop, aes(conc, mean)) +
  geom_hline(yintercept = 0, colour = "grey60") +
  geom_errorbar(aes(ymin = mean - se, ymax = mean + se), width = 0, colour = "grey45") +
  geom_path(arrow = grid::arrow(length = grid::unit(2.5, "mm"), type = "closed")) +
  geom_segment(data = closer, aes(x = x, y = y, xend = xend, yend = yend), linetype = "dotted") +
  geom_point(size = 1.8) +
  geom_text(data = loop %>% group_by(trt) %>% slice_max(conc, n = 1, with_ties = FALSE),
            aes(label = paste0(ATPTN, " h")), vjust = -0.9, size = 3) +   # label the time of the peak mean concentration
  facet_wrap(~ trt, scales = "free_x") +
  labs(x = sprintf("Mean plasma concentration (%s)", PCCD), y = "Mean ddQTcF (ms) +/- SE",
       title = ttl$titles[3], caption = str_wrap(ttl$footnotes[1], 150)) +
  theme_bw()
# ggsave(file.path(env$out, "f_cqtc_hysteresis.png"), p, width = 10, height = 6, dpi = 300)
print(p)
