################################################################################
# priors.R — calibration priors for the synthetic study-lifecycle simulator.
#
# DESIGN-STRUCTURE priors are CALIBRATED to a PUBLIC early-phase Phase-1 corpus
# (205 public studies on ClinicalTrials.gov; that calibration corpus is not included
#  in this public repo — the priors it produced are baked in below).
# PARTICIPANT-LEVEL distributions are DOMAIN priors (healthy-volunteer norms /
# typical oral small-molecule PK / AE incidence) — NOT from any specific sponsor
# participant-level data (none is public). Everything downstream is SYNTHETIC.
################################################################################

## --- CALIBRATED to the public corpus ---------------------------------------
PRIORS <- list(
 ## CT.gov interventionModel mix -> maps to our design templates
 design_model = c(CROSSOVER = 0.42, PARALLEL = 0.28, SINGLE_GROUP = 0.16, SEQUENTIAL = 0.14),
 ## enrollment N ~ log-normal fit to corpus (median 38, IQR 24-58)
 N_meanlog = log(38), N_sdlog = (log(58) - log(24)) / (2 * qnorm(0.75)),
 N_clamp = c(6L, 300L),
 healthy_frac = 0.85,
 randomized_frac = 0.78,
 sex_pref = c(ALL = 0.83, MALE = 0.13, FEMALE = 0.04),
 ## study archetype mix (title-keyword shares, renormalised)
 archetype = c(BE = 0.32, DOSE_ESC = 0.20, FOOD_EFFECT = 0.09, DDI = 0.08,
 FIH = 0.07, MAD = 0.08, SAD = 0.06, IMPAIRMENT = 0.05, ADME = 0.03, TQT = 0.02)
)

## --- DOMAIN priors (healthy volunteers; public norms) ----------------------
## age + sex FITTED to the 42 results-posted studies' baseline modules
## (age_mean 43.6 / sd 8.2; female 38.8%). Reflects the full corpus mix incl.
## some patient studies, so older than a pure healthy-volunteer panel. Weight/
## height stay domain priors (baseline weight/height public in only ~4 studies).
DEMOG <- list(
 age = c(min = 18, max = 65, mean = 43.6, sd = 8.2), # FITTED (42 studies)
 wt = list(M = c(mean = 80, sd = 11), `F` = c(mean = 66, sd = 10)), # kg (domain)
 ht = list(M = c(mean = 176, sd = 7), `F` = c(mean = 163, sd = 6)), # cm (domain)
 race = c(White = 0.62, Black = 0.16, Asian = 0.13, Other = 0.09), # domain
 female_frac = 0.388) # FITTED (1076 F / 1696 M)

## PK: typical oral small molecule, 1-compartment + first-order absorption.
## Between-participant variability log-normal on CL/V/Ka; proportional residual.
## CL/V/Ka structural values CALIBRATED so the simulated exposure matches the
## FITTED variability/shape from the 42 studies: Cmax CV ~36%, AUC CV ~33%,
## Tmax median ~1.0 h, t1/2 median ~7.8 h. (Ke=CL/V=0.089 -> t1/2 7.8 h;
## Ka=4 -> Tmax ~1.0 h.) Absolute geomeans are drug-specific and NOT transferred.
PK <- list(
 CL = c(gm = 10, cv = 0.33), # L/h (apparent CL/F) between-subj -> AUC CV ~33% w/ within
 V = c(gm = 112, cv = 0.40), # L (apparent V/F) -> Cmax CV ~36% (FITTED); t1/2 ~7.8 h
 Ka = c(gm = 4.0, cv = 0.40), # 1/h -> Tmax ~1.0 h (FITTED)
 conc_scale = 120, # lifts Cmax well above LLOQ (Cmax/LLOQ ~200; absolute scale arbitrary)
 lloq = 0.50, # ng/mL (BLQ below)
 prop_err = 0.08, # proportional residual CV (domain)
 times = c(0, .25, .5, 1, 1.5, 2, 3, 4, 6, 8, 12, 16, 24, 36, 48),
 ## bioequivalence truth: test/reference geometric ratio + within-participant CV
 be_gmr_true = 1.00, be_intra_cv = 0.15)

## AE incidence FITTED to the 42 results-posted studies: overall any-AE 0.43,
## serious 0.013; preferred-term weights = pooled incidences (terms reported
## above each study's frequency threshold, so these are COMMON-AE rates).
AE <- list(
 p_any = 0.43, # FITTED: P(>=1 TEAE) per participant on active
 placebo_factor = 0.5, # domain
 p_serious = 0.013, # FITTED: P(serious AE) per participant
 pts = c(Somnolence = 0.194, Pruritus = 0.165, Fatigue = 0.087, Dizziness = 0.082,
 Nausea = 0.080, Headache = 0.078, Diarrhoea = 0.076, `Feeling hot` = 0.051,
 `Decreased appetite` = 0.049, Vomiting = 0.046, `Dry mouth` = 0.043,
 `Abdominal pain` = 0.038), # FITTED pooled incidences (relative weights)
 soc = c(Somnolence = "Nervous system disorders", Dizziness = "Nervous system disorders",
 Headache = "Nervous system disorders", Nausea = "Gastrointestinal disorders",
 Diarrhoea = "Gastrointestinal disorders", Vomiting = "Gastrointestinal disorders",
 `Dry mouth` = "Gastrointestinal disorders", `Abdominal pain` = "Gastrointestinal disorders",
 Fatigue = "General disorders and administration site conditions",
 `Feeling hot` = "General disorders and administration site conditions",
 Pruritus = "Skin and subcutaneous tissue disorders",
 `Decreased appetite` = "Metabolism and nutrition disorders"),
 sev = c(MILD = 0.70, MODERATE = 0.25, SEVERE = 0.05), # domain
 p_related = 0.50) # domain

## --- samplers ---------------------------------------------------------------
sample_N <- function() {
 n <- round(rlnorm(1, PRIORS$N_meanlog, PRIORS$N_sdlog))
 as.integer(min(max(n, PRIORS$N_clamp[1]), PRIORS$N_clamp[2]))
}
pick <- function(p) sample(names(p), 1, prob = as.numeric(p))
