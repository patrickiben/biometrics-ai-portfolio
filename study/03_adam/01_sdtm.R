################################################################################
# 03_adam/01_sdtm.R: simulate SDTM-like source domains (DM, EX, PC, AE, VS, DS) for the
# synthetic study SIMBE01. SYNTHETIC DATA ONLY.
#
# Builds on sim_lifecycle/: the same priors (sim_lifecycle/priors.R: demographics, PK,
# adverse events), the same one-compartment oral model (.conc1 in simulate_adam.R), a
# 2x2 crossover with N = 40 and the master seed 2026. What this layer adds:
#   * sequences come from the randomization schedule in 01_design (not alternating);
#   * calendar dates and clock times, so ADaM can derive actual times (AFRLT, ARRLT);
#   * concentrations evaluated at the ACTUAL sampling time (nominal + a seeded deviation);
#   * SDTM-style variable names, BLQ results as text, and a few documented scenarios that
#     exercise the SAP rules (listed in SCENARIOS below).
# It is "SDTM-like": no trial design domains, no SUPP-- datasets, not checked by Pinnacle
# 21 or CDISC CORE.
#
# Inputs : sim_lifecycle/simulate_adam.R (+ priors.R), 01_design/randomization_schedule.csv
# Outputs: 03_adam/sdtm/{dm,ex,pc,ae,vs,ds}.csv
################################################################################
source("sim_lifecycle/simulate_adam.R")   # PRIORS, DEMOG, PK, AE and .conc1(); defines functions only

rand <- read.csv(sp("01_design", "randomization_schedule.csv"))
N <- STUDY$n_enrolled
stopifnot(nrow(rand) == N)

## documented scenarios (fixed participants so every page can name them)
SCENARIOS <- list(
  withdrawal   = list(subj = "017", what = "withdraws consent after Period 1 (no Period 2 dose)"),
  emesis       = list(subj = "029", period = 2L, onset_min = 45L, what = "vomits 45 minutes after the Period 2 dose"),
  carryover    = list(subj = "008", period = 2L, frac = 0.025, what = "measurable Period 2 pre-dose concentration at 2.5% of that period's Cmax (below the 5% rule)"),
  missed       = list(subj = "035", period = 1L, tpt = 12, what = "12 h sample in Period 1 not collected"),
  late_sample  = list(subj = "012", period = 1L, tpt = 4, dev_min = 25L, what = "4 h sample in Period 1 drawn 25 minutes late")
)

set.seed(STUDY$seed)
subj <- sprintf("%03d", seq_len(N))
usubjid <- paste(STUDY$studyid, STUDY$siteid, subj, sep = "-")
seqs <- rand$SEQUENCE                                      # enrollment order = RANDNO order

## --- DM ------------------------------------------------------------------------------
sex <- ifelse(runif(N) < DEMOG$female_frac, "F", "M")
age <- as.integer(pmin(pmax(round(rnorm(N, DEMOG$age["mean"], DEMOG$age["sd"])), DEMOG$age["min"]), DEMOG$age["max"]))
wt  <- round(ifelse(sex == "M", rnorm(N, DEMOG$wt$M["mean"], DEMOG$wt$M["sd"]), rnorm(N, DEMOG$wt$`F`["mean"], DEMOG$wt$`F`["sd"])), 1)
ht  <- round(ifelse(sex == "M", rnorm(N, DEMOG$ht$M["mean"], DEMOG$ht$M["sd"]), rnorm(N, DEMOG$ht$`F`["mean"], DEMOG$ht$`F`["sd"])), 1)
race_map <- c(White = "WHITE", Black = "BLACK OR AFRICAN AMERICAN", Asian = "ASIAN", Other = "MULTIPLE")
race <- unname(race_map[sample(names(DEMOG$race), N, TRUE, DEMOG$race)])
ethnic <- sample(c("HISPANIC OR LATINO", "NOT HISPANIC OR LATINO", "NOT REPORTED"), N, TRUE, c(.16, .80, .04))

t0 <- as.POSIXct("2026-03-02 08:00:00", tz = "UTC")              # Period 1 first dose
dose1 <- t0 + (seq_len(N) - 1) * 180                                 # 3-minute stagger
dose2 <- dose1 + STUDY$washout_d * 86400                             # Day 15, same clock time
consent <- as.Date(dose1) - sample(8:21, N, TRUE)
iso <- function(x) ifelse(is.na(x), NA_character_, format(x, "%Y-%m-%dT%H:%M", tz = "UTC"))
isod <- function(x) ifelse(is.na(x), NA_character_, format(x, "%Y-%m-%d"))
wd <- subj == SCENARIOS$withdrawal$subj
last_dose <- dose2; last_dose[wd] <- dose1[wd]
end_part <- as.Date(last_dose) + 2L; end_part[wd] <- as.Date(dose1[wd]) + 5L

dm <- data.frame(
  STUDYID = STUDY$studyid, DOMAIN = "DM", USUBJID = usubjid, SUBJID = subj,
  RFSTDTC = iso(dose1), RFENDTC = iso(last_dose), RFXSTDTC = iso(dose1), RFXENDTC = iso(last_dose),
  RFICDTC = isod(consent), RFPENDTC = isod(end_part), SITEID = STUDY$siteid,
  AGE = age, AGEU = "YEARS", SEX = sex, RACE = race, ETHNIC = ethnic,
  ARMCD = seqs, ARM = ifelse(seqs == "TR", "Test then Reference", "Reference then Test"),
  ACTARMCD = seqs, ACTARM = ifelse(seqs == "TR", "Test then Reference", "Reference then Test"),
  COUNTRY = "USA", DMDTC = isod(consent))

## --- EX ------------------------------------------------------------------------------
trt_in <- function(s, p) ifelse(substr(s, p, p) == "T", "Test", "Reference")
ex <- do.call(rbind, lapply(1:2, function(p) {
  keep <- if (p == 2) !wd else rep(TRUE, N)
  d <- if (p == 1) dose1 else dose2
  data.frame(STUDYID = STUDY$studyid, DOMAIN = "EX", USUBJID = usubjid[keep],
             EXTRT = paste("SIMDRUG", toupper(trt_in(seqs[keep], p))), EXDOSE = STUDY$dose_mg, EXDOSU = "mg",
             EXDOSFRM = "TABLET", EXDOSFRQ = "ONCE", EXROUTE = "ORAL",
             EXLOT = ifelse(trt_in(seqs[keep], p) == "Test", "T-0426", "R-1185"),
             EXSTDTC = iso(d[keep]), EXENDTC = iso(d[keep]),
             VISITNUM = p, VISIT = paste("PERIOD", p, "DAY", c(1, 15)[p]), VISITDY = c(1L, 15L)[p],
             EPOCH = paste("TREATMENT PERIOD", p))
}))
ex <- ex[order(ex$USUBJID, ex$VISITNUM), ]
ex$EXSEQ <- ave(seq_len(nrow(ex)), ex$USUBJID, FUN = seq_along)

## --- PC: concentrations at actual sampling times ----------------------------------------
lg <- function(gm, cv, n) gm * exp(rnorm(n, 0, sqrt(log(1 + cv^2))))
CLi <- lg(PK$CL["gm"], PK$CL["cv"], N); Vi <- lg(PK$V["gm"], PK$V["cv"], N); Kai <- lg(PK$Ka["gm"], PK$Ka["cv"], N)
tpts <- PK$times                                             # 0, 0.25, ..., 48 h (same as sim_lifecycle)
tpt_label <- function(h) ifelse(h == 0, "Pre-dose", ifelse(h < 1, paste0(h * 60, " Min Post-dose"), paste0(h, "h Post-dose")))
elt <- function(h) ifelse(h == 0, "PT0H", ifelse(h < 1, paste0("PT", h * 60, "M"), paste0("PT", h, "H")))
dev_min <- function(h) ifelse(h == 0, -round(runif(length(h), 10, 40)),
                       ifelse(h <= 2, round(runif(length(h), -1, 3)),
                       ifelse(h <= 16, round(runif(length(h), -5, 10)), round(runif(length(h), -15, 30)))))
pc_rows <- list(); k <- 0L
for (i in seq_len(N)) for (p in 1:2) {
  if (p == 2 && wd[i]) next
  trt <- trt_in(seqs[i], p)
  dose_t <- if (p == 1) dose1[i] else dose2[i]
  wsv  <- exp(rnorm(1, 0, sqrt(log(1 + PK$be_intra_cv^2))))        # occasion-to-occasion
  teff <- if (trt == "Test") PK$be_gmr_true * exp(rnorm(1, 0, 0.05)) else 1
  CLij <- CLi[i] / (teff * wsv)                                     # AUC proportional to 1/CL
  dv <- dev_min(tpts)
  sc <- SCENARIOS$late_sample
  if (subj[i] == sc$subj && p == sc$period) dv[tpts == sc$tpt] <- sc$dev_min
  t_act_h <- tpts + dv / 60                                         # pre-dose sample is before the dose
  conc <- .conc1(pmax(t_act_h, 0), STUDY$dose_mg, CLij, Vi[i], Kai[i]) * PK$conc_scale
  conc <- conc * exp(rnorm(length(conc), 0, PK$prop_err))
  if (subj[i] == SCENARIOS$emesis$subj && p == SCENARIOS$emesis$period) conc <- conc * 0.55  # part of the dose lost
  if (subj[i] == SCENARIOS$carryover$subj && p == SCENARIOS$carryover$period)
    conc[tpts == 0] <- SCENARIOS$carryover$frac * max(conc)
  conc <- signif(conc, 3)
  missed <- subj[i] == SCENARIOS$missed$subj & p == SCENARIOS$missed$period & tpts == SCENARIOS$missed$tpt
  blq <- !missed & conc < STUDY$lloq
  k <- k + 1L
  pc_rows[[k]] <- data.frame(
    STUDYID = STUDY$studyid, DOMAIN = "PC", USUBJID = usubjid[i],
    PCTESTCD = "SIMDRUG", PCTEST = "SIMDRUG", PCCAT = "ANALYTE", PCSPEC = "PLASMA",
    PCORRES = ifelse(missed, NA, ifelse(blq, "<0.50", formatC(conc, format = "fg", digits = 3))),
    PCORRESU = "ng/mL",
    PCSTRESC = ifelse(missed, NA, ifelse(blq, "<BLQ", formatC(conc, format = "fg", digits = 3))),
    PCSTRESN = ifelse(missed | blq, NA_real_, conc), PCSTRESU = "ng/mL",
    PCSTAT = ifelse(missed, "NOT DONE", NA), PCREASND = ifelse(missed, "SAMPLE NOT COLLECTED", NA),
    PCLLOQ = STUDY$lloq,
    VISITNUM = p, VISIT = paste("PERIOD", p, "DAY", c(1, 15)[p]), VISITDY = c(1L, 15L)[p],
    EPOCH = paste("TREATMENT PERIOD", p),
    PCDTC = ifelse(missed, NA, iso(dose_t + round(t_act_h * 3600))),
    PCTPT = tpt_label(tpts), PCTPTNUM = tpts, PCELTM = elt(tpts),
    PCTPTREF = paste("PERIOD", p, "DOSE"), PCRFTDTC = iso(dose_t))
}
pc <- do.call(rbind, pc_rows)
pc$PCTPTREF <- as.character(pc$PCTPTREF)
pc$PCSEQ <- ave(seq_len(nrow(pc)), pc$USUBJID, FUN = seq_along)

## --- AE: per exposure, from the sim_lifecycle adverse-event priors -----------------------
p_exp <- 1 - (1 - AE$p_any)^(1 / 2)
ae_rows <- list(); k <- 0L
for (i in seq_len(N)) for (p in 1:2) {
  if (p == 2 && wd[i]) next
  dose_t <- if (p == 1) dose1[i] else dose2[i]
  sc <- SCENARIOS$emesis
  if (subj[i] == sc$subj && p == sc$period) {
    k <- k + 1L
    ae_rows[[k]] <- data.frame(USUBJID = usubjid[i], AETERM = "VOMITING", AEDECOD = "Vomiting",
      AEBODSYS = "Gastrointestinal disorders", AESOC = "Gastrointestinal disorders", AESEV = "MILD", AESER = "N",
      AEREL = "RELATED", AEACN = "NOT APPLICABLE", AEOUT = "RECOVERED/RESOLVED",
      AESTDTC = iso(dose_t + sc$onset_min * 60), AEENDTC = iso(dose_t + (sc$onset_min + 20) * 60))
  }
  if (runif(1) >= p_exp) next
  npt <- 1L + rpois(1, 0.6)
  pts <- sample(names(AE$pts), min(npt, length(AE$pts)), FALSE, prob = AE$pts)
  ser <- runif(1) < (AE$p_serious / AE$p_any)
  for (j in seq_along(pts)) {
    on <- dose_t + round(runif(1, 0.5, 72) * 3600)
    k <- k + 1L
    ae_rows[[k]] <- data.frame(USUBJID = usubjid[i], AETERM = toupper(pts[j]), AEDECOD = pts[j],
      AEBODSYS = AE$soc[[pts[j]]], AESOC = AE$soc[[pts[j]]],
      AESEV = sample(c("MILD", "MODERATE", "SEVERE"), 1, prob = AE$sev),
      AESER = ifelse(ser && j == 1, "Y", "N"),
      AEREL = ifelse(runif(1) < AE$p_related, "RELATED", "NOT RELATED"),
      AEACN = "NOT APPLICABLE", AEOUT = "RECOVERED/RESOLVED",
      AESTDTC = iso(on), AEENDTC = iso(on + round(runif(1, 1, 48) * 3600)))
  }
}
ae <- do.call(rbind, ae_rows)
ae <- ae[order(ae$USUBJID, ae$AESTDTC), ]
ae <- data.frame(STUDYID = STUDY$studyid, DOMAIN = "AE", ae)
ae$AESEQ <- ave(seq_len(nrow(ae)), ae$USUBJID, FUN = seq_along)

## --- VS: screening height and weight (the inputs ADSL needs) -----------------------------
vs <- rbind(
  data.frame(STUDYID = STUDY$studyid, DOMAIN = "VS", USUBJID = usubjid, VSTESTCD = "HEIGHT", VSTEST = "Height",
             VSORRES = as.character(ht), VSORRESU = "cm", VSSTRESN = ht, VSSTRESU = "cm",
             VISITNUM = 0, VISIT = "SCREENING", VSDTC = isod(consent), VSBLFL = "Y"),
  data.frame(STUDYID = STUDY$studyid, DOMAIN = "VS", USUBJID = usubjid, VSTESTCD = "WEIGHT", VSTEST = "Weight",
             VSORRES = as.character(wt), VSORRESU = "kg", VSSTRESN = wt, VSSTRESU = "kg",
             VISITNUM = 0, VISIT = "SCREENING", VSDTC = isod(consent), VSBLFL = "Y"))
vs <- vs[order(vs$USUBJID, vs$VSTESTCD), ]
vs$VSSEQ <- ave(seq_len(nrow(vs)), vs$USUBJID, FUN = seq_along)

## --- DS: consent, randomization and disposition --------------------------------------------
ds <- rbind(
  data.frame(USUBJID = usubjid, DSTERM = "INFORMED CONSENT OBTAINED", DSDECOD = "INFORMED CONSENT OBTAINED",
             DSCAT = "PROTOCOL MILESTONE", DSSTDTC = isod(consent)),
  data.frame(USUBJID = usubjid, DSTERM = "RANDOMIZED", DSDECOD = "RANDOMIZED",
             DSCAT = "PROTOCOL MILESTONE", DSSTDTC = isod(as.Date(dose1))),
  data.frame(USUBJID = usubjid,
             DSTERM = ifelse(wd, "PARTICIPANT WITHDREW CONSENT", "COMPLETED"),
             DSDECOD = ifelse(wd, "WITHDRAWAL BY SUBJECT", "COMPLETED"),   # CDISC CT submission values
             DSCAT = "DISPOSITION EVENT", DSSTDTC = isod(end_part)))
ds <- data.frame(STUDYID = STUDY$studyid, DOMAIN = "DS", ds[order(ds$USUBJID, ds$DSSTDTC, ds$DSCAT), ])
ds$DSSEQ <- ave(seq_len(nrow(ds)), ds$USUBJID, FUN = seq_along)

SDTM <- list(dm = dm, ex = ex, pc = pc, ae = ae, vs = vs, ds = ds)
for (nm in names(SDTM)) write_csv_det(SDTM[[nm]], sp("03_adam", "sdtm", paste0(nm, ".csv")))
write_json_det(lapply(SCENARIOS, function(s) c(s, usubjid = paste(STUDY$studyid, STUDY$siteid, s$subj, sep = "-"))),
               sp("03_adam", "sdtm", "scenarios.json"))
cat(sprintf("[03_adam/sdtm] DM %d, EX %d, PC %d (BLQ %d, not done %d), AE %d, VS %d, DS %d records\n",
            nrow(dm), nrow(ex), nrow(pc), sum(pc$PCSTRESC == "<BLQ", na.rm = TRUE), sum(!is.na(pc$PCSTAT)),
            nrow(ae), nrow(vs), nrow(ds)))
