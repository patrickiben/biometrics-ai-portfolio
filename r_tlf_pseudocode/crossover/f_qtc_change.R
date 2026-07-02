################################################################################
# FIGURE    : f_qtc_change  (Crossover - 2x2 or Williams)
# TITLE     : Mean Change from Baseline in QTcF over Time by Treatment
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADEG (PARAMCD = QTCF; CHG from period baseline)
# NOTE      : PSEUDOCODE. Within-participant crossover view: mean (+/-90% CI) CHG in
#             QTcF from the PERIOD baseline over scheduled timepoint, one line
#             per treatment (dv$trtvar = TRTA). 90% CI is the conventional
#             thorough-QT presentation. Reference line at +10 ms (regulatory
#             threshold of clinical interest). Each participant contributes a within-
#             period QTcF change profile to the treatment given in that period.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("CROSSOVER")                 # trtvar = TRTA

eg <- adam$adeg %>%
  filter(SAFFL == "Y", ANL01FL == "Y", PARAMCD == "QTCF", !is.na(CHG)) %>%
  mutate(trt = .data[[dv$trtvar]])

## mean change + 90% CI of CHG by treatment x scheduled timepoint
mc <- eg %>%
  group_by(ATPTN, ATPT, trt) %>%
  summarise(n    = sum(!is.na(CHG)),
            mean = mean(CHG, na.rm = TRUE),
            se   = sd(CHG, na.rm = TRUE) / sqrt(pmax(n, 1)),
            .groups = "drop") %>%
  mutate(tcrit = qt(0.95, df = pmax(n - 1, 1)),     # two-sided 90% CI
         lo = mean - tcrit * se,
         hi = mean + tcrit * se)

ttl <- tfl_titles(num = "14.3.8.3", type = "Figure",
   text = "Mean Change from Baseline in QTcF over Time by Treatment",
   pop  = "Safety Population",
   foot = "Points = mean change from period baseline (QTcF); ribbon/bars = 90% CI. Reference lines at 0 and +10 ms (mean-effect threshold of clinical interest). One profile per treatment (crossover, within-participant).")

pd <- position_dodge(width = 0.3)
p <- ggplot(mc, aes(x = ATPTN, y = mean, colour = trt, group = trt)) +
  geom_hline(yintercept = 0,  linetype = "dashed") +
  geom_hline(yintercept = 10, linetype = "dotted", colour = "grey40") +
  geom_errorbar(aes(ymin = lo, ymax = hi), width = 0.2, position = pd) +
  geom_line(position = pd) + geom_point(size = 2, position = pd) +
  scale_x_continuous(breaks = sort(unique(mc$ATPTN)),
                     labels = function(b) mc$ATPT[match(b, mc$ATPTN)]) +
  labs(x = "Nominal time post-dose", y = "Mean change in QTcF (ms), 90% CI",
       colour = "Treatment", title = ttl$titles[3], caption = ttl$footnotes[1]) +
  theme_bw() + theme(legend.position = "bottom",
                     axis.text.x = element_text(angle = 45, hjust = 1))
# ggsave(file.path(env$out, "f_qtc_change.png"), p, width = 9, height = 6, dpi = 300)
print(p)
