################################################################################
# simulate_adam.R — synthetic ADaM generator for an early-phase clin-pharm study.
# Design structure sampled from the CALIBRATED public-corpus priors (priors.R);
# participant-level data simulated from DOMAIN priors. Output = an `adam` list of
# ADaM-shaped data frames consumable by the r_tlf_pseudocode programs.
# 100% SYNTHETIC. Not real clinical data (100% synthetic).
################################################################################
source("sim_lifecycle/priors.R")

## --- sample a study design from the calibrated priors -----------------------
sample_design <- function(archetype = NULL, N = NULL) {
 arch <- archetype %||% pick(PRIORS$archetype)
 model <- switch(arch,
 BE = "CROSSOVER", FOOD_EFFECT = "CROSSOVER", DDI = "SINGLE_GROUP",
 SAD = "SEQUENTIAL", MAD = "SEQUENTIAL", DOSE_ESC = "SEQUENTIAL", FIH = "SEQUENTIAL",
 "PARALLEL")
 n <- N %||% sample_N()
 list(archetype = arch, model = model, N = n,
 healthy = runif(1) < PRIORS$healthy_frac,
 dose_mg = switch(arch, SAD = , MAD = , DOSE_ESC = , FIH = c(10,30,100,300),
 c(100)), # ascending cohorts vs single dose
 site = sample(c("Quebec","Miami","Melbourne"), 1, prob = c(.46,.34,.20)))
}
`%||%` <- function(a,b) if (is.null(a)) b else a

## --- ADSL: demographics + treatment assignment -----------------------------
sim_adsl <- function(d) {
 n <- d$N
 sex <- ifelse(runif(n) < DEMOG$female_frac, "F", "M")
 age <- pmin(pmax(round(rnorm(n, DEMOG$age["mean"], DEMOG$age["sd"])), DEMOG$age["min"]), DEMOG$age["max"])
 wt <- round(ifelse(sex=="M", rnorm(n,DEMOG$wt$M["mean"],DEMOG$wt$M["sd"]),
 rnorm(n,DEMOG$wt$`F`["mean"],DEMOG$wt$`F`["sd"])), 1)
 ht <- round(ifelse(sex=="M", rnorm(n,DEMOG$ht$M["mean"],DEMOG$ht$M["sd"]),
 rnorm(n,DEMOG$ht$`F`["mean"],DEMOG$ht$`F`["sd"])), 1)
 race <- sample(names(DEMOG$race), n, TRUE, DEMOG$race)
 ethnic <- sample(c("HISPANIC OR LATINO","NOT HISPANIC OR LATINO","NOT REPORTED"),
 n, TRUE, c(.16,.80,.04)) # CDISC CT values
 agegr1 <- as.character(cut(age, breaks = c(-Inf,40,65,Inf),
 labels = c("<40","40-64",">=65"), right = FALSE))
 site <- unname(c(Quebec="101", Miami="102", Melbourne="103")[d$site])
 adsl <- data.frame(
 USUBJID = sprintf("CP-SIM-%s-%03d", site, seq_len(n)),
 SUBJID = sprintf("%03d", seq_len(n)), SITEID = site,
 AGE = as.integer(age), AGEGR1 = agegr1, SEX = sex, RACE = race, ETHNIC = ethnic,
 HEIGHTBL = ht, WEIGHTBL = wt, BMIBL = round(wt/(ht/100)^2, 1),
 SAFFL = "Y", PKFL = "Y", RANDFL = "Y", ENRLFL = "Y", stringsAsFactors = FALSE)
 if (d$model == "CROSSOVER") { # 2x2: sequences TR / RT
 seqn <- rep(1:2, length.out = n)
 adsl$TRTSEQP <- c("TR","RT")[seqn]; adsl$TRTSEQPN <- seqn
 p1 <- substr(adsl$TRTSEQP, 1, 1) # period-1 element of the sequence
 adsl$TRT01A <- ifelse(p1 == "T", "Test", "Reference") # actual treatment, period 1 (TR->Test, RT->Reference)
 adsl$TRT01AN <- ifelse(p1 == "T", 1L, 2L) # numeric code matches ADEX TRTAN (Test=1, Reference=2)
 } else if (d$model == "SEQUENTIAL") { # ascending-dose cohorts (+ placebo)
 dose <- rep(d$dose_mg, length.out = n)
 plac <- runif(n) < 0.25
 adsl$TRT01A <- ifelse(plac, "Placebo", paste0(dose," mg"))
 adsl$TRT01AN <- ifelse(plac, 0L, dose)
 } else { # PARALLEL / SINGLE_GROUP
 dose <- if (length(d$dose_mg) > 1) sample(d$dose_mg, n, TRUE) else d$dose_mg
 adsl$TRT01A <- paste0(dose," mg"); adsl$TRT01AN <- dose
 }
 adsl
}

## --- ADEX: exposure (ADaM analysis vars) -----------------------------------
sim_adex <- function(adsl, d) {
 if (d$model == "CROSSOVER") {
 ex <- do.call(rbind, lapply(1:2, function(p) {
 trt <- mapply(function(s) substr(s, p, p), adsl$TRTSEQP) # T or R in period p
 data.frame(USUBJID=adsl$USUBJID, APERIOD=p, APERIODC=paste("Period",p),
 TRTA=ifelse(trt=="T","Test","Reference"), TRTAN=ifelse(trt=="T",1L,2L),
 AVAL=100, TRTDURD=1L, NDOSES=1L, SAFFL="Y", stringsAsFactors=FALSE) }))
 } else {
 rep_n <- if (d$model=="SEQUENTIAL") 7L else 1L # MAD-ish multi-day else single
 ex <- data.frame(USUBJID=adsl$USUBJID, APERIOD=1L, APERIODC="Period 1",
 TRTA=adsl$TRT01A, TRTAN=adsl$TRT01AN,
 AVAL=adsl$TRT01AN, TRTDURD=rep_n, NDOSES=rep_n, SAFFL="Y",
 stringsAsFactors=FALSE)
 }
 ex
}

## --- one-compartment oral concentration profile ----------------------------
.conc1 <- function(t, dose, CL, V, Ka) {
 Ke <- CL / V
 ifelse(t <= 0, 0, (dose * Ka) / (V * (Ka - Ke)) * (exp(-Ke*t) - exp(-Ka*t)))
}

## --- ADPC: concentration-time, with BSV + WSV + residual + BLQ --------------
sim_adpc <- function(adsl, adex, d) {
 lg <- function(gm, cv) gm * exp(rnorm(length(gm), 0, sqrt(log(1+cv^2))))
 ## participant-level PK (between-participant)
 n <- nrow(adsl)
 CLi <- lg(rep(PK$CL["gm"],n), PK$CL["cv"]); Vi <- lg(rep(PK$V["gm"],n), PK$V["cv"])
 Kai <- lg(rep(PK$Ka["gm"],n), PK$Ka["cv"]); names(CLi) <- adsl$USUBJID
 Vi <- setNames(Vi, adsl$USUBJID); Kai <- setNames(Kai, adsl$USUBJID)
 atpt <- ifelse(PK$times==0, "Pre-dose", paste0(PK$times,"h")) # character nominal time label
 rows <- list(); k <- 0
 for (i in seq_len(nrow(adex))) {
 u <- adex$USUBJID[i]; per <- adex$APERIOD[i]; trt <- adex$TRTA[i]
 dose <- ifelse(adex$AVAL[i] > 0, adex$AVAL[i], 100)
 if (grepl("Placebo", trt)) next
 wsv <- exp(rnorm(1, 0, sqrt(log(1+PK$be_intra_cv^2)))) # within-participant (occasion)
 teff <- if (identical(trt,"Test")) PK$be_gmr_true * exp(rnorm(1,0,0.05)) else 1
 CLij <- CLi[u] / (teff * wsv) # AUC ∝ 1/CL
 cc <- .conc1(PK$times, dose, CLij, Vi[u], Kai[u]) * PK$conc_scale # scale above LLOQ
 cc <- cc * exp(rnorm(length(cc), 0, PK$prop_err)) # proportional residual
 blq <- cc < PK$lloq & PK$times > 0
 k <- k+1
 rows[[k]] <- data.frame(USUBJID=u, APERIOD=per, APERIODC=paste("Period",per),
 TRTA=trt, PARAMCD="CONC", PARAM="Plasma concentration (ng/mL)",
 ATPT=atpt, ATPTN=PK$times, AVAL=ifelse(blq, NA_real_, round(cc,3)),
 AVALC=ifelse(blq, "<LLOQ", as.character(round(cc,3))),
 ABLFL=ifelse(PK$times==0,"Y","N"), ANL01FL="Y", PKFL="Y", stringsAsFactors=FALSE)
 }
 do.call(rbind, rows)
}

## --- NCA: derive ADPP parameters from ADPC ---------------------------------
nca_one <- function(t, c) {
 ok <- !is.na(c) & c > 0
 if (sum(ok) < 3) return(NULL)
 cmax <- max(c[ok]); tmax <- t[ok][which.max(c[ok])]
 auclast <- sum(diff(t[ok]) * (head(c[ok],-1)+tail(c[ok],-1))/2) # linear trapezoid
 term <- tail(which(ok), 3) # terminal points
 fit <- lm(log(c[term]) ~ t[term]); lz <- unname(-coef(fit)[2]) # strip lm coef name
 if (is.na(lz) || lz <= 0) # no valid terminal slope
 return(c(CMAX=cmax, TMAX=tmax, AUCLST=auclast, AUCIFO=NA_real_, T12=NA_real_))
 t12 <- log(2)/lz; clast <- c[ok][length(c[ok])]
 aucinf <- unname(auclast + clast/lz)
 c(CMAX=cmax, TMAX=tmax, AUCLST=auclast, AUCIFO=aucinf, T12=as.numeric(t12))
}
sim_adpp <- function(adpc, adex) {
 plab <- c(CMAX="Cmax (ng/mL)", TMAX="Tmax (h)", AUCLST="AUClast (h*ng/mL)",
 AUCIFO="AUCinf (h*ng/mL)", T12="t1/2 (h)", CLFO="CL/F (L/h)", VZFO="Vz/F (L)")
 key <- unique(adpc[,c("USUBJID","APERIOD","TRTA")])
 out <- list(); k <- 0
 for (i in seq_len(nrow(key))) {
 s <- adpc[adpc$USUBJID==key$USUBJID[i] & adpc$APERIOD==key$APERIOD[i], ]
 s <- s[order(s$ATPTN), ]
 p <- nca_one(s$ATPTN, s$AVAL); if (is.null(p)) next
 dmatch <- adex$AVAL[adex$USUBJID==key$USUBJID[i] & adex$APERIOD==key$APERIOD[i]]
 dose <- if (length(dmatch) && !is.na(dmatch[1]) && dmatch[1] > 0) dmatch[1] else 100
 clf <- if (is.na(p["AUCIFO"])) NA_real_ else unname(dose / p["AUCIFO"]) # apparent CL/F
 vzf <- if (is.na(clf) || is.na(p["T12"])) NA_real_ else unname(clf / (log(2)/p["T12"]))
 vals <- c(CMAX=unname(p["CMAX"]), TMAX=unname(p["TMAX"]), AUCLST=unname(p["AUCLST"]),
 AUCIFO=unname(p["AUCIFO"]), T12=unname(p["T12"]), CLFO=clf, VZFO=vzf)
 k <- k+1
 out[[k]] <- data.frame(USUBJID=key$USUBJID[i], APERIOD=key$APERIOD[i], TRTA=key$TRTA[i],
 PARAMCD=names(vals), PARAM=unname(plab[names(vals)]), AVAL=as.numeric(vals),
 PKFL="Y", stringsAsFactors=FALSE)
 }
 do.call(rbind, out)
}

## --- ADAE: AE incidence per EXPOSURE (period/treatment of onset) ----------------
sim_adae <- function(adsl, adex, d) {
 nper <- if (d$model == "CROSSOVER") 2L else 1L # exposures per participant
 p_exp <- 1 - (1 - AE$p_any)^(1/nper) # keep participant-level ~ p_any
 rows <- list(); k <- 0
 for (i in seq_len(nrow(adex))) {
 u <- adex$USUBJID[i]; trta <- adex$TRTA[i]; trtan <- adex$TRTAN[i]
 per <- adex$APERIOD[i]; perc <- adex$APERIODC[i]
 on_active <- !grepl("Placebo", trta)
 p <- p_exp * (if (on_active) 1 else AE$placebo_factor) # placebo_factor live only for arms with placebo
 if (runif(1) >= p) next
 npt <- 1L + rpois(1, 0.6)
 pts <- sample(names(AE$pts), min(npt, length(AE$pts)), FALSE, prob = AE$pts)
 ser_subj <- runif(1) < (AE$p_serious / AE$p_any) # P(serious | has AE)
 day0 <- (per - 1L) * 14L # period-2 onset after washout
 trt01a <- adsl$TRT01A[match(u, adsl$USUBJID)]
 for (j in seq_along(pts)) { pt <- pts[j]
 sae <- ser_subj && j==1
 k <- k+1
 rows[[k]] <- data.frame(USUBJID=u, TRT01A=trt01a,
 APERIOD=per, APERIODC=perc, TRTA=trta, TRTAN=trtan,
 AESOC=AE$soc[[pt]], AEDECOD=pt,
 AESEVN=sample(1:3,1,prob=AE$sev), AREL=ifelse(runif(1)<AE$p_related,"RELATED","NOT RELATED"),
 AESER=ifelse(sae,"Y","N"),
 AEACN=ifelse(sae && runif(1)<0.30,"DRUG WITHDRAWN","NONE"),
 AESDTH="N", TRTEMFL="Y", SAFFL="Y",
 ASTDY=day0 + sample(1:3,1), stringsAsFactors=FALSE)
 }
 }
 if (!k) return(data.frame())
 do.call(rbind, rows)
}

## --- generic BDS builder: baseline + on-treatment per EXPOSURE x parameter ----
## emits per-period records (crossover -> 2 periods) so by-treatment safety tables
## have correct per-treatment denominators; each record carries APERIOD + TRTA.
.bds <- function(adsl, adex, params, chg_frac = 0.5) {
 uln_codes <- c("ALT","AST","BILI","CREAT") # 'x ULN' is only meaningful for these
 rows <- list(); k <- 0
 for (i in seq_len(nrow(adex))) {
 u <- adex$USUBJID[i]; per <- adex$APERIOD[i]; perc <- adex$APERIODC[i]
 trta <- adex$TRTA[i]; trtan <- adex$TRTAN[i]; ai <- match(u, adsl$USUBJID)
 for (pi in seq_len(nrow(params))) {
 pr <- params[pi, ]
 base <- rnorm(1, pr$mean, pr$sd); post <- base + rnorm(1, 0, pr$sd * chg_frac)
 ind <- function(x) if (x < pr$lo) "LOW" else if (x > pr$hi) "HIGH" else "NORMAL"
 for (v in 0:1) { val <- if (v==0) base else post; k <- k+1
 rows[[k]] <- data.frame(USUBJID=u, TRT01A=adsl$TRT01A[ai],
 APERIOD=per, APERIODC=perc, TRTA=trta, TRTAN=trtan,
 PARAMCD=pr$code, PARAM=pr$param, AVISIT=ifelse(v==0,"Baseline","On-treatment"),
 AVISITN=v, ATPTN=v, AVAL=round(val, pr$dp), BASE=round(base, pr$dp),
 CHG=ifelse(v==0, 0, round(post-base, pr$dp)), ABLFL=ifelse(v==0,"Y","N"),
 ONTRTFL=ifelse(v==0,"N","Y"), ANRIND=ind(val), BNRIND=ind(base),
 A1LO=pr$lo, A1HI=pr$hi,
 R2ULN=ifelse(pr$code %in% uln_codes, round(val/pr$hi, 2), NA_real_),
 SAFFL="Y", PKFL="Y", stringsAsFactors=FALSE) }
 }
 }
 do.call(rbind, rows)
}
sim_advs <- function(adsl, adex, d) .bds(adsl, adex, data.frame(
 code=c("SYSBP","DIABP","PULSE","TEMP","RESP"),
 param=c("Systolic BP (mmHg)","Diastolic BP (mmHg)","Pulse (beats/min)","Temperature (C)","Respiratory rate (/min)"),
 mean=c(118,75,64,36.6,14), sd=c(10,8,8,0.3,2), lo=c(90,50,50,36.0,10), hi=c(140,90,100,37.5,20),
 dp=c(0,0,0,1,0), stringsAsFactors=FALSE))
sim_adlb <- function(adsl, adex, d) {
 lb <- .bds(adsl, adex, data.frame(
 code=c("ALT","AST","BILI","CREAT","GLUC","K","SODIUM","HGB","WBC","PLAT"),
 param=c("Alanine aminotransferase (U/L)","Aspartate aminotransferase (U/L)","Total bilirubin (mg/dL)",
 "Creatinine (mg/dL)","Glucose (mg/dL)","Potassium (mmol/L)","Sodium (mmol/L)",
 "Hemoglobin (g/dL)","Leukocytes (10^9/L)","Platelets (10^9/L)"),
 mean=c(22,22,0.6,0.9,88,4.2,140,14.5,6.5,250), sd=c(8,7,0.2,0.15,8,0.3,2,1.2,1.5,50),
 lo=c(5,5,0.1,0.6,70,3.5,135,12,4,150), hi=c(40,40,1.2,1.3,100,5.1,145,17,11,400),
 dp=c(0,0,1,2,0,1,0,1,1,0), stringsAsFactors=FALSE))
 hi_subj <- sample(unique(lb$USUBJID), max(1, round(0.08*nrow(adsl)))) # inject LFT elevations
 el <- lb$USUBJID %in% hi_subj & lb$ONTRTFL=="Y" & lb$PARAMCD %in% c("ALT","AST")
 lb$AVAL[el] <- round(lb$A1HI[el]*runif(sum(el),2,4),0); lb$ANRIND[el]<-"HIGH"
 ## bilirubin elevation in an INDEPENDENT participant (do not manufacture a Hy's-Law pair)
 bili_pool <- setdiff(unique(lb$USUBJID), hi_subj)
 bili_subj <- if (length(bili_pool)) sample(bili_pool, 1) else sample(unique(lb$USUBJID), 1)
 eb <- lb$USUBJID %in% bili_subj & lb$ONTRTFL=="Y" & lb$PARAMCD=="BILI"
 lb$AVAL[eb] <- round(lb$A1HI[eb]*runif(sum(eb),1.5,2.5),1); lb$ANRIND[eb]<-"HIGH"
 lb$R2ULN <- ifelse(lb$PARAMCD %in% c("ALT","AST","BILI","CREAT"), round(lb$AVAL/lb$A1HI,2), NA_real_)
 lb$CHG <- ifelse(lb$ONTRTFL=="Y", round(lb$AVAL-lb$BASE,2), 0); lb
}
sim_adeg <- function(adsl, adex, d) .bds(adsl, adex, data.frame(
 code=c("QT","QTCF","HR","PR","QRS"),
 param=c("QT interval (ms)","QTcF interval (ms)","Heart rate (beats/min)","PR interval (ms)","QRS duration (ms)"),
 mean=c(390,410,64,160,92), sd=c(22,16,8,18,8), lo=c(320,350,50,120,70), hi=c(450,450,100,210,110),
 dp=c(0,0,0,0,0), stringsAsFactors=FALSE))

## --- orchestrate: full synthetic study -------------------------------------
simulate_study <- function(design = sample_design(), seed = 1L) {
 set.seed(seed)
 adsl <- sim_adsl(design); adex <- sim_adex(adsl, design)
 adpc <- sim_adpc(adsl, adex, design); adpp <- sim_adpp(adpc, adex)
 adae <- sim_adae(adsl, adex, design)
 advs <- sim_advs(adsl, adex, design); adlb <- sim_adlb(adsl, adex, design); adeg <- sim_adeg(adsl, adex, design)
 if (design$model == "CROSSOVER") { # ADSL period-1 trt must equal ADEX period-1 TRTA
 p1 <- adex[adex$APERIOD==1, c("USUBJID","TRTA")]
 m <- merge(adsl[,c("USUBJID","TRT01A")], p1, by="USUBJID")
 stopifnot(all(m$TRT01A == m$TRTA))
 }
 list(design = design, adsl = adsl, adex = adex, adpc = adpc, adpp = adpp,
 adae = adae, advs = advs, adlb = adlb, adeg = adeg)
}
