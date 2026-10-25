################################################################################
# FIGURE    : f_cqtc_hysteresis  (Multiple Ascending Dose)
# TITLE     : Mean (+/-SE) ddQTcF versus Mean Plasma Concentration in Time Order
#             (Hysteresis Loop) by Dose and Profile Day
# POPULATION: C-QTc Analysis Set (PKFL == "Y" and SAFFL == "Y"), active doses
# INPUT     : ADEG (PARAMCD == "QTCF"; CHG, ADY, ATPTN), ADPC (PARAMCD == "CONC";
#             AVAL, ADY, ATPTN), time-matched on profile day and nominal time
# NOTE      : PSEUDOCODE. Descriptive companion to t_cqtc_hysteresis (the signed
#             loop-area check run before the C-QTc analysis). ddQTcF = individual
#             dQTcF (CHG) minus the time-matched placebo mean dQTcF on the same
#             profile day and nominal time (placebo pooled); use the C-QTc
#             analysis dataset's ddQTcF instead if the ADaM specification carries
#             one. Rows = profile days (Day 1 and the steady-state day named in
#             the SAP, PROFDAYS), columns = doses; one panel per dose and day.
#             Points = mean concentration (x) and mean ddQTcF (y) at each nominal
#             time over the dosing interval, joined IN TIME ORDER with arrows;
#             bars = +/-1 SE of ddQTcF; dotted segment closes the path back to
#             predose (at steady state the predose point is the trough). A
#             counterclockwise loop suggests the effect lags concentration; the
#             figure is not the test (see Table 14.3.6.5). Descriptive only.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("MAD")                       # TRT01A = dose level; TRT01AN = dose

PCCD     <- "CONC"     # parent analyte PARAMCD in ADPC
PROFDAYS <- c(1, 14)   # full-profile days per the SAP (Day 1 and steady state)

## ---- dQTcF and the time-matched placebo mean (by profile day and time) --------
eg <- adam$adeg %>%
  filter(SAFFL == "Y", ANL01FL == "Y", PARAMCD == "QTCF", ADY %in% PROFDAYS, !is.na(CHG)) %>%
  transmute(USUBJID, trt = .data[[dv$trtvar]], dose = .data[[dv$trtnvar]], ADY, ATPTN, CHG)
pbo <- eg %>% filter(dose == 0) %>%
  group_by(ADY, ATPTN) %>% summarise(pbo_chg = mean(CHG), .groups = "drop")
ddq <- eg %>% filter(dose > 0) %>%
  inner_join(pbo, by = c("ADY", "ATPTN")) %>%
  mutate(ddqtcf = CHG - pbo_chg)                  # ddQTcF, ms

## ---- time-matched concentrations (C-QTc analysis set) -------------------------
pc <- adam$adpc %>%
  filter(PKFL == "Y", PARAMCD == PCCD, ADY %in% PROFDAYS, !is.na(AVAL)) %>%
  transmute(USUBJID, ADY, ATPTN, conc = AVAL)
cq <- ddq %>% inner_join(pc, by = c("USUBJID", "ADY", "ATPTN"))

## ---- mean concentration and mean (SE) ddQTcF per dose x day x nominal time ----
loop <- cq %>%
  group_by(trt, dose, ADY, ATPTN) %>%
  summarise(n    = n_distinct(USUBJID),
            conc = mean(conc),
            mean = mean(ddqtcf),
            se   = sd(ddqtcf) / sqrt(n),
            .groups = "drop") %>%
  arrange(dose, ADY, ATPTN) %>%
  mutate(trt = factor(trt, levels = unique(trt[order(dose)])),
         day = factor(paste("Day", ADY), levels = paste("Day", PROFDAYS)))
closer <- loop %>% group_by(trt, day) %>%
  summarise(x = last(conc), y = last(mean), xend = first(conc), yend = first(mean), .groups = "drop")

ttl <- tfl_titles(num = "14.3.6.4", type = "Figure",
   text = "Mean (+/-SE) ddQTcF versus Mean Plasma Concentration in Time Order (Hysteresis Loop) by Dose and Profile Day",
   pop  = "C-QTc Analysis Set",
   foot = paste("ddQTcF = change from baseline in QTcF minus the time-matched placebo mean on the same day (placebo pooled).",
                "Points = means at each nominal time over the dosing interval, joined in time order (arrows); bars = +/-1 SE across active participants (the placebo mean's own variance is not included);",
                "dotted segment closes the path back to predose (the trough at steady state).",
                "A counterclockwise loop suggests the effect lags concentration; Table 14.3.6.5 gives the test.",
                "Descriptive only."))

p <- ggplot(loop, aes(conc, mean)) +
  geom_hline(yintercept = 0, colour = "grey60") +
  geom_errorbar(aes(ymin = mean - se, ymax = mean + se), width = 0, colour = "grey45") +
  geom_path(arrow = grid::arrow(length = grid::unit(2.5, "mm"), type = "closed")) +
  geom_segment(data = closer, aes(x = x, y = y, xend = xend, yend = yend), linetype = "dotted") +
  geom_point(size = 1.8) +
  facet_grid(day ~ trt, scales = "free_x") +
  labs(x = sprintf("Mean plasma concentration (%s)", PCCD), y = "Mean ddQTcF (ms) +/- SE",
       title = ttl$titles[3], caption = str_wrap(ttl$footnotes[1], 150)) +
  theme_bw()
# ggsave(file.path(env$out, "f_cqtc_hysteresis.png"), p, width = 11, height = 7, dpi = 300)
print(p)
