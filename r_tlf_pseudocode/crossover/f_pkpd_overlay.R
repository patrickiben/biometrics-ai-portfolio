################################################################################
# FIGURE    : f_pkpd_overlay  (Crossover - 2x2 or Williams)
# TITLE     : Mean Plasma Concentration and Pharmacodynamic Biomarker Over Time
#             by Treatment (Dual-Axis Overlay)
# POPULATION: PK Population (PKFL=="Y") + Pharmacodynamic Population (PDFL=="Y")
# INPUT     : ADPC (PARAMCD = parent analyte, AVAL = concentration) +
#             ADPD (PARAMCD = PD biomarker, AVAL) ; both with APERIOD/TRTA/ATPT
# NOTE      : PSEUDOCODE. Temporal PK/PD relationship: mean plasma concentration
#             on the LEFT (primary) axis (SEMILOG / log10, solid) overlaid with
#             mean PD response on the RIGHT (secondary) axis (linear, dashed)
#             -- matches the SAS house convention -- FACETED by treatment (TRTA)
#             since each crossover period delivers a different treatment. Each
#             source keeps its own population flag and period-specific time grid;
#             joined only on nominal time for display. Dual axis is for visual
#             relationship only -> not for inference.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("CROSSOVER")                 # TRTA + APERIOD + TRTSEQP

PC_CD <- "CONC"                                 # PK analyte on ADPC (match SAS)
PD_CD <- "PDMARK1"                              # PD biomarker on ADPD (match SAS)

## --- mean PK concentration by treatment x nominal time (ADPC, PKFL) ---------
## concentration shown on a SEMILOG axis -> restrict to AVAL>0 for the log scale
pk <- adam$adpc %>%
  filter(PKFL == "Y", PARAMCD == PC_CD, AVAL > 0) %>%
  group_by(trt = .data[[dv$trtvar]], ATPTN, ATPT) %>%
  summarise(conc = mean(AVAL, na.rm = TRUE), .groups = "drop")

## --- mean PD biomarker by treatment x nominal time (ADPD, PDFL) -------------
pd <- adam$adpd %>%
  filter(PDFL == "Y", PARAMCD == PD_CD) %>%
  group_by(trt = .data[[dv$trtvar]], ATPTN, ATPT) %>%
  summarise(pdv = mean(AVAL, na.rm = TRUE), .groups = "drop")

## --- align on treatment + nominal time -------------------------------------
ov <- full_join(pk, pd, by = c("trt", "ATPTN", "ATPT")) %>% arrange(trt, ATPTN)

## PRIMARY axis = concentration (semilog / log10). SECONDARY axis = PD (linear).
## The primary axis is a true log10 scale (scale_y_log10) carrying the
## concentration series. The PD series is mapped linearly into the log10(conc)
## display range so it overlays correctly, and a back-transforming sec_axis
## labels the RIGHT axis in original PD units on a linear scale.
lc       <- log10(ov$conc)                                  # log10 concentration
lc_rng   <- range(lc, na.rm = TRUE)
pd_rng   <- range(ov$pdv, na.rm = TRUE)
## linear map  PD value -> log10(conc) display units (and its inverse for sec_axis)
to_conc  <- function(y) lc_rng[1] + (y - pd_rng[1]) * diff(lc_rng) / diff(pd_rng)
from_conc<- function(z) pd_rng[1] + (z - lc_rng[1]) * diff(pd_rng) / diff(lc_rng)
ov$pd_on_conc <- 10 ^ to_conc(ov$pdv)                       # PD series in conc units

ttl <- tfl_titles(num = "14.4.5.1", type = "Figure",
   text = "Mean Plasma Concentration and Pharmacodynamic Biomarker Over Time by Treatment",
   pop  = "PK Population (concentration) and Pharmacodynamic Population (biomarker)",
   foot = paste("Left axis (semilog/log10) = mean concentration (solid); right axis (linear) = mean PD response (dashed).",
                "Faceted by treatment (TRTA); each crossover period delivers one treatment.",
                "Dual axis is descriptive overlay only and is not used for inference."))

p <- ggplot(ov, aes(ATPTN)) +
  geom_line(aes(y = conc, colour = "Concentration")) +
  geom_point(aes(y = conc, colour = "Concentration"), size = 1.6) +
  geom_line(aes(y = pd_on_conc, colour = "PD Response"), linetype = "dashed") +
  geom_point(aes(y = pd_on_conc, colour = "PD Response"), size = 1.6, shape = 17) +
  facet_wrap(~ trt) +
  scale_y_log10(
    name = "Mean Concentration (units), log scale",
    sec.axis = sec_axis(~ from_conc(log10(.)), name = "Mean PD Response (units)")) +
  scale_colour_manual(values = c("Concentration" = "#b5651d", "PD Response" = "#1b6ca8")) +
  labs(x = "Nominal Time Post-Dose", colour = NULL,
       title = ttl$titles[3], caption = ttl$footnotes[1]) +
  theme_bw() + theme(legend.position = "bottom")
# ggsave(file.path(env$out, "f_pkpd_overlay.png"), p, width = 10, height = 6, dpi = 300)
print(p)
