################################################################################
# FIGURE    : f_pd_change  (Multiple Ascending Dose)
# TITLE     : Mean (+/- SE) Change from Baseline in Pharmacodynamic Endpoint
#             over the Multiple-Dose Period by Dose Level
# POPULATION: PD-Evaluable Population (PDFL == "Y")
# INPUT     : ADPD (PARAMCD = PD biomarker code; CHG, AVISIT/AVISITN, ADY,
#             ATPT/ATPTN)
# NOTE      : PSEUDOCODE. Mean change-from-baseline (CHG) profile over the
#             REPEATED-dose PD time course, one line per dose level, error bars =
#             SE. MAD = parallel cohorts, repeated dosing, one dose level per
#             participant -> grouping = dv$trtvar (TRT01A = dose level; placebo
#             pooled). Because dosing is repeated over several days, the x axis is
#             continuous treatment-time (ADY + within-day ATPTN) so the day-on-day
#             approach to a PD plateau is visible; a secondary panel tracks the
#             pre-dose (trough) PD value across dosing days as the steady-state
#             read. Ascending dose read across cohorts is by-eye (line per dose);
#             a formal dose response uses the power model (see t_pd_summary).
#             n per dose x time from ADPD (participants with a CHG value), NOT ADSL.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("MAD")                      # grouping = TRT01A (= dose level)

PDCD <- "INHIB"                                # PD endpoint of interest

pd <- adam$adpd %>%
  filter(PDFL == "Y", PARAMCD == PDCD, !is.na(CHG)) %>%
  ## order dose levels by their numeric value so cohorts ascend in the legend
  mutate(trt = factor(.data[[dv$trtvar]],
                      levels = unique(.data[[dv$trtvar]][order(.data[[dv$trtnvar]])])),
         ## continuous treatment-time over the multiple-dose period:
         ## study day + fractional within-day clock-time post-dose (ATPTN in hours)
         ttime = ADY + coalesce(ATPTN, 0) / 24)

## --- summarise CHG by dose level x treatment-time (ADPD-borne n) -------------
## continuous treatment-time keeps the repeated-dose course on a single axis
prof <- pd %>%
  group_by(trt, ttime) %>%
  summarise(
    n    = n_distinct(USUBJID),
    mean = mean(CHG, na.rm = TRUE),
    sd   = sd(CHG,   na.rm = TRUE),
    se   = sd / sqrt(n),
    .groups = "drop") %>%
  arrange(trt, ttime)

## --- MAD steady-state read: PRE-DOSE (trough) CHG by dosing day -------------
## trough = pre-dose records (ATPTN <= 0 or labelled pre-dose); plateau of the
## trough across days is the by-eye steady-state read (formal lmer slope in
## t_pd_summary). One point per dose level x dosing day.
trough <- pd %>%
  filter((!is.na(ATPTN) & ATPTN <= 0) | toupper(coalesce(ATPT, "")) == "PRE-DOSE") %>%
  group_by(trt, ADY) %>%
  summarise(n = n_distinct(USUBJID),
            mean = mean(CHG, na.rm = TRUE),
            se   = sd(CHG, na.rm = TRUE) / sqrt(n),
            .groups = "drop") %>%
  arrange(trt, ADY)

ttl <- tfl_titles(num = "14.4.6.2", type = "Figure",
   text = "Mean (+/- SE) Change from Baseline in Pharmacodynamic Endpoint over the Multiple-Dose Period by Dose Level",
   pop  = "Pharmacodynamic-Evaluable Population",
   foot = paste("Points = mean change from baseline; error bars = +/- 1 SE.",
                "n = PD-evaluable participants with a value at the timepoint (ADPD), not ADSL.",
                "Multiple ascending dose: one line per dose level (placebo pooled);",
                "x axis = continuous treatment-time over the repeated-dose period.",
                "Inset/secondary = pre-dose (trough) value by dosing day = PD steady-",
                "state read (plateau by eye; formal slope in t_pd_summary).",
                "Dashed line = no change. Parameter:", PDCD))

## main figure: full repeated-dose CHG time course
p_main <- ggplot(prof, aes(ttime, mean, colour = trt, group = trt)) +
  geom_hline(yintercept = 0, linetype = "dashed", colour = "grey50") +
  geom_line() +
  geom_point(size = 1.8) +
  geom_errorbar(aes(ymin = mean - se, ymax = mean + se), width = 0.2) +
  scale_x_continuous(name = "Treatment time (study day)") +
  labs(y = "Change from baseline (mean +/- SE)",
       colour = "Dose level", title = ttl$titles[3], caption = ttl$footnotes[1]) +
  theme_bw() + theme(legend.position = "bottom")

## companion figure: pre-dose (trough) CHG by dosing day = steady-state read
p_trough <- ggplot(trough, aes(ADY, mean, colour = trt, group = trt)) +
  geom_hline(yintercept = 0, linetype = "dashed", colour = "grey50") +
  geom_line() + geom_point(size = 2) +
  geom_errorbar(aes(ymin = mean - se, ymax = mean + se), width = 0.3) +
  scale_x_continuous(name = "Dosing day", breaks = sort(unique(trough$ADY))) +
  labs(y = "Pre-dose (trough) change from baseline (mean +/- SE)",
       colour = "Dose level", title = "Pre-dose (trough) PD by dosing day (steady-state read)") +
  theme_bw() + theme(legend.position = "bottom")

# ggsave(file.path(env$out, "f_pd_change.png"), p_main, width = 9, height = 6, dpi = 300)
# ggsave(file.path(env$out, "f_pd_change_trough.png"), p_trough, width = 9, height = 5, dpi = 300)
print(p_main)
print(p_trough)
