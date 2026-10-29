# Independent numerical checks and adverse-input tests; synthetic data only.
# Run from repository root: Rscript tests/test_analysis_models.R
suppressPackageStartupMessages({ library(dplyr); library(tidyr); library(tibble) })
source("r_tlf_pseudocode/01_analysis_models.R")
source("r_tlf_pseudocode/00_setup_helpers.R")
source("toolkit_launcher/tests/analysis_fixtures.R")
checks <- 0L
check <- function(ok, label) { if (!isTRUE(ok)) stop("FAIL: ", label); checks <<- checks + 1L }
near <- function(actual, expected, tolerance = 1e-7, label = "numerical equality") check(isTRUE(all.equal(as.numeric(actual), as.numeric(expected), tolerance = tolerance)), label)
reject <- function(expression, pattern, label) { error <- tryCatch({ force(expression); NULL }, error = identity); check(inherits(error, "error") && grepl(pattern, conditionMessage(error), ignore.case = TRUE), label) }
base_settings <- list(dose_map = "Placebo=0\nDose 10=10\nDose 20=20\nDose 40=40", dose_unit = "mg", accumulation_auc_comparable = TRUE)
settings <- function(...) options(tfl.settings = modifyList(base_settings, list(...)))
settings()

# Paired log interval: independently published t critical for df=2, not helper math.
paired <- tfl_model_paired(c(1, 1, 1), c(2, 4, 8), .95)
near(paired$ratio, 4, label = "paired geometric ratio")
near(c(paired$lower, paired$upper), c(.7149242471326539, 22.379993494655114), label = "paired known 95% interval")
scaled <- tfl_model_paired(c(1000, 1000, 1000), c(2000, 4000, 8000), .95)
near(scaled$ratio, paired$ratio, label = "paired unit-scale invariance")
rev <- tfl_model_paired(c(2, 4, 8), c(1, 1, 1), .95)
near(c(rev$ratio, rev$lower, rev$upper), 1/c(paired$ratio, paired$upper, paired$lower), label = "paired reference reversal")
check(is.na(tfl_model_paired(1, 2)$lower), "one pair cannot supply confidence limits")
check(tfl_model_paired(c(1, 0, NA), c(2, 3, 4))$excluded_pairs == 2, "nonpositive and missing pairs counted")

# Power model independently computed from centered log dose and residual sums.
power_data <- tibble(USUBJID = letters[1:9], dose = rep(c(10, 20, 40), each = 3), value = exp(2 + 1.2*log(dose) + c(-.12, .02, .1, -.03, .08, -.05, .06, -.09, .03)))
x <- log(power_data$dose); y <- log(power_data$value)
beta <- sum((x - mean(x))*(y - mean(y)))/sum((x - mean(x))^2)
residual <- y - mean(y) - beta*(x - mean(x))
se <- sqrt(sum(residual^2)/(length(x) - 2)/sum((x - mean(x))^2))
ci <- beta + c(-1, 1)*qt(.95, length(x) - 2)*se
power <- tfl_model_power(power_data)
near(c(power$beta, power$lower, power$upper), c(beta, ci), label = "power model independent OLS oracle")
near(power$critical_lower, 1+log(.8)/log(4), label = "power critical region uses observed range")
near(tfl_model_power(power_data[9:1, ])$beta, beta, label = "power row-order invariance")
near(tfl_model_power(mutate(power_data, dose = dose/1000, value = value*1000))$beta, beta, label = "power unit-scale invariance")
check(grepl("Not estimable", tfl_model_power(filter(power_data, dose == 10))$status), "single dose is not estimable")
reject(tfl_model_power(bind_rows(power_data, power_data[1, ])), "duplicate", "power duplicate rejected")
settings(dose_map = "Dose 10=10\nDose 20=20")
reject(tfl_model_dose(c("Dose 10", "Dose 40")), "missing treatment", "unmapped dose rejected")
settings(dose_map = "Dose 10=-1")
reject(tfl_model_dose("Dose 10"), "nonnegative", "negative dose rejected")
settings(dose_unit = "")
reject(tfl_model_dose("Dose 10"), "unit", "missing dose unit rejected")
settings()

# Integration checks: each parameter uses only its observed dose range; ordering
# codes cannot change doses, and a configured subset excludes other parameters.
sad <- analysis_fixture("sad")
subset_pp <- sad$adpp %>% filter(!(PARAMCD == "CMAX" & TRT01A == "Dose 40"))
proportional <- tfl_model_dose_proportionality(subset_pp)
near(proportional$dose_ratio[proportional$parameter == "CMAX"], 2, label = "parameter-specific dose range")
near(proportional$dose_ratio[proportional$parameter == "AUCLST"], 4, label = "other parameter retains observed dose range")
recoded <- subset_pp; recoded$TRT01AN <- 700 + seq_len(nrow(recoded))
near(tfl_model_dose_proportionality(recoded)$beta, proportional$beta, label = "treatment ordering codes cannot alter actual doses")
settings(pk_parameters = "CMAX")
check(identical(tfl_model_dose_proportionality(subset_pp)$parameter, "CMAX"), "configured PK parameter selection applied")
settings()

# Balanced 2x2 crossover: direct oracle on the within-participant log contrasts.
n <- 12L; period <- rep(1:2, times = n); id <- rep(seq_len(n), each = 2)
seq_id <- rep(rep(c("RT", "TR"), each = n/2), each = 2)
arm <- ifelse((seq_id == "RT" & period == 2) | (seq_id == "TR" & period == 1), "Test", "Reference")
noise <- .07*sin(1.7*id + 2.3*period) + .02*cos(id*period)
be_data <- tibble(USUBJID = paste0("S", id), PKFL = "Y", PARAMCD = "CMAX", AVALU = "ng/mL", APERIOD = period, TRTA = arm, TRTSEQP = seq_id,
                 AVAL = exp(3 + .3*sin(id) + log(1.1)*(arm == "Test") + .04*(period == 2) + noise))
settings(pk_parameters = "CMAX")
be <- tfl_model_be(be_data, "CROSSOVER")
wide <- be_data %>% mutate(log_value = log(AVAL)) %>% select(USUBJID, TRTSEQP, TRTA, log_value) %>% pivot_wider(names_from = TRTA, values_from = log_value) %>% mutate(delta = Test - Reference)
a <- wide$delta[wide$TRTSEQP == "RT"]; b <- wide$delta[wide$TRTSEQP == "TR"]
expected <- (mean(a) + mean(b))/2
pooled <- ((length(a)-1)*var(a) + (length(b)-1)*var(b))/(n-2)
half <- qt(.95, n-2)*sqrt(pooled*(1/length(a)+1/length(b))/4)
near(c(be$gmr, be$lower, be$upper), exp(c(expected, expected-half, expected+half)), 1e-5, "BE independent balanced crossover oracle")
near(be$df, n-2, 1e-5, "BE pinned Satterthwaite df")
reverse_data <- be_data %>% mutate(TRTA = if_else(TRTA == "Test", "Reference", "Test"))
reverse_be <- tfl_model_be(reverse_data, "CROSSOVER")
near(c(reverse_be$gmr, reverse_be$lower, reverse_be$upper), 1/c(be$gmr, be$upper, be$lower), 1e-5, "BE reference reversal")
near(tfl_model_be(be_data[nrow(be_data):1, ], "CROSSOVER")$gmr, be$gmr, label = "BE order invariance")
check(tfl_model_be(be_data[-1, ], "CROSSOVER")$excluded_participants == 1, "BE incomplete pair counted")
reject(tfl_model_be(bind_rows(be_data, be_data[1, ]), "CROSSOVER"), "duplicate", "BE duplicate rejected")
reject(tfl_model_be(mutate(be_data, TRTSEQP = "One sequence"), "CROSSOVER"), "2x2", "BE unsupported design rejected")
mixed_units <- be_data; mixed_units$AVALU[1] <- "ug/mL"
reject(tfl_model_be(mixed_units, "CROSSOVER"), "Mixed units", "BE mixed units rejected")
# Fixed-sequence CI agrees with the paired log t interval when the model is estimable.
fixed <- be_data %>% mutate(APERIODC = if_else(APERIOD == 1, "Reference", "Test"))
fb <- tfl_model_be(fixed, "SINGLESEQ")
fwide <- fixed %>% select(USUBJID, APERIODC, AVAL) %>% pivot_wider(names_from = APERIODC, values_from = AVAL)
fp <- tfl_model_paired(fwide$Reference, fwide$Test, .9)
near(c(fb$gmr, fb$lower, fb$upper), c(fp$ratio, fp$lower, fp$upper), 1e-5, "fixed-sequence paired t oracle")
settings()

# Rich MAD fixture: actual window and occasion choices have observable consequences.
mad <- analysis_fixture("mad")
acc <- tfl_model_accumulation(mad$adpp, mad$adpc)
check(nrow(acc$ratios) == 6L && all(acc$ratios$n_paired == 6L), "MAD paired ratio counts")
check(all(acc$troughs$ADY >= 5 & acc$troughs$ADY <= 14), "MAD trough window applied")
changed <- mad$adpc; changed$AVAL[changed$ADY == 1] <- changed$AVAL[changed$ADY == 1] * 1e6
near(tfl_model_accumulation(mad$adpp, changed)$troughs$mean, acc$troughs$mean, label = "outside-window records cannot change trend summary")
settings(steady_state_first_day = 7, trough_last_day = 14)
check(setequal(tfl_model_accumulation(mad$adpp, mad$adpc)$troughs$ADY, c(7, 14)), "configured trough window changes selected days")
settings(accumulation_auc_comparable = FALSE)
a <- tfl_model_accumulation(mad$adpp, mad$adpc)$ratios
check(all(is.na(a$ratio[a$parameter == "AUC"])), "unconfirmed AUC intervals are not compared")
settings()
reject(tfl_model_accumulation(bind_rows(mad$adpp, filter(mad$adpp, PARAMCD == "CMAX", ADY == 1)[1, ]), mad$adpc), "duplicate", "accumulation duplicate pairs rejected")
pd <- tfl_model_pd_data(mad$adpd, design_vars("MAD"))
pds <- tfl_model_pd_summary(pd)
check(all(c(1, 5, 7, 14) %in% pds$ADY) && all(pds$n == 6), "PD day/time denominators remain distinct")
peak <- tfl_model_pd_peak(pd)
pd$AVAL[pd$ADY != 14] <- pd$AVAL[pd$ADY != 14] * 1e8
near(tfl_model_pd_peak(pd)$beta, peak$beta, label = "PD peak model selects configured day")
reject(tfl_model_pd_data(bind_rows(mad$adpd, mad$adpd[1, ]), design_vars("MAD")), "duplicate", "PD duplicate analysis key rejected")
constant_overlay <- mad; constant_overlay$adpc$AVAL <- 3; constant_overlay$adpd$AVAL <- 10
ov <- tfl_model_overlay(constant_overlay$adpc, constant_overlay$adpd, design_vars("MAD"))
check(all(is.finite(ov$mean)), "constant overlay values do not cause division by zero")

# Closed polygon and shared-placebo SE checked independently.
near(tfl_model_loop_area(c(0,1,1,0), c(0,0,1,1)), 1, label = "unit-square signed area")
near(tfl_model_loop_area(c(0,1,1,0), c(0,0,1,1)+17), 1, label = "area translation invariance")
near(tfl_model_loop_area(rev(c(0,1,1,0)), rev(c(0,0,1,1))), -1, label = "area orientation reverses sign")
A <- c(1,2,4,5); H <- c(-2,-1,1,2)
at <- tfl_model_area_test(A,H)
near(at$se, sqrt(var(A)/4 + var(H)/4), label = "shared placebo variance included")
check(at$se > sqrt(var(A)/4), "placebo uncertainty increases area SE")
check(grepl("zero", tfl_model_area_test(rep(0,4),rep(0,4))$status), "zero-variance area not assigned a p value")

# Execute complete linear/Emax diagnostic on synthetic data with known f(C).
make_cqtc <- function(form = "LINEAR", delay = FALSE) {
  a <- analysis_fixture("mad")
  pc <- a$adpc %>% filter(PARAMCD == "CONC") %>% select(USUBJID, ADY, ATPTN, conc = AVAL)
  a$adeg <- a$adeg %>% left_join(pc, by = c("USUBJID", "ADY", "ATPTN"))
  ii <- as.integer(factor(a$adeg$USUBJID)); tt <- a$adeg$ATPTN
  use <- a$adeg$PARAMCD == "QTCF" & a$adeg$ADY %in% c(1,14)
  cval <- ifelse(is.finite(a$adeg$conc), a$adeg$conc, 0)
  effect <- if (form == "LINEAR") .1*cval else 16*cval/(12+cval)
  placebo <- a$adeg$TRT01A == "Placebo"
  effect[placebo] <- 0
  a$adeg$CHG[use] <- (.25*sin(tt) + .2*cos(ii) + effect + .025*sin(ii*1.3+tt*2.1))[use]
  if (delay) a$adeg$CHG[use & !placebo] <- a$adeg$CHG[use & !placebo] + 2*sin(tt[use & !placebo]/2)
  a$adeg$conc <- NULL
  a
}
settings(cqtc_form = "LINEAR")
linear_data <- make_cqtc(); prep <- tfl_model_cqtc_data(linear_data$adpc, linear_data$adeg, TRUE)
linear <- tfl_model_cqtc(prep)
near(linear$coefficients$estimate[linear$coefficients$term == "conc"], .1, .01, "linear C-QTc known concentration slope")
check(nrow(linear$summary) == 8 && all(is.finite(linear$summary$p_two_sided)), "linear complete diagnostic table")
near(tfl_model_cqtc(tfl_model_cqtc_data(linear_data$adpc[nrow(linear_data$adpc):1, ], linear_data$adeg[nrow(linear_data$adeg):1, ], TRUE))$summary$estimate, linear$summary$estimate, 1e-6, "C-QTc row-order invariance")
loop_profile <- tfl_model_cqtc_profile(prep)
manual <- prep$cq %>% filter(trt == "Dose 10", ADY == 1, ATPTN == 0)
near(loop_profile$se[1], sqrt(var(manual$ddqtcf)/nrow(manual) + manual$pbo_variance[1]), label = "figure SE includes placebo mean uncertainty")
delayed_data <- make_cqtc(delay = TRUE)
delayed <- tfl_model_cqtc(tfl_model_cqtc_data(delayed_data$adpc, delayed_data$adeg, TRUE))
check(max(abs(delayed$summary$estimate - linear$summary$estimate)) > .1, "time-delay perturbation changes diagnostic areas")
settings(cqtc_form = "EMAX")
emax_data <- make_cqtc("EMAX")
emax <- tfl_model_cqtc(tfl_model_cqtc_data(emax_data$adpc, emax_data$adeg, TRUE))
near(emax$coefficients$estimate[emax$coefficients$term == "ec50"], 12, .1, "Emax known EC50 recovery")
near(emax$coefficients$estimate[emax$coefficients$term == "emax"], 16, .03, "Emax known maximum-effect recovery")
settings()
bad <- linear_data$adpc; bad <- bad[!((bad$USUBJID == unique(prep$cq$USUBJID)[1]) & bad$ADY == 1 & bad$ATPTN == 0), ]
reject(tfl_model_cqtc_data(bad, linear_data$adeg, TRUE), "matching", "missing matched concentration rejected")
bad <- linear_data$adeg; bad <- bad[!(bad$TRT01A == "Placebo" & bad$ADY == 1 & bad$ATPTN == 0 & bad$PARAMCD == "QTCF"), ]
reject(tfl_model_cqtc_data(linear_data$adpc, bad, TRUE), "incomplete", "missing placebo times rejected")
reject(tfl_model_cqtc_data(linear_data$adpc, bind_rows(linear_data$adeg, filter(linear_data$adeg, PARAMCD == "QTCF", ADY == 1)[1, ]), TRUE), "duplicate", "duplicate ECG analysis rows rejected")
bad <- prep; bad$cq$conc <- 1
reject(tfl_model_cqtc(bad), "variation", "nonidentifiable direct-effect model rejected")
# Execute every completed model/PD source wrapper and build its complete plots.
# Reuse the loaded helpers so each wrapper executes in an isolated fixture environment.
model_stems <- c("t_be_anova", "t_dose_proportionality", "t_dose_proportionality_ss", "t_accumulation", "t_pd_summary", "f_pd_change", "f_pkpd_overlay", "t_cqtc_hysteresis", "f_cqtc_hysteresis")
wrapper_count <- 0L
for (design in c("parallel", "crossover", "single_sequence", "sad", "mad")) {
  paths <- list.files(file.path("r_tlf_pseudocode", design), pattern = "[.]R$", full.names = TRUE)
  paths <- paths[tools::file_path_sans_ext(basename(paths)) %in% model_stems]
  for (path in paths) {
    settings()
    e <- new.env(parent = globalenv()); e$adam <- analysis_fixture(design); e$components <- list()
    e$source <- function(...) invisible(NULL)
    e$setup <- function(...) list(out = tempdir())
    e$print <- function(x, ...) {
      if (inherits(x, "ggplot")) ggplot2::ggplot_build(x)
      else if (is.data.frame(x)) check(nrow(x) > 0L && ncol(x) > 0L, paste("nonempty component", path))
      else stop("Unsupported rendered component in ", path)
      e$components[[length(e$components) + 1L]] <- x
      invisible(x)
    }
    sys.source(path, envir = e)
    check(length(e$components) > 0L, paste("wrapper rendered", path))
    wrapper_count <- wrapper_count + 1L
  }
}
check(wrapper_count == 24L, "all 24 completed model/PD source wrappers executed")
# Treatment order codes carry no pharmacological meaning. Changing an active
# arm to code zero and placing placebo last must only affect display ordering.
capture_table_source <- function(path, data) {
  e <- new.env(parent = globalenv()); e$adam <- data; result <- list()
  e$source <- function(...) invisible(NULL)
  e$setup <- function(...) list(study = "SYNTHETIC-QC", out = tempdir())
  e$print <- function(x, ...) { result[[length(result)+1L]] <<- x; invisible(x) }
  sys.source(path, envir = e)
  result
}
canonical_table <- function(d) {
  columns <- sort(names(d)); d <- as.data.frame(d[, columns, drop = FALSE])
  rows <- if(nrow(d)) apply(d, 1, function(row) paste(ifelse(is.na(row), "<missing>", as.character(row)), collapse = " | ")) else character()
  list(columns = columns, rows = sort(rows))
}
order_stems <- c("t_disposition", "t_demographics", "t_exposure", "t_medical_history", "t_prior_con_meds", "t_protocol_deviations")
for (design in c("sad", "mad")) {
  original <- analysis_fixture(design)
  reordered <- lapply(original, function(d) {
    if(all(c("TRT01A", "TRT01AN") %in% names(d))) d$TRT01AN <- ifelse(d$TRT01A == "Dose 10", 0, ifelse(d$TRT01A == "Placebo", 999, d$TRT01AN))
    d
  })
  for (stem in c(order_stems, if (design == "sad") "t_ada_impact_pk")) {
    settings()
    path <- file.path("r_tlf_pseudocode", design, paste0(stem, ".R"))
    before <- lapply(capture_table_source(path, original), canonical_table)
    after <- lapply(capture_table_source(path, reordered), canonical_table)
    check(identical(before, after), paste(design, stem, "preserves counts and labels after active ordering code becomes zero"))
  }
}
settings(placebo_label = "Vehicle control")
custom <- analysis_fixture("sad")
for (slot in names(custom)) if ("TRT01A" %in% names(custom[[slot]])) custom[[slot]]$TRT01A[custom[[slot]]$TRT01A == "Placebo"] <- "Vehicle control"
control_pk <- custom$adpp[1, ]; control_pk$USUBJID <- custom$adsl$USUBJID[custom$adsl$TRT01A == "Vehicle control"][1]
control_pk$TRT01A <- "Vehicle control"; control_pk$TRT01AN <- 999; control_pk$PKFL <- "Y"
custom$adpp <- bind_rows(custom$adpp, control_pk)
custom_ada <- capture_table_source("r_tlf_pseudocode/sad/t_ada_impact_pk.R", custom)
check(!any(grepl("Vehicle control", names(custom_ada[[1]]), fixed = TRUE)), "SAD ADA exposure excludes the explicitly configured placebo label")
settings()
cat(sprintf("PASS: %d model/QC assertions; %d model source wrappers plus 13 treatment-order metamorphic source comparisons\n", checks, wrapper_count))
