################################################################################
# FIGURE    : f_pk_param_boxplot  (Parallel-group / per-dose)
# TITLE     : Distribution of Plasma PK Parameters by Treatment (Box Plots)
# POPULATION: PK Parameter Population (PKFL == "Y")
# INPUT     : ADPP (PARAMCD = CMAX, AUCLST, AUCIFO, ...)
# NOTE      : PSEUDOCODE. Box plots of exposure parameters across treatments
#             (= dose groups, TRT01A), with individual points overlaid (jitter).
#             Exposure params (Cmax, AUC) on a log y-axis to show the dose-
#             ordered spread; Tmax handled on a linear axis (it is a time, not
#             an exposure). Parallel: between-group spread, descriptive only.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("PARALLEL")

## --- exposure parameters (log axis) ----------------------------------------
expo_cd <- c("CMAX","AUCLST","AUCIFO")
expo <- adam$adpp %>%
  filter(PKFL == "Y", PARAMCD %in% expo_cd, AVAL > 0) %>%
  mutate(trt = factor(.data[[dv$trtvar]],
                      levels = unique(.data[[dv$trtvar]][order(.data[[dv$trtnvar]])])),  # dose order
         PARAM = factor(PARAM))

ttl <- tfl_titles(num = "14.4.2.3", type = "Figure",
   text = "Distribution of Plasma Pharmacokinetic Parameters by Treatment",
   pop  = "Pharmacokinetic Parameter Population",
   foot = paste("Box = median and IQR; whiskers = 1.5*IQR; points = individual participants.",
                "Exposure parameters on log y-axis. Treatments ordered by dose (TRT01AN).",
                "Descriptive; no between-group inferential test (parallel design)."))

## exposure box plots, faceted by parameter (free y so units differ cleanly)
p_expo <- ggplot(expo, aes(trt, AVAL, fill = trt)) +
  geom_boxplot(outlier.shape = NA, alpha = 0.5) +
  geom_jitter(width = 0.15, size = 1.2, alpha = 0.6) +
  scale_y_log10() +
  facet_wrap(~ PARAM, scales = "free_y") +
  labs(x = "Treatment (dose group)", y = "Parameter value (log scale)", fill = "Treatment",
       title = ttl$titles[3], caption = ttl$footnotes[1]) +
  theme_bw() + theme(legend.position = "none",
                     axis.text.x = element_text(angle = 30, hjust = 1))

## Tmax separately on a LINEAR axis (it is a time, summarized as Median (Min,Max))
tmax <- adam$adpp %>% filter(PKFL == "Y", PARAMCD == "TMAX") %>%
  mutate(trt = factor(.data[[dv$trtvar]],
                      levels = unique(.data[[dv$trtvar]][order(.data[[dv$trtnvar]])])))
p_tmax <- ggplot(tmax, aes(trt, AVAL, fill = trt)) +
  geom_boxplot(outlier.shape = NA, alpha = 0.5) +
  geom_jitter(width = 0.15, size = 1.2, alpha = 0.6) +
  labs(x = "Treatment (dose group)", y = "Tmax (h)", title = "Tmax") +
  theme_bw() + theme(legend.position = "none",
                     axis.text.x = element_text(angle = 30, hjust = 1))

# ggsave(file.path(env$out, "f_pk_param_boxplot.png"),      p_expo, width = 10, height = 6, dpi = 300)
# ggsave(file.path(env$out, "f_pk_param_boxplot_tmax.png"), p_tmax, width = 6,  height = 5, dpi = 300)
print(p_expo)
print(p_tmax)
