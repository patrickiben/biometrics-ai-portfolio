################################################################################
# 05_qc/qc.R: re-derivation by a second method, compared with diffdf 1.1.2 at explicit
# tolerances. SYNTHETIC DATA ONLY.
#
# What this is: SAME-AUTHOR re-derivation. The same person wrote the primary programs
# and these checks, from the same SAP, in the same session. It is NOT independent double
# programming by a second programmer, and it cannot catch a misreading of the SAP that
# both routes share. What it can catch: coding slips, engine-specific defaults, and
# experimental helpers that behave unexpectedly.
#
#   Q1  NCA: NonCompart 0.8.4 tblNCA() vs PKNCA 0.12.1, same input, per parameter
#   Q2  BE model: closed-form two-sample t-test on within-participant period differences
#       vs the GLM (lm)
#   Q3  BE model: nlme::lme() with a random participant effect vs the GLM (equal for
#       complete crossover data)
#   Q4  ADPC times: NFRLT (admiral derive_var_nfrlt(), EXPERIMENTAL), ARRLT and AFRLT
#       vs base-R arithmetic on the SDTM-like PC and EX dates
#   Q5  ADSL population flags vs a base-R re-derivation from the SDTM-like domains and PP
#   Q6  Table 14.3.1.1 counts vs a base-R count from the SDTM-like AE and EX domains
#   Q7  control: a planted 0.1% change in one AUC(0-t) must give exactly one mismatch
#
# Inputs : objects adpc, adpp, adsl, nca_wide, be_results, TLF; 03_adam/sdtm/*.csv
# Outputs: 05_qc/qc_ledger.json, qc_ledger.csv, qc_ledger.html, qc_nca_differences.csv
################################################################################
suppressPackageStartupMessages({ library(diffdf); library(NonCompart) })
SAP <- jsonlite::read_json(sp("02_sap", "analysis_parameters.json"), simplifyVector = TRUE)
ledger <- list()

## compare one column at a time so each gets its own documented tolerance
cmp <- function(id, item, base, compare, keys, cols, tol, primary, qc_method) {
  for (cl in cols) {
    b <- base[, c(keys, cl)]; cpr <- compare[, c(keys, cl)]
    if (is.numeric(b[[cl]]) && is.numeric(cpr[[cl]])) { b[[cl]] <- as.double(b[[cl]]); cpr[[cl]] <- as.double(cpr[[cl]]) }  # values, not storage type
    d <- suppressMessages(suppressWarnings(diffdf(b, cpr, keys = keys, tolerance = tol[[cl]] %||% tol[[1]], suppress_warnings = TRUE)))
    vd <- d[[paste0("VarDiff_", cl)]]
    nmis <- if (is.null(vd)) 0L else nrow(vd)
    other <- setdiff(names(d), c(paste0("VarDiff_", cl), "DataSummary", "NumDiff"))
    j <- merge(b, cpr, by = keys, suffixes = c(".b", ".c"))
    dif <- suppressWarnings(abs(as.numeric(j[[paste0(cl, ".b")]]) - as.numeric(j[[paste0(cl, ".c")]])))
    ledger[[length(ledger) + 1]] <<- data.frame(
      id = id, item = item, variable = cl, primary = primary, qc = qc_method, n_compared = nrow(j),
      tolerance = tol[[cl]] %||% tol[[1]], mismatches = nmis + length(other),
      max_abs_diff = if (all(is.na(dif))) NA_real_ else max(dif, na.rm = TRUE),
      status = ifelse(nmis + length(other) == 0, "pass", "fail"))
  }
}

## --- Q1 NCA -------------------------------------------------------------------------------
nc_in <- adpc %>% filter(PARAMCD == "SIMDRUG", ANL01FL == "Y") %>%
  mutate(TIME = pmax(ARRLT, 0)) %>% arrange(USUBJID, APERIOD, TIME) %>%
  select(USUBJID, APERIOD, TIME, AVAL) %>% as.data.frame()
nc <- tblNCA(nc_in, key = c("USUBJID", "APERIOD"), colTime = "TIME", colConc = "AVAL", dose = STUDY$dose_mg,
             adm = "Extravascular", doseUnit = "mg", timeUnit = "h", concUnit = "ng/mL",
             down = "Log", R2ADJ = SAP$nca$min_hl_r_squared)
nc_par <- c("CMAX", "TMAX", "TLST", "CLST", "AUCLST", "AUCIFO", "AUCPEO", "LAMZHL", "LAMZ", "LAMZNPT", "R2ADJ", "LAMZLL", "LAMZUL")
nc_w <- as.data.frame(nc)[, c("USUBJID", "APERIOD", nc_par)]
for (v in nc_par) nc_w[[v]] <- as.numeric(nc_w[[v]])
nc_w$APERIOD <- as.integer(nc_w$APERIOD)
pk_w <- as.data.frame(nca_wide)[, c("USUBJID", "APERIOD", nc_par)]
pk_w$APERIOD <- as.integer(pk_w$APERIOD)
nca_tol <- list(CMAX = 1e-9, CLST = 1e-9, TMAX = 1e-9, TLST = 1e-9, LAMZLL = 1e-9, LAMZUL = 1e-9, LAMZNPT = 0,
                AUCLST = 1e-6, AUCIFO = 1e-6, AUCPEO = 1e-6, LAMZHL = 1e-6, LAMZ = 1e-9, R2ADJ = 1e-9)
cmp("Q1", "NCA parameters per profile", pk_w, nc_w, c("USUBJID", "APERIOD"), nc_par, nca_tol,
    "PKNCA 0.12.1 pk.nca()", "NonCompart 0.8.4 tblNCA()")
nca_diff <- merge(pk_w, nc_w, by = c("USUBJID", "APERIOD"), suffixes = c("_PKNCA", "_NonCompart"))
write_csv_det(nca_diff, sp("05_qc", "qc_nca_side_by_side.csv"))

## --- Q2 and Q3 BE model ----------------------------------------------------------------------
be_alt <- function(p) {
  d <- adpp %>% filter(PARAMCD == p, ANL02FL == "Y") %>% mutate(y = log(AVAL)) %>%
    select(USUBJID, TRTSEQP, APERIOD, TRTA, y)
  w <- d %>% select(USUBJID, TRTSEQP, APERIOD, y) %>% pivot_wider(names_from = APERIOD, values_from = y, names_prefix = "P")
  w$hd <- (w$P2 - w$P1) / 2                                     # half period difference
  a <- w$hd[w$TRTSEQP == "TR"]; b <- w$hd[w$TRTSEQP == "RT"]
  est <- mean(b) - mean(a)                                      # TR: (R - T)/2 + pi; RT: (T - R)/2 + pi
  s2 <- (sum((a - mean(a))^2) + sum((b - mean(b))^2)) / (length(a) + length(b) - 2)
  dfe <- length(a) + length(b) - 2; se <- sqrt(s2 * (1 / length(a) + 1 / length(b)))
  tq <- qt(1 - (1 - SAP$ci_level) / 2, dfe)
  B <- data.frame(PARAMCD = p, ratio = exp(est), lower = exp(est - tq * se), upper = exp(est + tq * se),
                  cv_within = 100 * sqrt(exp(2 * s2) - 1), df = dfe)
  dd <- d %>% mutate(SEQ = factor(TRTSEQP), PER = factor(APERIOD), TRT = factor(TRTA, levels = c("Reference", "Test")))
  ## tight convergence settings: with the defaults the REML sigma agrees with the GLM only to about 5e-6
  ## percentage points of CV, which is optimizer tolerance, not a difference in the model
  m <- nlme::lme(y ~ SEQ + PER + TRT, random = ~ 1 | USUBJID, data = dd, method = "REML",
                 control = nlme::lmeControl(msTol = 1e-14, tolerance = 1e-14, maxIter = 500, msMaxIter = 500, niterEM = 100, opt = "optim"))
  tt <- summary(m)$tTable["TRTTest", ]
  tq2 <- qt(1 - (1 - SAP$ci_level) / 2, tt[["DF"]])
  C <- data.frame(PARAMCD = p, ratio = exp(tt[["Value"]]), lower = exp(tt[["Value"]] - tq2 * tt[["Std.Error"]]),
                  upper = exp(tt[["Value"]] + tq2 * tt[["Std.Error"]]), cv_within = 100 * sqrt(exp(m$sigma^2) - 1), df = tt[["DF"]])
  list(B = B, C = C)
}
alt <- lapply(be_results$PARAMCD, be_alt)
bB <- do.call(rbind, lapply(alt, `[[`, "B")); bC <- do.call(rbind, lapply(alt, `[[`, "C"))
bA <- be_results[, c("PARAMCD", "ratio", "lower", "upper", "cv_within", "df")]
cmp("Q2", "BE ratio, 90% CI and within-participant CV", bA, bB, "PARAMCD", c("ratio", "lower", "upper", "cv_within", "df"),
    list(ratio = 1e-10, df = 0), "lm() GLM (02_be.R)", "two-sample t-test on half period differences (closed form)")
cmp("Q3", "BE ratio, 90% CI and within-participant CV", bA, bC, "PARAMCD", c("ratio", "lower", "upper", "cv_within", "df"),
    list(ratio = 1e-6, df = 0), "lm() GLM (02_be.R)", "nlme::lme() REML, random participant")

## --- Q4 ADPC times from the SDTM-like dates ----------------------------------------------------
pc_s <- read_sdtm("pc"); ex_s <- read_sdtm("ex")
tz <- function(x) as.POSIXct(x, format = "%Y-%m-%dT%H:%M", tz = "UTC")
dose_by <- ex_s %>% transmute(USUBJID, VISITNUM, DOSE_T = tz(EXSTDTC))
first_d <- dose_by %>% group_by(USUBJID) %>% summarise(FIRST_T = min(DOSE_T), .groups = "drop")
q4 <- pc_s %>% left_join(dose_by, by = c("USUBJID", "VISITNUM")) %>% left_join(first_d, by = "USUBJID") %>%
  transmute(USUBJID, SRCSEQ = PCSEQ,
            NFRLT = (VISITDY - 1) * 24 + PCTPTNUM,
            ARRLT = as.numeric(difftime(tz(PCDTC), DOSE_T, units = "hours")),
            AFRLT = as.numeric(difftime(tz(PCDTC), FIRST_T, units = "hours")))
q4_adpc <- adpc %>% filter(PARAMCD == "SIMDRUG") %>% select(USUBJID, SRCSEQ, NFRLT, ARRLT, AFRLT) %>% as.data.frame()
cmp("Q4", "ADPC relative times", q4_adpc, as.data.frame(q4), c("USUBJID", "SRCSEQ"), c("NFRLT", "ARRLT", "AFRLT"),
    list(NFRLT = 0, ARRLT = 1e-6, AFRLT = 1e-6), "admiral 1.5.0 ad_adpc.R pattern", "base-R difftime() on PCDTC and EXSTDTC")

## --- Q5 ADSL population flags ---------------------------------------------------------------------
dm_s <- read_sdtm("dm"); ae_s <- read_sdtm("ae"); pp_s <- read_sdtm("pp")
dosed <- unique(ex_s$USUBJID[ex_s$EXDOSE > 0])
quant <- unique(pc_s$USUBJID[!is.na(pc_s$PCSTRESN) & pc_s$PCSTRESN > 0 & pc_s$PCTPTNUM > 0])
emes <- ae_s %>% filter(AEDECOD == "Vomiting") %>% mutate(ON = tz(AESTDTC)) %>%
  inner_join(dose_by, by = "USUBJID", relationship = "many-to-many") %>%
  mutate(h = as.numeric(difftime(ON, DOSE_T, units = "hours"))) %>% filter(h >= 0, h <= SAP$exclusion_rules$emesis_window_h) %>%
  distinct(USUBJID, VISITNUM)
pre <- pc_s %>% filter(PCTPTNUM == 0) %>% transmute(USUBJID, VISITNUM, PRE = coalesce(PCSTRESN, 0))
cmx <- pp_s %>% filter(PPTESTCD == "CMAX") %>% transmute(USUBJID, VISITNUM, CMAX = PPSTRESN)
prof_ok <- pp_s %>% filter(PPTESTCD %in% c("CMAX", "AUCLST")) %>% group_by(USUBJID, VISITNUM) %>%
  summarise(ok = sum(!is.na(PPSTRESN)) == 2, .groups = "drop") %>%
  left_join(pre, by = c("USUBJID", "VISITNUM")) %>% left_join(cmx, by = c("USUBJID", "VISITNUM")) %>%
  anti_join(emes, by = c("USUBJID", "VISITNUM")) %>% filter(ok, PRE <= SAP$exclusion_rules$predose_pct_cmax / 100 * CMAX)
q5 <- dm_s %>% transmute(USUBJID,
  SAFFL = ifelse(USUBJID %in% dosed, "Y", "N"),
  PKCFL = ifelse(USUBJID %in% dosed & USUBJID %in% quant, "Y", "N"),
  PKPFL = ifelse(USUBJID %in% prof_ok$USUBJID, "Y", "N"),
  BEFL = ifelse(USUBJID %in% names(which(table(prof_ok$USUBJID) == 2)), "Y", "N"))
cmp("Q5", "ADSL population flags", as.data.frame(adsl[, names(q5)]), as.data.frame(q5), "USUBJID", c("SAFFL", "PKCFL", "PKPFL", "BEFL"),
    list(SAFFL = 0), "admiral ADSL plus 05_adpp.R rules", "base R on DM, EX, PC, AE and PP")

## --- Q6 adverse-event overview counts ---------------------------------------------------------------
ae_on <- ae_s %>% mutate(ON = tz(AESTDTC)) %>% inner_join(dose_by, by = "USUBJID", relationship = "many-to-many") %>%
  filter(DOSE_T <= ON) %>% group_by(USUBJID, AESEQ) %>% slice_max(DOSE_T, n = 1) %>% ungroup() %>%
  left_join(ex_s %>% transmute(USUBJID, VISITNUM, TRT = ifelse(grepl("TEST", EXTRT), "Test", "Reference")), by = c("USUBJID", "VISITNUM"))
q6 <- lapply(c("Test", "Reference"), function(t) {
  a <- ae_on[ae_on$TRT == t, ]
  data.frame(TRT = t, any = length(unique(a$USUBJID)), events = nrow(a),
             related = length(unique(a$USUBJID[a$AEREL == "RELATED"])), severe = length(unique(a$USUBJID[a$AESEV == "SEVERE"])),
             serious = length(unique(a$USUBJID[a$AESER == "Y"])), N = sum(ex_s$EXTRT == paste("SIMDRUG", toupper(t))))
}) %>% bind_rows()
cnt <- function(tt, row, col) as.integer(sub(" .*", "", formatters::matrix_form(tt)$strings[row, col]))
mf <- formatters::matrix_form(TLF$t_14_3_1_1$tt)$strings
rows <- match(c("Participants with at least one TEAE", "Total number of TEAEs", "Participants with a related TEAE",
                "Participants with a severe TEAE", "Participants with a serious TEAE"), trimws(mf[, 1]))
q6_tlf <- lapply(2:3, function(j) data.frame(TRT = c("Test", "Reference")[j - 1],
  any = cnt(TLF$t_14_3_1_1$tt, rows[1], j), events = cnt(TLF$t_14_3_1_1$tt, rows[2], j), related = cnt(TLF$t_14_3_1_1$tt, rows[3], j),
  severe = cnt(TLF$t_14_3_1_1$tt, rows[4], j), serious = cnt(TLF$t_14_3_1_1$tt, rows[5], j),
  N = as.integer(gsub("\\D", "", mf[2, j])))) %>% bind_rows()
cmp("Q6", "Table 14.3.1.1 displayed counts", q6_tlf, q6, "TRT", c("N", "any", "events", "related", "severe", "serious"),
    list(N = 0), "rtables/tern table cells", "base-R count on AE and EX")

## --- Q7 control: the comparison must catch a planted difference ---------------------------------------
planted <- pk_w; i <- which(planted$USUBJID == "SIMBE01-101-005" & planted$APERIOD == 1)
planted$AUCLST[i] <- planted$AUCLST[i] * 1.001
before <- length(ledger)
cmp("Q7", "Control: planted 0.1% change in one AUC(0-t)", pk_w, planted, c("USUBJID", "APERIOD"), "AUCLST", list(AUCLST = 1e-6),
    "PKNCA results", "the same results with one value changed")
ledger[[length(ledger)]]$status <- ifelse(ledger[[length(ledger)]]$mismatches == 1, "pass", "fail")   # expected: exactly one
ledger[[length(ledger)]]$item <- "Control: planted 0.1% change in one AUC(0-t); pass = exactly 1 mismatch found"

## --- write the ledger ------------------------------------------------------------------------------
qc_ledger <- do.call(rbind, ledger)
n_pass <- sum(qc_ledger$status == "pass"); n_fail <- sum(qc_ledger$status == "fail")
write_csv_det(qc_ledger, sp("05_qc", "qc_ledger.csv"))
write_json_det(list(label = "Same-author re-derivation by a second method; not independent double programming",
                    tool = paste("diffdf", packageVersion("diffdf")), checks = nrow(qc_ledger), pass = n_pass, fail = n_fail,
                    values_compared = sum(qc_ledger$n_compared), ledger = round_df(qc_ledger)),
               sp("05_qc", "qc_ledger.json"))

show <- qc_ledger %>% transmute(ID = id, Item = item, Variable = variable, `Primary route` = primary, `QC route` = qc,
                                Compared = n_compared, Tolerance = ifelse(tolerance == 0, "exact", format(tolerance, scientific = TRUE)),
                                Mismatches = mismatches, `Max abs diff` = ifelse(is.na(max_abs_diff), "", ifelse(max_abs_diff == 0, "0", formatC(max_abs_diff, format = "e", digits = 1))),
                                Status = status)
body <- paste0(
  '<div class="note"><p><strong>Same-author re-derivation, not independent double programming.</strong> One person wrote the primary programs and these checks from the same SAP. The checks re-derive each result by a different method and compare with <code>diffdf</code> at the tolerances shown. They can catch coding slips and engine defaults; they cannot catch a misreading of the SAP that both routes share.</p></div>',
  '<ul class="kv">',
  sprintf('<li><span class="k">Checks</span><span class="v">%d</span></li>', nrow(qc_ledger)),
  sprintf('<li><span class="k">Pass</span><span class="v">%d</span></li>', n_pass),
  sprintf('<li><span class="k">Fail</span><span class="v">%d</span></li>', n_fail),
  sprintf('<li><span class="k">Values compared</span><span class="v">%d</span></li>', sum(qc_ledger$n_compared)), '</ul>',
  html_table(show, caption = "Executed QC ledger. Tolerances are absolute, in the units of each variable; 'exact' means identical values."),
  md(
    "### How to read it",
    "",
    "- **Q1** runs a second NCA engine (NonCompart) on the same ADPC input with the same settings: linear-up/log-down AUC, BLQ as zero, at least 3 terminal points after tmax chosen by adjusted R-squared.",
    "- **Q2** is the closed-form crossover analysis: half the within-participant period difference, compared between sequences with a two-sample t-test. For complete 2x2 data it gives the same estimate, interval and residual variance as the GLM.",
    "- **Q3** refits the model with a random participant effect (`nlme::lme`, REML, tight convergence settings). With every participant contributing both periods it reproduces the GLM's estimate, interval and residual variance; the 1e-6 tolerance allows for the iterative fit. With the default settings the CV agreed only to about 5e-6 percentage points, so the settings were tightened rather than the tolerance widened.",
    "- **Q4** checks the admiral-derived times, including `derive_var_nfrlt()`, which admiral 1.5.0 labels experimental.",
    "- **Q5** and **Q6** rebuild the population flags and the adverse-event counts from the SDTM-like domains without admiral or tern.",
    "- **Q7** is a control: a 0.1% change planted in one value must be found exactly once, which shows the comparison can fail.",
    "",
    "Files: [qc_ledger.csv](qc_ledger.csv), [qc_ledger.json](qc_ledger.json), [qc_nca_side_by_side.csv](qc_nca_side_by_side.csv) (PKNCA and NonCompart values for every profile). Program: `study/05_qc/qc.R`.",
    "",
    "### What the QC found while this example was built",
    "",
    "The first full run had 6 failures out of 37, all now resolved; the fixes are in the code, not in the tolerances:",
    "",
    "- TLST, LAMZLL and LAMZUL differed by about 3e-9 h because ADPC was rounded to 10 significant digits after PKNCA had already run on the unrounded times. ADPC is now rounded when it is built, so both engines and the XPT file see the same times.",
    "- The degrees of freedom were stored as integer in one route and as double in the other; the comparison now uses values, not storage types.",
    "- With nlme's default convergence settings the REML residual variance matched the GLM only to about 5e-6 percentage points of CV; the refit now uses tight convergence settings and meets the pre-set 1e-6 tolerance.",
    "",
    "### Not covered",
    "",
    "- No second programmer, no blinded re-implementation from the specification alone.",
    "- The SDTM-like inputs are simulated by the same code base; there is no check against source documents or an EDC export.",
    "- No Pinnacle 21 or CDISC CORE conformance run; the metadata checks in stage 3 are metatools and xportr checks against this study's own specification."))
write_text(page_html(title = "QC Ledger", kicker = "Stage 5: QC and validation", h1 = "Executed QC ledger: re-derivation by a second method",
                     description = "Executed QC ledger for a synthetic BE study: NonCompart vs PKNCA, two refits of the BE model, and base-R re-derivations, compared with diffdf.",
                     labels = paste0(lab("sup", "Supported (job): reviewed outputs"), lab("tools", "Executed here: same-author re-derivation")),
                     body = body, depth = 1), sp("05_qc", "qc_ledger.html"))
cat(sprintf("[05_qc] %d checks: %d pass, %d fail (%d values compared)\n", nrow(qc_ledger), n_pass, n_fail, sum(qc_ledger$n_compared)))
