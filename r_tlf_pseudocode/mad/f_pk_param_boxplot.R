################################################################################
# FIGURE    : f_pk_param_boxplot  (MAD - Multiple Ascending Dose / per-cohort)
# TITLE     : Distribution of Plasma PK Parameters by Dose Cohort and Dosing Day
#             (Box Plots)
# POPULATION: PK Parameter Population (PKFL == "Y")
# INPUT     : ADPP (PARAMCD = CMAX/CMAXSS, AUCLST/AUCTAU, CMINSS, CTROUGH, ...)
# NOTE      : PSEUDOCODE. Box plots of exposure parameters across ascending dose
#             cohorts (TRT01A), individual points overlaid (jitter). Exposure
#             params on a log y-axis so the dose-ordered escalation is visible;
#             Tmax on a linear axis (a time, not an exposure). MAD: fill = dosing
#             day (Day 1 single dose vs Day N steady state) dodged within each
#             cohort, so accumulation Day1->DayN is visible alongside the
#             ascending-dose trend. Cohorts ordered low -> high (TRT01AN);
#             between-cohort spread descriptive (formal trend -> dose-prop power
#             model in t_dose_proportionality_ss.R).
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("MAD")

## --- exposure parameters (log axis), Day 1 single-dose vs Day N steady state -
## CMAX/AUCLST = Day 1; CMAXSS/AUCTAU = Day N. Map to common labels for paneling.
expo_cd <- c("CMAX","AUCLST","CMAXSS","AUCTAU")
expo <- adam$adpp %>%
  filter(PKFL == "Y", PARAMCD %in% expo_cd, AVAL > 0) %>%
  mutate(trt   = factor(.data[[dv$trtvar]],
                        levels = unique(.data[[dv$trtvar]][order(.data[[dv$trtnvar]])])),  # dose order
         day   = factor(AVISIT),                            # Day 1 / Day N
         panel = case_when(PARAMCD %in% c("CMAX","CMAXSS")   ~ "Cmax",
                           PARAMCD %in% c("AUCLST","AUCTAU") ~ "AUC"),
         panel = factor(panel, levels = c("Cmax","AUC")))

ttl <- tfl_titles(num = "14.4.2.3", type = "Figure",
   text = "Distribution of Plasma Pharmacokinetic Parameters by Dose Cohort and Dosing Day",
   pop  = "Pharmacokinetic Parameter Population",
   foot = paste("Box = median and IQR; whiskers = 1.5*IQR; points = individual participants.",
                "Exposure parameters on log y-axis. Dose cohorts ordered low -> high (TRT01AN);",
                "fill = dosing day (Day 1 single dose vs Day N steady state).",
                "Descriptive; formal steady-state dose-proportionality via power model",
                "(t_dose_proportionality_ss.R) and accumulation in t_accumulation.R."))

## exposure box plots, faceted by parameter family; fill/dodge by dosing day
p_expo <- ggplot(expo, aes(trt, AVAL, fill = day)) +
  geom_boxplot(outlier.shape = NA, alpha = 0.5, position = position_dodge(0.8)) +
  geom_point(position = position_jitterdodge(jitter.width = 0.12, dodge.width = 0.8),
             size = 1.0, alpha = 0.5) +
  scale_y_log10() +
  facet_wrap(~ panel, scales = "free_y") +
  labs(x = "Dose Cohort", y = "Parameter value (log scale)", fill = "Dosing Day",
       title = ttl$titles[3], caption = ttl$footnotes[1]) +
  theme_bw() + theme(legend.position = "bottom",
                     axis.text.x = element_text(angle = 30, hjust = 1))

## Tmax separately on a LINEAR axis (a time; Median (Min,Max)) - both occasions
tmax <- adam$adpp %>% filter(PKFL == "Y", PARAMCD == "TMAX") %>%
  mutate(trt = factor(.data[[dv$trtvar]],
                      levels = unique(.data[[dv$trtvar]][order(.data[[dv$trtnvar]])])),
         day = factor(AVISIT))
p_tmax <- ggplot(tmax, aes(trt, AVAL, fill = day)) +
  geom_boxplot(outlier.shape = NA, alpha = 0.5, position = position_dodge(0.8)) +
  geom_point(position = position_jitterdodge(jitter.width = 0.12, dodge.width = 0.8),
             size = 1.0, alpha = 0.5) +
  labs(x = "Dose Cohort", y = "Tmax (h)", fill = "Dosing Day", title = "Tmax") +
  theme_bw() + theme(legend.position = "bottom",
                     axis.text.x = element_text(angle = 30, hjust = 1))

# ggsave(file.path(env$out, "f_pk_param_boxplot.png"),      p_expo, width = 10, height = 6, dpi = 300)
# ggsave(file.path(env$out, "f_pk_param_boxplot_tmax.png"), p_tmax, width = 7,  height = 5, dpi = 300)
print(p_expo)
print(p_tmax)
