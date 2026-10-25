#!/usr/bin/env Rscript
################################################################################
# run_lifecycle.R: full SIMULATED study life cycle on one tool stack:
# calibrated design -> synthetic ADaM -> TLF computations -> SLM draft
# All participant-level data is SYNTHETIC (domain priors); only the design STRUCTURE
# is calibrated to the public Phase-1 corpus (ClinicalTrials.gov). Not real clinical data (100% synthetic).
# Run from repo root: Rscript sim_lifecycle/run_lifecycle.R
################################################################################
source("sim_lifecycle/simulate_adam.R")

## --- 1. sample a design (a bioequivalence crossover, the dominant archetype) and simulate.
## simulate_study() sets the seed first and then draws the design, so this one call regenerates
## the committed out/*.csv byte for byte; validation_harness/run_harness.sh (G1) checks the same call.
adam <- simulate_study(sample_design(archetype = "BE", N = 40), seed = 2026)
design <- adam$design
cat(sprintf("\n================ SIMULATED STUDY (calibrated design) ================\n"))
cat(sprintf("Archetype: %s | model: %s | N=%d | site: %s | healthy: %s\n",
 design$archetype, design$model, design$N, design$site, design$healthy))

## --- 2. demographics TLF (ADSL) -------------------------------------------
a <- adam$adsl
cat(sprintf("\n[T] Demographics: age %.1f (%.1f) | %d F / %d M | weight %.1f kg | BMI %.1f\n",
 mean(a$AGE), sd(a$AGE), sum(a$SEX=="F"), sum(a$SEX=="M"), mean(a$WEIGHTBL), mean(a$BMIBL)))

## --- 3. PK NCA summary (ADPP): geometric, on the log scale ----------------
## results: the printed results, unrounded, written to out/results_summary.csv in step 7 so the
## harness (G9) can recompute them independently; the printout rounds them
results <- list()
keep <- function(section, paramcd, group, stat, value) results[[length(results) + 1]] <<-
 data.frame(SECTION=section, PARAMCD=paramcd, GROUP=group, STAT=stat, VALUE=as.numeric(value), stringsAsFactors=FALSE)
geo <- function(param) {
 s <- adam$adpp[adam$adpp$PARAMCD==param, ]
 do.call(rbind, lapply(split(s$AVAL, s$TRTA), function(x){ x<-x[x>0]
 data.frame(n=length(x), geomean=exp(mean(log(x))),
 geocv=100*sqrt(exp(var(log(x)))-1)) })) }
cat("\n[T] PK NCA: geometric mean (Geo CV%) by treatment:\n")
for (p in c("CMAX","AUCLST","AUCIFO")) { g <- geo(p)
 cat(sprintf(" %-7s Test: %s (%.1f%%) | Reference: %s (%.1f%%)\n", p,
 round(g["Test","geomean"],3), round(g["Test","geocv"],1), round(g["Reference","geomean"],3), round(g["Reference","geocv"],1)))
 for (trt in rownames(g)) { keep("PK_GEO", p, trt, "N", g[trt,"n"]); keep("PK_GEO", p, trt, "GEOMEAN", g[trt,"geomean"])
 keep("PK_GEO", p, trt, "GEOCV_PCT", g[trt,"geocv"]) } }

## --- 4. Bioequivalence (crossover ANOVA on log scale): GMR + 90% CI --------
be <- function(param) {
 s <- adam$adpp[adam$adpp$PARAMCD==param, ]
 s$TRTA <- relevel(factor(s$TRTA), ref="Reference")
 fit <- lm(log(AVAL) ~ factor(USUBJID) + factor(APERIOD) + TRTA, data=s)
 co <- summary(fit)$coefficients; r <- grep("TRTATest", rownames(co))
 est <- co[r,1]; se <- co[r,2]; tc <- qt(0.95, fit$df.residual)
 data.frame(param=param, GMR=100*exp(est),
 lo=100*exp(est-tc*se), hi=100*exp(est+tc*se),
 intra_cv=100*sqrt(exp(summary(fit)$sigma^2)-1)) }
cat("\n[T] Bioequivalence (Test vs Reference): GMR and 90% CI:\n")
for (p in c("CMAX","AUCLST")) { b <- be(p)
 # the 80.00-125.00% decision uses the unrounded limits (ICH M13A)
 cat(sprintf(" %-7s GMR %.1f%% 90%% CI %.1f-%.1f%% intra-CV %.1f%% within 80-125%%: %s\n",
 p, round(b$GMR,1), round(b$lo,1), round(b$hi,1), round(b$intra_cv,1), ifelse(b$lo>=80 & b$hi<=125,"YES","no")))
 keep("BE", p, "Test vs Reference", "GMR_PCT", b$GMR); keep("BE", p, "Test vs Reference", "LCL90_PCT", b$lo)
 keep("BE", p, "Test vs Reference", "UCL90_PCT", b$hi); keep("BE", p, "Test vs Reference", "INTRA_CV_PCT", b$intra_cv) }

## --- 5. AE overview TLF (ADAE): distinct participants --------------------------
ae <- adam$adae; N <- nrow(adam$adsl)
nUSj <- function(f) length(unique(ae$USUBJID[f]))
ae_result <- data.frame(
 category = c("Any TEAE","Related TEAE","Severe TEAE","SAE",
 "TEAE leading to discontinuation","Death"),
 n = c(if(nrow(ae)) length(unique(ae$USUBJID)) else 0,
 nUSj(ae$AREL=="RELATED"), nUSj(ae$AESEVN==3), nUSj(ae$AESER=="Y"), 0, 0))
ae_result$pct <- round(100*ae_result$n/N, 1)
cat(sprintf("\n[T] AE overview (N=%d): any TEAE %d (%.1f%%), related %d, severe %d, SAE %d\n",
 N, ae_result$n[1], ae_result$pct[1], ae_result$n[2], ae_result$n[3], ae_result$n[4]))
keep("AE", "", "Safety population", "N", N)
for (i in 1:4) keep("AE", "", ae_result$category[i], "N_PARTICIPANTS", ae_result$n[i])

## --- 6. SLM interpretation (the tlf_interpret pipeline) --------------------
source("tlf_interpret/R/slm_client.R")
source("tlf_interpret/R/extract_facts.R")
source("tlf_interpret/R/validate_interpretation.R")
source("tlf_interpret/R/interpret.R")
facts <- extract_facts("t_ae_overview", ae_result, arm = paste(design$archetype,"(Test)"), N = N)
res <- interpret_tlf("t_ae_overview", facts)
cat(sprintf("\n[SLM] interpretation status: %s (model: %s%s)\n",
 res$status, res$audit$model_name, if (isTRUE(res$audit$stub)) ": STUB, no model installed" else ""))
cat(sprintf("[SLM] numeric-consistency: %s (%d numbers checked)\n",
 ifelse(res$validation$numbers$ok,"PASS","FAIL"), res$validation$numbers$n_checked))
cat("[SLM] draft:\n ", res$draft, "\n", sep="")

## --- 6b. safety TLFs on the new domains (ADVS / ADLB / ADEG) ---------------
onb <- function(dom, code) adam[[dom]][adam[[dom]]$PARAMCD==code & adam[[dom]]$ONTRTFL=="Y", ]
abr <- function(dom) { s <- adam[[dom]][adam[[dom]]$ONTRTFL=="Y", ]; round(100*mean(s$ANRIND!="NORMAL"),1) }
cat(sprintf("\n[T] Vitals: on-treatment SBP mean %.0f mmHg | %.1f%% of vital readings out of range\n",
 mean(onb("advs","SYSBP")$AVAL), abr("advs")))
altmax <- aggregate(AVAL~USUBJID, onb("adlb","ALT"), max)
cat(sprintf("[T/F] Labs: %d participants ALT>ULN on-treatment (peak ALT/ULN %.1f) | %.1f%% labs abnormal | LFT scatter: %d participants plottable\n",
 sum(altmax$AVAL>40), max(onb("adlb","ALT")$R2ULN), abr("adlb"), length(unique(adam$adlb$USUBJID))))
cat(sprintf("[T] ECG: on-treatment QTcF mean %.0f ms, max %.0f ms | %.1f%% QTcF > 450 ms\n",
 mean(onb("adeg","QTCF")$AVAL), max(onb("adeg","QTCF")$AVAL), round(100*mean(onb("adeg","QTCF")$AVAL>450),1)))

## --- 6c. CALIBRATION CHECK: Monte-Carlo (large N) sim vs FITTED targets -----
## Estimate on a big simulated study so the CV estimate is stable (a single
## N=40 study's empirical CV is noisy).
cal <- simulate_study(sample_design(archetype = "BE", N = 400), seed = 99)
cvsim <- function(p){ v<-cal$adpp$AVAL[cal$adpp$PARAMCD==p]; v<-v[v>0]; round(100*sqrt(exp(var(log(v)))-1),1) }
tmed <- function(p) round(median(cal$adpp$AVAL[cal$adpp$PARAMCD==p]),1)
cat("\n[CALIBRATION CHECK] Monte-Carlo N=400 vs fitted-from-42-studies\n")
cat(sprintf(" Cmax CV%% %5.1f vs 36\n", cvsim("CMAX")))
cat(sprintf(" AUClast CV%% %5.1f vs 33\n", cvsim("AUCLST")))
cat(sprintf(" Tmax median %5.1f h vs 1.0 h\n", tmed("TMAX")))
cat(sprintf(" t1/2 median %5.1f h vs 7.8 h\n", tmed("T12")))
cat(sprintf(" any-AE rate %5.3f vs 0.430\n", round(length(unique(cal$adae$USUBJID))/nrow(cal$adsl),3)))

## --- 7. persist the simulated study ----------------------------------------
dir.create("sim_lifecycle/out", showWarnings = FALSE)
for (nm in c("adsl","adex","adpc","adpp","adae","advs","adlb","adeg"))
 { d <- adam[[nm]]; dbl <- vapply(d, is.double, logical(1))
   # 12 significant digits: the 15th-16th digits of derived doubles differ between macOS and
   # Linux libm, which broke the byte-for-byte regeneration check in CI.
   d[dbl] <- lapply(d[dbl], signif, digits = 12)
   write.csv(d, sprintf("sim_lifecycle/out/%s.csv", nm), row.names = FALSE) }
## the printed results, unrounded (10 significant digits): a ninth file, which G1 does not compare;
## the harness's independent recomputation (G9) checks it
rs <- do.call(rbind, results); rs$VALUE <- signif(rs$VALUE, 10)
write.csv(rs, "sim_lifecycle/out/results_summary.csv", row.names = FALSE)
cat("\nSimulated ADaM written to sim_lifecycle/out/ (adsl,adex,adpc,adpp,adae,advs,adlb,adeg)\n")
cat("Printed results written to sim_lifecycle/out/results_summary.csv\n")
cat("================ END SIMULATED LIFE CYCLE ================\n")
