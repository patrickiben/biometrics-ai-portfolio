#!/usr/bin/env Rscript
################################################################################
# carryover_oc/R/tables.R: tables T1 to T5, figures F1 to F3 (base R PNG, light and dark),
# and the generated blocks of index.html, from the files in out/. SYNTHETIC DATA ONLY.
#
#   Rscript sim_lifecycle/carryover_oc/R/tables.R    (after R/run_oc.R and tests/test_carryover.R)
#
# Every number on the page between <!--oc:NAME--> and <!--/oc:NAME--> markers is written
# here from out/*.csv; the prose around the markers is hand-written.
# Page tables and figures use the base configuration (no assay error, sampling to 72 h) and
# AUC(0-t); every other configuration, disposition and endpoint is in out/oc_results.csv.
################################################################################
args <- commandArgs(trailingOnly = FALSE)
me <- sub("^--file=", "", args[grep("^--file=", args)])
mod <- if (length(me)) dirname(dirname(normalizePath(me))) else normalizePath("sim_lifecycle/carryover_oc")
setwd(dirname(dirname(mod)))
source(file.path(mod, "R", "analyze.R"))                       # OC_ARMS, OC_WASHOUTS, write_oc_csv
out_dir <- file.path(mod, "out"); tab_dir <- file.path(out_dir, "tables"); fig_dir <- file.path(out_dir, "figures")
dir.create(tab_dir, showWarnings = FALSE); dir.create(fig_dir, showWarnings = FALSE)

res <- read.csv(file.path(out_dir, "oc_results.csv"), stringsAsFactors = FALSE)
dec <- read.csv(file.path(out_dir, "oc_bias_decomposition.csv"), stringsAsFactors = FALSE)
kac <- read.csv(file.path(out_dir, "known_answer_checks.csv"), stringsAsFactors = FALSE)
info <- read.csv(file.path(out_dir, "run_info.csv"), stringsAsFactors = FALSE)
iv <- function(item) info$value[info$item == item]
Wn <- as.character(OC_WASHOUTS); Wcols <- c(Wn, "adequate")
Whead <- c(paste0(Wn, "&times;"), "KA1")
arms <- names(OC_ARMS)

sel <- function(cfg = "base", disp = "mono", theta, ep = "AUC", arm = NULL, d = res) {
  x <- d[d$config == cfg & d$disposition == disp & abs(d$theta - theta) < 1e-9 & d$endpoint == ep, ]
  if (!is.null(arm)) x <- x[x$arm %in% arm, ]
  x
}
f_bias <- function(b, m) ifelse(is.na(b), "n/e", ifelse(abs(b) < 1e-4 & b != 0, sprintf("%.1e (%.1e)", b, m), sprintf("%.4f (%.4f)", b, m)))
f_rate <- function(p, m) ifelse(is.na(p), "n/e", sprintf("%.3f (%.3f)", p, m))
## a share with its MCSE, blank when the total it divides is within 2 MCSE of 0
f_share <- function(s, m, tot, tot_m) ifelse(is.na(s) | is.na(tot) | abs(tot) < 2 * tot_m, "", sprintf("%.0f%% (%.0f%%)", 100 * s, 100 * m))
pct <- function(s, m) sprintf("%.0f%% (MCSE %.0f%%)", 100 * s, 100 * m)
pct_s <- function(s, m) sprintf("%.0f%% (%.0f%%)", 100 * s, 100 * m)
## Qualitative claims in the page prose are checked against the numbers here; if a re-run changes
## them, tables.R stops instead of writing prose the data no longer support.
claim <- function(ok, what) if (!isTRUE(ok)) stop("page claim no longer supported by out/*.csv: ", what, call. = FALSE)
## which part of the rule's bias is larger, judged at 2 MCSE
part_word <- function(s, m) if (s - 0.5 > 2 * m) "selection is the larger part" else if (0.5 - s > 2 * m) "the retained residual is the larger part" else "the two parts are comparable"

esc <- function(s) { s <- gsub("&(?!times;|plusmn;|minus;)", "&amp;", s, perl = TRUE); s <- gsub("<", "&lt;", s); gsub(">", "&gt;", s) }

## grid of formatted cells: rows = arms, columns = washouts
grid_table <- function(x, value, mcse, f, rows = arms, label = OC_ARMS) {
  m <- t(vapply(rows, function(a) vapply(Wcols, function(w) {
    r <- x[x$arm == a & x$washout == w, ]
    if (!nrow(r)) "" else f(r[[value]], r[[mcse]]) }, ""), rep("", length(Wcols))))
  data.frame(Arm = paste0(rows, ": ", label[rows]), m, check.names = FALSE, stringsAsFactors = FALSE)
}
## The caption is a paragraph above the scroll box (linked by aria-labelledby), so that on a
## phone it wraps to the screen instead of scrolling with a wide table.
CAP_N <- 0L
html_table <- function(df, caption, head = names(df), cls = "oc") {
  CAP_N <<- CAP_N + 1L; id <- sprintf("cap-t%02d", CAP_N)
  h <- paste0("<p class=\"tcap\" id=\"", id, "\">", caption, "</p>\n<div class=\"tbl\"><table class=\"", cls,
              "\" aria-labelledby=\"", id, "\">\n<thead><tr>",
              paste0("<th scope=\"col\">", head, "</th>", collapse = ""), "</tr></thead>\n<tbody>\n")
  for (i in seq_len(nrow(df))) {
    cells <- vapply(df[i, ], function(v) esc(as.character(v)), "")
    h <- paste0(h, "<tr><th scope=\"row\">", cells[1], "</th>", paste0("<td>", cells[-1], "</td>", collapse = ""), "</tr>\n")
  }
  paste0(h, "</tbody></table></div>")
}
write_tab <- function(df, name) write.csv(df, file.path(tab_dir, name), row.names = FALSE)
Wnote <- "Columns: washout as a multiple of the mean half-life (24 h); KA1 = 10 times the largest individual half-life in each replicate. Cells: estimate (MCSE). n/e: no evaluable study."
blocks <- list()

## ---- T1 bias of log GMR-hat --------------------------------------------------------------
t1 <- list()
for (th in c(1.25, 0.80)) {
  x <- sel(theta = th)
  g <- grid_table(x, "bias", "bias_mcse", f_bias)
  cf <- vapply(Wcols, function(w) sprintf("%.4f", x$closed_form_bias[x$arm == "A1" & x$washout == w]), "")
  g <- rbind(g, data.frame(Arm = "Closed form, naive (no within-participant noise)", t(cf), check.names = FALSE))
  t1[[as.character(th)]] <- cbind(theta = th, g)
  blocks[[paste0("t1_", sub("\\.", "", th))]] <- html_table(g, sprintf(
    "T1%s. Bias of log GMR-hat, AUC(0-t), true GMR %.2f. %s", if (th > 1) "a" else "b", th, Wnote), c("Arm", Whead))
}
write_tab(do.call(rbind, t1), "t1_bias.csv")
gc <- grid_table(sel(theta = 1.25), "ci_coverage", "ci_coverage_mcse", f_rate)
write_tab(cbind(theta = 1.25, gc), "t1_ci_coverage.csv")
blocks$t1_cov <- html_table(gc, paste("T1c. Coverage of the 90% CI for the log GMR, AUC(0-t), true GMR 1.25 (studies evaluable in that arm).", Wnote), c("Arm", Whead))

## ---- T2 rates of concluding BE -------------------------------------------------------------
t2 <- list(); lab <- c("1.25" = "consumer risk", "0.8" = "consumer risk", "0.95" = "power", "1" = "power")
for (th in c(1.25, 0.80, 0.95, 1.00)) {
  x <- sel(theta = th); g <- grid_table(x, "be_rate", "be_rate_mcse", f_rate)
  t2[[as.character(th)]] <- cbind(theta = th, g)
  blocks[[paste0("t2_", sub("\\.", "", th))]] <- html_table(g, sprintf(
    "T2. Rate of concluding BE on AUC(0-t), true GMR %.2f (%s). Studies that are not evaluable count as not concluding BE. %s",
    th, lab[[as.character(th)]], Wnote), c("Arm", Whead))
}
write_tab(do.call(rbind, t2), "t2_be_rates.csv")
## sensitivity: other dispositions and configurations, consumer risk at theta = 1.25
sens <- list()
for (cd in list(c("base", "biexp"), c("assay", "mono"), c("assay", "biexp"), c("extended", "mono"), c("extended", "biexp"))) {
  x <- sel(cd[1], cd[2], 1.25)
  g <- grid_table(x, "be_rate", "be_rate_mcse", f_rate, rows = c("A0", "A1", "A2", "A3"))
  g$Arm <- paste0(c(base = "Base", assay = "Assay error", extended = "Sampling to 120 h")[[cd[1]]], ", ",
                  c(mono = "monoexponential", biexp = "biexponential")[[cd[2]]], "; ", g$Arm)
  sens[[length(sens) + 1]] <- g
}
sens <- do.call(rbind, sens)
write_tab(sens, "t2_sensitivity_consumer_risk.csv")
blocks$t2_sens <- html_table(sens, paste("T2c. Consumer risk on AUC(0-t) at a true GMR of 1.25 under the biexponential disposition, 8% assay error with an LLOQ of 0.5% of the median Cmax, and sampling extended to 120 h.", Wnote), c("Configuration; arm", Whead))
## Cmax and the joint decision versus AUC(0-t), over the whole grid
jj <- merge(res[res$endpoint == "AUC", c("config", "theta", "disposition", "washout", "arm", "be_rate")],
            res[res$endpoint == "AUC_CMAX", c("config", "theta", "disposition", "washout", "arm", "be_rate")],
            by = c("config", "theta", "disposition", "washout", "arm"))
jc <- merge(res[res$endpoint == "AUC", c("config", "theta", "disposition", "washout", "arm", "be_rate")],
            res[res$endpoint == "CMAX", c("config", "theta", "disposition", "washout", "arm", "be_rate")],
            by = c("config", "theta", "disposition", "washout", "arm"))
bm <- function(d) d$config == "base" & d$disposition == "mono"
max_joint <- max(abs(jj$be_rate.x - jj$be_rate.y)[bm(jj)]); max_cmax <- max(abs(jc$be_rate.x - jc$be_rate.y)[bm(jc)])
na_gap <- max(abs(jj$be_rate.x - jj$be_rate.y)[jj$config != "assay"], abs(jc$be_rate.x - jc$be_rate.y)[jc$config != "assay"])
ja <- jj[jj$config == "assay", ]; ja_gap <- max(ja$be_rate.x - ja$be_rate.y); jw <- ja[which.max(ja$be_rate.x - ja$be_rate.y), ]

## ---- T3 exclusion and non-evaluable rates ----------------------------------------------------
t3 <- list()
for (th in c(1.25, 1.00, 0.80)) {
  x <- sel(theta = th, arm = "A2")
  row <- function(lbl, v, m) data.frame(Quantity = sprintf("GMR %.2f: %s", th, lbl), t(vapply(Wcols, function(w)
    f_rate(x[[v]][x$washout == w], x[[m]][x$washout == w]), "")), check.names = FALSE)
  t3[[length(t3) + 1]] <- rbind(row("participants excluded", "excl_frac", "excl_frac_mcse"),
                                row("excluded, sequence TR", "excl_frac_tr", "excl_frac_tr_mcse"),
                                row("excluded, sequence RT", "excl_frac_rt", "excl_frac_rt_mcse"),
                                row("studies not evaluable", "noneval_rate", "noneval_rate_mcse"))
}
t3 <- do.call(rbind, t3); write_tab(t3, "t3_exclusion.csv")
blocks$t3 <- html_table(t3, paste("T3. M13A pre-dose rule: share of participants excluded (overall and by sequence) and share of studies not evaluable (fewer than 12 participants or an empty sequence).", Wnote), c("Quantity", Whead))

## ---- T4 the AUC coverage condition --------------------------------------------------------------
t4 <- list()
for (cf in c("base", "extended")) for (a in c("A0", "A1", "A2")) {
  x <- sel(cf, "mono", 1.25, arm = a)
  lbl <- sprintf("%s; %s", c(base = "Sampling to 72 h", extended = "Sampling to 120 h")[[cf]], paste0(a, ": ", OC_ARMS[[a]]))
  t4[[length(t4) + 1]] <- data.frame(Profiles = paste0(lbl, ", profiles below 80%"), t(vapply(Wcols, function(w)
    f_rate(x$auc_cov_below80[x$washout == w], x$auc_cov_below80_mcse[x$washout == w]), "")), check.names = FALSE)
  t4[[length(t4) + 1]] <- data.frame(Profiles = paste0(lbl, ", studies over the 20% trigger"), t(vapply(Wcols, function(w)
    f_rate(x$auc_cov_trigger[x$washout == w], x$auc_cov_trigger_mcse[x$washout == w]), "")), check.names = FALSE)
}
t4 <- do.call(rbind, t4); write_tab(t4, "t4_auc_coverage.csv")
blocks$t4 <- html_table(t4, paste("T4. M13A coverage condition AUC(0-t) / AUC(0-inf) &ge; 0.80 at a true GMR of 1.25: mean share of analyzed profiles below 0.80, and share of studies in which more than 20% of profiles fall below it (M13A then asks for a discussion of validity).", Wnote), c("Sampling; arm; quantity", Whead))
blocks$t4 <- gsub("&amp;ge;", "&ge;", blocks$t4, fixed = TRUE)

## ---- T5 decomposition of the rule's bias ---------------------------------------------------------
t5 <- list()
for (th in c(1.25, 0.80)) {
  x <- dec[dec$config == "base" & dec$disposition == "mono" & abs(dec$theta - th) < 1e-9 & dec$endpoint == "AUC", ]
  x <- x[match(Wcols, x$washout), ]
  t5[[length(t5) + 1]] <- data.frame(
    Washout = ifelse(x$washout == "adequate", sprintf("GMR %.2f, KA1", th), sprintf("GMR %.2f, %s&times;", th, x$washout)),
    `Evaluable studies` = x$n_eval,
    `Total, A2 - A0` = f_bias(x$bias_total, x$bias_total_mcse),
    `Retained residual, A2 - A2s` = f_bias(x$bias_retained, x$bias_retained_mcse),
    `Selection, A2s - A0` = f_bias(x$bias_selection, x$bias_selection_mcse),
    `Selection share` = f_share(x$selection_share, x$selection_share_mcse, x$bias_total, x$bias_total_mcse),
    `BE rate, A2 - A0` = f_rate(x$rate_total, x$rate_total_mcse),
    `BE rate, selection` = f_rate(x$rate_selection, x$rate_selection_mcse),
    `Bias, A2 - A1` = f_bias(x$bias_vs_naive, x$bias_vs_naive_mcse),
    `BE rate, A2 - A1` = f_rate(x$rate_vs_naive, x$rate_vs_naive_mcse),
    check.names = FALSE, stringsAsFactors = FALSE)
}
t5 <- do.call(rbind, t5); write_tab(t5, "t5_decomposition.csv")
blocks$t5 <- html_table(t5, "T5. The M13A arm's bias split into retained residual (A2 - A2s) and selection (A2s - A0), and the rule against including everyone (A2 - A1), paired within study, AUC(0-t). Bias terms use studies evaluable under the rule; BE-rate terms use all studies. Cells: estimate (MCSE). Selection share: (A2s - A0) / (A2 - A0), with its delta-method MCSE; left blank when the total is within 2 MCSE of 0.",
                        c("Washout", "Evaluable studies", "Total, A2 &minus; A0", "Retained residual, A2 &minus; A2s", "Selection, A2s &minus; A0", "Selection share", "BE rate, A2 &minus; A0", "BE rate, selection", "Bias, A2 &minus; A1", "BE rate, A2 &minus; A1"))

## ---- known-answer pass table -------------------------------------------------------------------
blocks$checks <- html_table(data.frame(Test = kac$test, Check = kac$check, Criterion = kac$criterion,
                                       Observed = kac$observed, Result = kac$result, stringsAsFactors = FALSE),
  sprintf("Known-answer checks and controls, written by tests/test_carryover.R (%d PASS, %d FAIL, %d INFO). INFO rows compare against the unvalidated pilot and are reported, not enforced.",
          sum(kac$result == "PASS"), sum(kac$result == "FAIL"), sum(kac$result == "INFO")), cls = "oc checks")
blocks$checks <- gsub("<td>PASS</td>", "<td class=\"ok\">PASS</td>", blocks$checks, fixed = TRUE)
blocks$checks <- gsub("<td>FAIL</td>", "<td class=\"bad\">FAIL</td>", blocks$checks, fixed = TRUE)

## ---- generated findings and run facts -----------------------------------------------------------
g <- function(th, arm, w, col, ep = "AUC", cfg = "base", disp = "mono") { x <- sel(cfg, disp, th, ep, arm); x[[col]][x$washout == w] }
dW <- function(th, w) { x <- dec[dec$config == "base" & dec$disposition == "mono" & abs(dec$theta - th) < 1e-9 & dec$endpoint == "AUC" & dec$washout == w, ]; x }
d5 <- dW(1.25, "5"); d6 <- dW(1.25, "6"); d8 <- dW(1.25, "8"); d10 <- dW(1.25, "10")
claim(part_word(d5$selection_share, d5$selection_share_mcse) == "selection is the larger part" &&
      part_word(d6$selection_share, d6$selection_share_mcse) == "selection is the larger part", "selection is most of the rule's bias at 5 and 6 half-lives (GMR 1.25)")
bm_a3 <- res[res$config == "base" & res$disposition == "mono" & res$endpoint %in% c("AUC", "CMAX") & res$arm %in% c("A3", "A3o"), ]
a3_max <- max(bm_a3$max_abs_diff_a0[bm_a3$arm == "A3"], na.rm = TRUE); a3o_max <- max(bm_a3$max_abs_diff_a0[bm_a3$arm == "A3o"], na.rm = TRUE)
claim(a3_max < 1e-8 && a3o_max < 1e-10 && all(bm_a3$be_disagree_a0 == 0), "subtraction matches the oracle in the base grid (monoexponential)")
blocks$findings <- paste0("<ul>\n",
  sprintf("<li><strong>Naive analysis.</strong> At a true GMR of 1.25 the consumer risk of including everyone is %.3f (MCSE %.3f) at 2 mean half-lives, %.3f (%.3f) at 3, %.3f (%.3f) at 5 and %.3f (%.3f) at 10, against %.3f (%.3f) with no residual. The bias is toward 1, as the closed form predicts.</li>\n",
          g(1.25, "A1", "2", "be_rate"), g(1.25, "A1", "2", "be_rate_mcse"), g(1.25, "A1", "3", "be_rate"), g(1.25, "A1", "3", "be_rate_mcse"),
          g(1.25, "A1", "5", "be_rate"), g(1.25, "A1", "5", "be_rate_mcse"), g(1.25, "A1", "10", "be_rate"), g(1.25, "A1", "10", "be_rate_mcse"),
          g(1.25, "A0", "5", "be_rate"), g(1.25, "A0", "5", "be_rate_mcse")),
  sprintf("<li><strong>Interval coverage.</strong> With no residual the 90%% CI covers the true GMR in %.3f (MCSE %.3f) of studies. Including everyone, coverage falls to %.3f (%.3f) at 2 mean half-lives and %.3f (%.3f) at 3; under the M13A rule it is %.3f (%.3f) at 4 half-lives and %.3f (%.3f) at 5.</li>\n",
          g(1.25, "A0", "5", "ci_coverage"), g(1.25, "A0", "5", "ci_coverage_mcse"), g(1.25, "A1", "2", "ci_coverage"), g(1.25, "A1", "2", "ci_coverage_mcse"),
          g(1.25, "A1", "3", "ci_coverage"), g(1.25, "A1", "3", "ci_coverage_mcse"), g(1.25, "A2", "4", "ci_coverage"), g(1.25, "A2", "4", "ci_coverage_mcse"),
          g(1.25, "A2", "5", "ci_coverage"), g(1.25, "A2", "5", "ci_coverage_mcse")),
  sprintf("<li><strong>M13A rule, short washouts.</strong> At 2 and 3 mean half-lives the rule excludes %.0f%% and %.0f%% of participants and no study is evaluable, so consumer risk is 0 and so is power. At 4 half-lives %.0f%% of studies are not evaluable and power at a true GMR of 0.95 is %.3f (MCSE %.3f), against %.3f (%.3f) with no residual.</li>\n",
          100 * g(1.25, "A2", "2", "excl_frac"), 100 * g(1.25, "A2", "3", "excl_frac"), 100 * g(0.95, "A2", "4", "noneval_rate"),
          g(0.95, "A2", "4", "be_rate"), g(0.95, "A2", "4", "be_rate_mcse"), g(0.95, "A0", "4", "be_rate"), g(0.95, "A0", "4", "be_rate_mcse")),
  sprintf("<li><strong>M13A rule, borderline washouts.</strong> At 5 mean half-lives the rule drops %.0f%% of participants (%.0f%% in sequence TR, %.0f%% in RT at a true GMR of 1.25) and brings consumer risk to %.3f (MCSE %.3f); power at 0.95 falls to %.3f (%.3f). At 6 half-lives it drops %.0f%% and consumer risk is %.3f (%.3f), close to the naive %.3f (%.3f).</li>\n",
          100 * g(1.25, "A2", "5", "excl_frac"), 100 * g(1.25, "A2", "5", "excl_frac_tr"), 100 * g(1.25, "A2", "5", "excl_frac_rt"),
          g(1.25, "A2", "5", "be_rate"), g(1.25, "A2", "5", "be_rate_mcse"), g(0.95, "A2", "5", "be_rate"), g(0.95, "A2", "5", "be_rate_mcse"),
          100 * g(1.25, "A2", "6", "excl_frac"), g(1.25, "A2", "6", "be_rate"), g(1.25, "A2", "6", "be_rate_mcse"),
          g(1.25, "A1", "6", "be_rate"), g(1.25, "A1", "6", "be_rate_mcse")),
  sprintf("<li><strong>Where the rule's bias comes from.</strong> At a true GMR of 1.25 the M13A arm's bias is %.4f (MCSE %.4f) at 5 half-lives; selection contributes %.4f (%.4f) and retained residual %.4f (%.4f). Selection is %s of the total at 5 half-lives and %s at 6; at 8 it is %s, where %s, and at 10 it is %s, where %s (delta-method MCSEs).</li>\n",
          d5$bias_total, d5$bias_total_mcse, d5$bias_selection, d5$bias_selection_mcse, d5$bias_retained, d5$bias_retained_mcse,
          pct(d5$selection_share, d5$selection_share_mcse), pct_s(d6$selection_share, d6$selection_share_mcse),
          pct_s(d8$selection_share, d8$selection_share_mcse), part_word(d8$selection_share, d8$selection_share_mcse),
          pct_s(d10$selection_share, d10$selection_share_mcse), part_word(d10$selection_share, d10$selection_share_mcse)),
  sprintf("<li><strong>Subtraction (sensitivity analysis).</strong> With a monoexponential residual and no assay error, subtracting the extrapolated pre-dose concentration matches the oracle almost exactly, because the model it extrapolates is the model that generated the data: over the base grid the largest per-study difference in log GMR-hat from the oracle is %s (&lambda;<sub>z</sub> is fitted to period-1 points that still carry a trace of absorption; %s with the true k), and every study reaches the oracle's BE decision. Under the biexponential disposition its consumer risk at 3 half-lives is %.3f (MCSE %.3f) against %.3f (%.3f) with no residual; with 8%% assay error and an LLOQ it is %.3f (%.3f) against %.3f (%.3f).</li>\n",
          sprintf("%.1e", a3_max), sprintf("%.1e", a3o_max),
          g(1.25, "A3", "3", "be_rate", disp = "biexp"), g(1.25, "A3", "3", "be_rate_mcse", disp = "biexp"),
          g(1.25, "A0", "3", "be_rate", disp = "biexp"), g(1.25, "A0", "3", "be_rate_mcse", disp = "biexp"),
          g(1.25, "A3", "3", "be_rate", cfg = "assay"), g(1.25, "A3", "3", "be_rate_mcse", cfg = "assay"),
          g(1.25, "A0", "3", "be_rate", cfg = "assay"), g(1.25, "A0", "3", "be_rate_mcse", cfg = "assay")),
  sprintf("<li><strong>Sampling.</strong> With sampling to 72 h and a mean half-life of 24 h, %.0f%% of profiles have AUC(0-t) below 80%% of AUC(0-inf), and %.0f%% of studies cross the M13A 20%% trigger even with no residual. Sampling to 120 h brings these to %.1f%% and %.1f%%.</li>\n",
          100 * g(1.25, "A0", "5", "auc_cov_below80"), 100 * g(1.25, "A0", "5", "auc_cov_trigger"),
          100 * g(1.25, "A0", "5", "auc_cov_below80", cfg = "extended"), 100 * g(1.25, "A0", "5", "auc_cov_trigger", cfg = "extended")),
  sprintf("<li><strong>Endpoints.</strong> Without assay error, Cmax and the joint decision (AUC(0-t) and Cmax both within the limits) give the same picture as AUC(0-t): their BE rates differ from it by at most %.4f and %.4f in the base configuration with the monoexponential disposition, and by at most %.3f anywhere without assay error, because within-participant variation then largely scales each profile as a whole. With 8%% assay error each sample has its own error and the endpoints separate: the joint rate is up to %.3f lower than the AUC(0-t) rate (%s arm, %s mean half-lives, true GMR %.2f, %s disposition).</li>\n",
          max_cmax, max_joint, na_gap, ja_gap, jw$arm, jw$washout, jw$theta, c(mono = "monoexponential", biexp = "biexponential")[[jw$disposition]]),
  "</ul>")
## ---- "What this shows" bullets that carry numbers (paired within study, base, mono, AUC(0-t)) ----
## added(): how much the rule adds to the size of the naive bias, (A2 - A1) signed by the
## direction of the naive bias; negative means the rule removes part of it.
nv_sign <- function(th) sign(g(th, "A1", "5", "bias"))
added <- function(th, w) { x <- dW(th, w); c(est = nv_sign(th) * x$bias_vs_naive, mcse = x$bias_vs_naive_mcse) }
z <- function(v) v[["est"]] / v[["mcse"]]
a5 <- lapply(c(hi = 1.25, lo = 0.80), added, w = "5"); a6 <- lapply(c(hi = 1.25, lo = 0.80), added, w = "6")
a8 <- lapply(c(hi = 1.25, lo = 0.80), added, w = "8"); a10 <- lapply(c(hi = 1.25, lo = 0.80), added, w = "10")
e5 <- lapply(c(hi = 1.25, lo = 0.80), dW, w = "5"); e6 <- lapply(c(hi = 1.25, lo = 0.80), dW, w = "6"); e8 <- dW(0.80, "8")
claim(all(vapply(a5, z, 0) < -2) && all(vapply(e5, function(x) x$rate_vs_naive / x$rate_vs_naive_mcse, 0) < -2) &&
      all(vapply(e5, function(x) abs(x$bias_total / x$bias_total_mcse), 0) > 2), "at 5 half-lives the rule removes part, not all, of the naive bias and lowers consumer risk")
claim(all(abs(vapply(a6, z, 0)) < 2) && all(abs(vapply(e6, function(x) x$rate_vs_naive / x$rate_vs_naive_mcse, 0)) < 2) &&
      all(vapply(e6, function(x) x$rate_total, 0) > 0), "at 6 half-lives no detectable gain over the naive analysis; consumer risk above the oracle's")
claim(z(a8$lo) > 2 && z(a10$lo) > 2 && abs(z(a8$hi)) < 2 && abs(z(a10$hi)) < 2, "at 8 and 10 half-lives the rule's bias exceeds the naive bias at GMR 0.80 only")
f4 <- function(v) sprintf("%+.4f (%.4f)", v[["est"]], v[["mcse"]])
a4 <- function(v, lab = "") sprintf("%.4f (%s%.4f)", abs(v[["est"]]), lab, v[["mcse"]])
a3r <- function(e, m, lab = "") sprintf("%.3f (%s%.3f)", abs(e), lab, m)
f3 <- function(e, m) sprintf("%+.3f (%.3f)", e, m)
blocks$shows_rule <- paste0(
  sprintf("<li>At 5 mean half-lives the rule removes part of the naive bias, not all of it. Paired with including everyone in the same studies, it reduces the size of the bias by %s at a true GMR of 1.25 and %s at 0.80, and lowers consumer risk by %s and %s; its consumer risk is %.3f (MCSE %.3f) and %.3f (%.3f), against %.3f and %.3f for the oracle.</li>\n",
          a4(a5$hi, "MCSE "), a4(a5$lo), a3r(e5$hi$rate_vs_naive, e5$hi$rate_vs_naive_mcse), a3r(e5$lo$rate_vs_naive, e5$lo$rate_vs_naive_mcse),
          g(1.25, "A2", "5", "be_rate"), g(1.25, "A2", "5", "be_rate_mcse"), g(0.80, "A2", "5", "be_rate"), g(0.80, "A2", "5", "be_rate_mcse"),
          g(1.25, "A0", "5", "be_rate"), g(0.80, "A0", "5", "be_rate")),
  sprintf("<li>At 6 half-lives the rule drops %.0f%% of participants with no detectable gain over including everyone: the paired changes in the size of the bias are %s and %s, and in consumer risk %s and %s (true GMR 1.25 and 0.80). Paired with the oracle in the same studies, its consumer risk is higher by %s and %s.</li>\n",
          100 * g(1.25, "A2", "6", "excl_frac"), f4(a6$hi), f4(a6$lo), f3(e6$hi$rate_vs_naive, e6$hi$rate_vs_naive_mcse), f3(e6$lo$rate_vs_naive, e6$lo$rate_vs_naive_mcse),
          a3r(e6$hi$rate_total, e6$hi$rate_total_mcse, "MCSE "), a3r(e6$lo$rate_total, e6$lo$rate_total_mcse)),
  sprintf("<li>At 8 and 10 half-lives, where the rule drops %.0f%% and %.1f%% of participants, its selection makes its bias slightly larger than the naive analysis's at a true GMR of 0.80: by %s and %s, with consumer risk %.4f (MCSE %.4f) against the naive %.4f (%.4f) at 8 half-lives, a paired difference of %s. At 1.25 the same differences, %s and %s, are not distinguishable from 0.</li>",
          100 * g(0.80, "A2", "8", "excl_frac"), 100 * g(0.80, "A2", "10", "excl_frac"), a4(a8$lo, "MCSE "), a4(a10$lo),
          g(0.80, "A2", "8", "be_rate"), g(0.80, "A2", "8", "be_rate_mcse"), g(0.80, "A1", "8", "be_rate"), g(0.80, "A1", "8", "be_rate_mcse"),
          f3(e8$rate_vs_naive, e8$rate_vs_naive_mcse), f4(a8$hi), f4(a10$hi)))
sh <- lapply(list(c(1.25, 5), c(1.25, 6), c(0.80, 5), c(0.80, 6)), function(v) dW(v[1], as.character(v[2])))
claim(all(vapply(sh, function(x) part_word(x$selection_share, x$selection_share_mcse) == "selection is the larger part", TRUE)) &&
      g(1.25, "A2", "5", "excl_frac_tr") > g(1.25, "A2", "5", "excl_frac_rt") && g(0.80, "A2", "5", "excl_frac_rt") > g(0.80, "A2", "5", "excl_frac_tr"),
      "selection is the larger part at 5 and 6 half-lives at both GMRs, and the rule excludes more from the lower-exposure period-2 sequence")
blocks$shows_sel <- sprintf("<li>Most of the bias left after the rule at 5 to 6 half-lives comes from the selection the rule makes, not from residual left in the retained participants: selection is %s and %s of it at 5 and 6 half-lives at a true GMR of 1.25, and %s and %s at 0.80. The rule conditions on the outcome: its denominator is the period's own Cmax, so it excludes more participants from the sequence whose period-2 product gives lower exposure (at 5 half-lives, %.0f%% of TR and %.0f%% of RT at a true GMR of 1.25, and %.0f%% and %.0f%% at 0.80).</li>",
  pct(sh[[1]]$selection_share, sh[[1]]$selection_share_mcse), pct_s(sh[[2]]$selection_share, sh[[2]]$selection_share_mcse),
  pct_s(sh[[3]]$selection_share, sh[[3]]$selection_share_mcse), pct_s(sh[[4]]$selection_share, sh[[4]]$selection_share_mcse),
  100 * g(1.25, "A2", "5", "excl_frac_tr"), 100 * g(1.25, "A2", "5", "excl_frac_rt"), 100 * g(0.80, "A2", "5", "excl_frac_tr"), 100 * g(0.80, "A2", "5", "excl_frac_rt"))
## the pilot subtracted with the true k, which is arm A3o here
pb <- function(arm, col) g(1.25, arm, "3", col, disp = "biexp")
claim(abs(pb("A3o", "be_rate") - 0.069) > 3 * pb("A3o", "be_rate_mcse"), "the pilot's 0.069 does not reproduce for A3o")
blocks$pilot <- sprintf("<li>One expected pattern from the pilot did not reproduce. The pilot subtracted with the true k, as arm A3o does here. With the biexponential phase at 3 half-lives, A3o's consumer risk is %.4f (MCSE %.4f) against the oracle's %.4f (%.4f), a paired difference of %+.4f (%.4f), and A3, with &lambda;<sub>z</sub> estimated from period 1, gives %.4f (%.4f); the pilot reported 0.069 (INFO rows in the checks).</li>",
  pb("A3o", "be_rate"), pb("A3o", "be_rate_mcse"), pb("A0", "be_rate"), pb("A0", "be_rate_mcse"), pb("A3o", "be_rate_diff_a0"), pb("A3o", "be_rate_diff_a0_mcse"),
  pb("A3", "be_rate"), pb("A3", "be_rate_mcse"))
## figure alt text is hand-written; these are the statements it makes
f1r <- res[res$config == "base" & res$endpoint == "AUC" & res$arm == "A2" & res$theta %in% c(0.80, 1.25) & res$washout %in% c("5", "6", "8", "10"), ]
claim(all(f1r$be_rate >= 0.045 & f1r$be_rate <= 0.07), "F1 alt text: the rule's consumer risk is between about 0.05 and 0.07 from 5 half-lives on")
for (th in c(1.25, 0.80)) claim(part_word(dW(th, "10")$selection_share, dW(th, "10")$selection_share_mcse) == "the retained residual is the larger part", "F3 alt text: by 10 half-lives the retained residual is the larger part")

blocks$runinfo <- sprintf("Committed run: %s replicates per cell (MCSE %s at a rate of 0.05 and at most %s, at a rate of 0.5), %s cells, seed %s, %s; the grid took %s s on %s %s (%s).",
  iv("replicates per cell"), iv("MCSE of a rate of 0.05"), iv("largest MCSE of a rate (at 0.5)"), iv("cells"), iv("seed"),
  esc(iv("R version")), iv("grid run time (s)"), iv("cores"), if (iv("cores") == "1") "core" else "cores", iv("run date"))

## ---- ADaM single-study demonstration (out/adam_demo, written by run_oc.R) -------------------------
dm <- read.csv(file.path(out_dir, "adam_demo", "adpp.csv"), stringsAsFactors = FALSE)
ds <- read.csv("sim_lifecycle/out/adsl.csv", stringsAsFactors = FALSE)   # ADSL is unchanged by washout_h (T10)
x <- dm[dm$PARAMCD == "PDCMXR" & dm$APERIOD == 2, ]; x <- x[order(-x$AVAL, x$USUBJID), ]
xe <- x[x$AVAL > 0.05, ]
fl <- function(u, col) { v <- dm[[col]][dm$USUBJID == u & dm$APERIOD == 2 & dm$PARAMCD == "PDCMXR"]; ifelse(is.na(v), "(null)", v) }
blocks$demo <- paste0(
  sprintf("<p>With <code>washout_h = 48</code>, %d of %d participants have a period-2 pre-dose concentration above 5%% of that period's Cmax (largest ratio %.3f). Their ADPP rows carry a null <code>ANL02FL</code> in both periods, and the period-2 rows give the reason in <code>PKEXRSN</code>; %d participants remain for the bioequivalence analysis.</p>\n",
          nrow(xe), nrow(x), max(x$AVAL), length(unique(dm$USUBJID[dm$ANL02FL %in% "Y"]))),
  html_table(data.frame(USUBJID = xe$USUBJID, Sequence = ds$TRTSEQP[match(xe$USUBJID, ds$USUBJID)],
                        `Period-2 treatment` = xe$TRTA, PDCMXR = sprintf("%.3f", xe$AVAL),
                        ANL02FL = vapply(xe$USUBJID, fl, "", col = "ANL02FL"), PKEXRSN = vapply(xe$USUBJID, fl, "", col = "PKEXRSN"),
                        check.names = FALSE, stringsAsFactors = FALSE),
             "Participants excluded from the bioequivalence analysis in the ADaM demonstration (out/adam_demo/adpp.csv; PDCMXR = pre-dose concentration / Cmax, period 2)."))

## ---- figures (base R PNG), light and dark ---------------------------------------------------------
PAL <- list(
  light = list(bg = "#FFFFFF", ink = "#18212B", muted = "#4F5B67", grid = "#D5DBE1",
               s = c(A0 = "#2a78d6", A1 = "#eb6834", A2 = "#1baf7a", A2s = "#eda100", A3 = "#e87ba4", A3o = "#008300")),
  dark  = list(bg = "#1A2129", ink = "#E6EAEE", muted = "#A9B3BD", grid = "#323C47",
               s = c(A0 = "#3987e5", A1 = "#d95926", A2 = "#199e70", A2s = "#c98500", A3 = "#d55181", A3o = "#008300")))
PCH <- c(A0 = 16, A1 = 17, A2 = 15, A2s = 0, A3 = 18, A3o = 1)
LTY <- c(A0 = 1, A1 = 1, A2 = 1, A2s = 2, A3 = 1, A3o = 3)
dodge <- setNames(seq(-0.15, 0.15, length.out = 6), arms)

fig <- function(name, width, height, draw) for (mode in names(PAL)) {
  p <- PAL[[mode]]
  png(file.path(fig_dir, sprintf("%s%s.png", name, if (mode == "dark") "_dark" else "")), width = width, height = height, res = 180, bg = p$bg)
  op <- par(bg = p$bg, fg = p$muted, col.axis = p$muted, col.lab = p$ink, col.main = p$ink, family = "sans", las = 1)
  draw(p); par(op); dev.off()
}
rate_panel <- function(p, x, ttl, ylim, ref = NULL) {
  plot(NA, xlim = c(1.6, 10.4), ylim = ylim, xaxt = "n", xlab = "Washout (multiples of the mean half-life)",
       ylab = "Rate of concluding BE", main = ttl, cex.main = 1.0, font.main = 1, bty = "n")
  axis(1, at = OC_WASHOUTS)
  abline(h = pretty(ylim), col = p$grid, lwd = 1)
  if (!is.null(ref)) abline(h = ref, col = p$muted, lty = 2, lwd = 1.5)
  for (a in arms) {
    r <- x[x$arm == a & x$washout %in% Wn, ]; r <- r[order(r$W_over_thalf), ]
    xx <- r$W_over_thalf + dodge[[a]]
    segments(xx, pmax(0, r$be_rate - 2 * r$be_rate_mcse), xx, pmin(1, r$be_rate + 2 * r$be_rate_mcse), col = p$s[[a]], lwd = 1.5)
    lines(xx, r$be_rate, col = p$s[[a]], lwd = 2, lty = LTY[[a]])
    points(xx, r$be_rate, col = p$s[[a]], pch = PCH[[a]], cex = 1.1, bg = p$bg)
  }
}
legend_row <- function(p, keys = arms) {
  par(mar = c(0, 0, 0, 0)); plot.new()
  legend("center", legend = paste0(keys, ": ", OC_ARMS[keys]), col = p$s[keys], pch = PCH[keys], lty = LTY[keys], lwd = 2,
         ncol = 2, bty = "n", text.col = p$ink, cex = 0.95, pt.cex = 1.2, x.intersp = 0.8, seg.len = 2.4)
}

fig("f1_consumer_risk", 1500, 1300, function(p) {
  layout(matrix(c(1, 1, 2, 3, 4, 5), 3, 2, byrow = TRUE), heights = c(0.22, 1, 1))
  legend_row(p)
  par(mar = c(4.2, 4.4, 2.4, 1))
  for (disp in c("mono", "biexp")) for (th in c(0.80, 1.25))
    rate_panel(p, sel("base", disp, th), sprintf("True GMR %.2f, %s", th, c(mono = "monoexponential", biexp = "biexponential")[[disp]]),
               c(0, 0.36), ref = 0.05)
})
fig("f2_power", 1500, 800, function(p) {
  layout(matrix(c(1, 1, 2, 3), 2, 2, byrow = TRUE), heights = c(0.36, 1))
  legend_row(p)
  par(mar = c(4.2, 4.4, 2.4, 1))
  for (disp in c("mono", "biexp"))
    rate_panel(p, sel("base", disp, 0.95), sprintf("True GMR 0.95, %s", c(mono = "monoexponential", biexp = "biexponential")[[disp]]), c(0, 1))
})
fig("f3_decomposition", 1500, 780, function(p) {
  layout(matrix(c(1, 1, 2, 3), 2, 2, byrow = TRUE), heights = c(0.24, 1))
  par(mar = c(0, 0, 0, 0)); plot.new()
  legend("center", legend = c("Selection (A2s \u2212 A0)", "Retained residual (A2 \u2212 A2s)", "Total (A2 \u2212 A0), \u00b12 MCSE", "Naive (A1 \u2212 A0)"),
         fill = c(p$s[["A0"]], p$s[["A1"]], NA, NA), border = c(p$bg, p$bg, NA, NA), pch = c(NA, NA, 16, 5),
         col = c(NA, NA, p$ink, p$ink), ncol = 2, bty = "n", text.col = p$ink, cex = 0.95)
  par(mar = c(4.2, 5.6, 2.4, 1))
  for (th in c(1.25, 0.80)) {
    x <- dec[dec$config == "base" & dec$disposition == "mono" & abs(dec$theta - th) < 1e-9 & dec$endpoint == "AUC" & dec$washout %in% Wn, ]
    x <- x[order(as.numeric(x$washout)), ]
    nv <- sel("base", "mono", th)
    naive <- vapply(Wn, function(w) nv$bias[nv$arm == "A1" & nv$washout == w] - nv$bias[nv$arm == "A0" & nv$washout == w], 0)
    ok <- x$n_eval >= 20
    naive[!ok] <- NA                                # shown only where the rule leaves evaluable studies
    yr <- range(c(0, naive, x$bias_total[ok] - 2 * x$bias_total_mcse[ok], x$bias_total[ok] + 2 * x$bias_total_mcse[ok],
                   x$bias_selection[ok] + x$bias_retained[ok], x$bias_selection[ok], x$bias_retained[ok]), na.rm = TRUE)
    yr <- yr + c(-1, 1) * 0.06 * diff(yr)
    plot(NA, xlim = c(0.5, length(Wn) + 0.5), ylim = yr, xaxt = "n", xlab = "Washout (multiples of the mean half-life)",
         ylab = "", main = sprintf("True GMR %.2f, monoexponential, AUC(0-t)", th), cex.main = 1.0, font.main = 1, bty = "n")
    title(ylab = "Bias of log GMR-hat", line = 4.3)
    axis(1, at = seq_along(Wn), labels = Wn)
    abline(h = pretty(yr), col = p$grid); abline(h = 0, col = p$muted)
    for (i in seq_along(Wn)) {
      if (!ok[i]) next
      comp <- c(sel = x$bias_selection[i], ret = x$bias_retained[i]); cols <- c(sel = p$s[["A0"]], ret = p$s[["A1"]])
      up <- 0; dn <- 0
      for (k in names(comp)) {
        v <- comp[[k]]
        if (v >= 0) { rect(i - 0.3, up, i + 0.3, up + v, col = cols[[k]], border = p$bg, lwd = 2); up <- up + v }
        else { rect(i - 0.3, dn + v, i + 0.3, dn, col = cols[[k]], border = p$bg, lwd = 2); dn <- dn + v }
      }
      segments(i, x$bias_total[i] - 2 * x$bias_total_mcse[i], i, x$bias_total[i] + 2 * x$bias_total_mcse[i], col = p$ink, lwd = 2)
      points(i, x$bias_total[i], pch = 16, col = p$ink, cex = 1.1)
    }
    points(seq_along(Wn) + 0.38, naive, pch = 5, col = p$ink, cex = 1.0)
    if (any(!ok)) text(mean(which(!ok)), mean(yr), "No evaluable study\nunder the rule", col = p$muted, cex = 0.8)
  }
})

## ---- inject the generated blocks into index.html ------------------------------------------------
page <- file.path(mod, "index.html")
h <- paste(readLines(page, encoding = "UTF-8"), collapse = "\n")
for (nm in names(blocks)) {
  if (length(blocks[[nm]]) != 1 || !nzchar(blocks[[nm]])) stop("generated block ", nm, " is empty (a column missing from out/*.csv?)")
  pat <- sprintf("(?s)(<!--oc:%s-->)(.*?)(<!--/oc:%s-->)", nm, nm)
  if (!grepl(pat, h, perl = TRUE)) stop("index.html has no block ", nm)
  h <- sub(pat, paste0("\\1\n", gsub("\\\\", "\\\\\\\\", blocks[[nm]]), "\n\\3"), h, perl = TRUE)
}
writeLines(h, page, useBytes = TRUE)
cat(sprintf("Wrote %d tables to out/tables/, 6 figures to out/figures/, and %d generated blocks into index.html\n",
            length(list.files(tab_dir)), length(blocks)))
