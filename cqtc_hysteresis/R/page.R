################################################################################
# cqtc_hysteresis/R/page.R
# Builds cqtc_hysteresis/index.html and the SVG figures from the files in out/,
# so every number on the page is read from an output file. Base R only.
# Called at the end of run_oc.R (or: Rscript cqtc_hysteresis/R/run_oc.R --page-only).
################################################################################

f3 <- function(x) formatC(as.numeric(x), format = "f", digits = 3)
f2 <- function(x) formatC(as.numeric(x), format = "f", digits = 2)
f1 <- function(x) formatC(as.numeric(x), format = "f", digits = 1)
esc <- function(s) { s <- gsub("&", "&amp;", s, fixed = TRUE); s <- gsub("<", "&lt;", s, fixed = TRUE); gsub(">", "&gt;", s, fixed = TRUE) }

## nice axis ticks
nice_ticks <- function(lo, hi, n = 5) {
  step <- diff(pretty(c(lo, hi), n))[1]
  seq(floor(lo / step) * step, ceiling(hi / step) * step, by = step)
}

## standalone SVG files carry their own light/dark colors; inline copies use cqtc.css
SVG_STYLE <- paste0(
  "<style>.ax{stroke:#c3c2b7;stroke-width:1}.gr{stroke:#e1e0d9;stroke-width:1}",
  ".ref{stroke:#898781;stroke-width:1;stroke-dasharray:4 3}.tx{fill:#52514e;font:13px system-ui,-apple-system,'Segoe UI',sans-serif}",
  ".tt{fill:#0b0b0b;font:600 13px system-ui,-apple-system,'Segoe UI',sans-serif}.bg{fill:#fcfcfb}",
  ".s1{stroke:#2a78d6}.s2{stroke:#eb6834}.f1{fill:#2a78d6}.f2{fill:#eb6834}.ring{stroke:#fcfcfb;stroke-width:2}",
  ".ind{stroke:#898781}.find{fill:#898781}",
  "@media (prefers-color-scheme:dark){.ax{stroke:#383835}.gr{stroke:#2c2c2a}.tx{fill:#c3c2b7}.tt{fill:#f0efec}.bg{fill:#1a1a19}",
  ".s1{stroke:#3987e5}.s2{stroke:#d95926}.f1{fill:#3987e5}.f2{fill:#d95926}.ring{stroke:#1a1a19}}</style>")

svg_wrap <- function(body, w, h, title, desc, id, standalone) {
  paste0('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ', w, ' ', h, '" role="img" aria-labelledby="',
         id, '-t ', id, '-d" class="chart">',
         '<title id="', id, '-t">', esc(title), '</title><desc id="', id, '-d">', esc(desc), '</desc>',
         if (standalone) paste0(SVG_STYLE, '<rect class="bg" width="', w, '" height="', h, '"/>') else "",
         body, '</svg>')
}

## ---- F1: rejection rate against ke0 -----------------------------------------------
F1_SERIES <- list(
  list(ids = c("KA1", "KA3-k4", "KA3-k2", "KA3-k1", "KA3-k0.7", "KA3-k0.5", "KA3-k0.35"),
       cls = "1", dash = "", lab = "32 + 8 placebo"),
  list(ids = c("KA1-p32", "KA3-k4-p32", "KA3-k2-p32", "KA3-k1-p32", "KA3-k0.7-p32", "KA3-k0.5-p32", "KA3-k0.35-p32"),
       cls = "1", dash = ' stroke-dasharray="6 4"', lab = "32 + 32 placebo"),
  list(ids = c("KA4-direct", "KA4-k4", "KA4-k2", "KA4-k1", "KA4-k0.7", "KA4-k0.5", "KA4-k0.35"),
       cls = "2", dash = "", lab = "6 + 8 placebo"))
fig_f1 <- function(oc, standalone = FALSE) {
  W <- 540; H <- 310; L <- 52; R <- 124; T <- 16; Bm <- 70
  pw <- W - L - R; ph <- H - T - Bm
  ke0 <- c(Inf, 4, 2, 1, 0.7, 0.5, 0.35)
  th <- ifelse(is.infinite(ke0), 0, log(2) / ke0)
  xs <- function(v) L + v / 2.1 * pw
  ys <- function(v) T + (1 - v) * ph
  get <- function(ids) {
    r <- oc[oc$scenario %in% ids & oc$method == "area_t_one_sided", ]
    r[match(ids, r$scenario), ]
  }
  b <- character(0)
  for (v in seq(0, 1, 0.25)) b <- c(b, sprintf('<line class="gr" x1="%.1f" x2="%.1f" y1="%.1f" y2="%.1f"/>', L, L + pw, ys(v), ys(v)),
                                  sprintf('<text class="tx" x="%.1f" y="%.1f" text-anchor="end" dominant-baseline="middle">%s</text>', L - 6, ys(v), f2(v)))
  b <- c(b, sprintf('<line class="ax" x1="%.1f" x2="%.1f" y1="%.1f" y2="%.1f"/>', L, L + pw, ys(0), ys(0)))
  b <- c(b, sprintf('<line class="ref" x1="%.1f" x2="%.1f" y1="%.1f" y2="%.1f"/>', L, L + pw, ys(0.05), ys(0.05)),
         sprintf('<text class="tx" x="%.1f" y="%.1f" dominant-baseline="middle">alpha 0.05</text>', L + pw + 6, ys(0.05)))
  lab_k <- c("&#8734;", "4", "2", "1", "0.7", "0.5", "0.35")
  for (i in seq_along(th)) b <- c(b,
    sprintf('<line class="ax" x1="%.1f" x2="%.1f" y1="%.1f" y2="%.1f"/>', xs(th[i]), xs(th[i]), ys(0), ys(0) + 5),
    sprintf('<text class="tx" x="%.1f" y="%.1f" text-anchor="middle">%s</text>', xs(th[i]), ys(0) + 19, lab_k[i]))
  for (v in c(0, 0.5, 1, 1.5, 2)) b <- c(b, sprintf('<text class="tx" x="%.1f" y="%.1f" text-anchor="middle">%s</text>', xs(v), ys(0) + 38, f1(v)))
  b <- c(b, sprintf('<text class="tx" x="%.1f" y="%.1f" text-anchor="end">ke0</text>', L - 14, ys(0) + 19),
         sprintf('<text class="tx" x="%.1f" y="%.1f" text-anchor="end">t&#189;</text>', L - 14, ys(0) + 38),
         sprintf('<text class="tt" x="%.1f" y="%.1f" text-anchor="middle">ke0, per h (top); t&#189; = ln 2 / ke0, h (bottom)</text>', L + pw / 2, H - 8))
  ends <- numeric(0)
  for (s in F1_SERIES) {
    d <- get(s$ids); rr <- as.numeric(d$rejection_rate)
    lo <- as.numeric(d$ci95_low); hi <- as.numeric(d$ci95_high)
    pts <- paste(sprintf("%.1f,%.1f", xs(th), ys(rr)), collapse = " ")
    b <- c(b, sprintf('<polyline class="s%s" fill="none" stroke-width="2"%s stroke-linejoin="round" stroke-linecap="round" points="%s"/>', s$cls, s$dash, pts))
    for (i in seq_along(th)) {
      b <- c(b, sprintf('<line class="s%s" stroke-width="1.5" x1="%.1f" x2="%.1f" y1="%.1f" y2="%.1f"/>', s$cls,
                        xs(th[i]), xs(th[i]), ys(hi[i]), ys(lo[i])),
             sprintf('<circle class="f%s ring" cx="%.1f" cy="%.1f" r="4.5"><title>%s, ke0 %s: rejection rate %s (exact 95%% CI %s to %s)</title></circle>',
                     s$cls, xs(th[i]), ys(rr[i]), s$lab, gsub("&#8734;", "infinite (direct effect)", lab_k[i], fixed = TRUE),
                     f3(rr[i]), f3(lo[i]), f3(hi[i])))
    }
    ends <- c(ends, ys(rr[7]))
  }
  ## direct labels at the right end, nudged apart so they never overlap
  o <- order(ends); yl <- ends[o]
  for (i in seq_along(yl)[-1]) yl[i] <- max(yl[i], yl[i - 1] + 15)
  yl[o] <- yl
  for (k in seq_along(F1_SERIES)) b <- c(b, sprintf('<text class="tx" x="%.1f" y="%.1f" dominant-baseline="middle">%s</text>',
                                                    xs(th[7]) + 9, yl[k], F1_SERIES[[k]]$lab))
  b <- c(b, sprintf('<text class="tx" transform="translate(13 %.1f) rotate(-90)" text-anchor="middle">Rejection rate, one-sided</text>', T + ph / 2))
  g <- function(id) f2(as.numeric(get(id)$rejection_rate))
  svg_wrap(paste(b, collapse = ""), W, H, "F1. Rejection rate of the one-sided placebo-adjusted area test against ke0",
           sprintf("Linear direct-effect model. With 32 active and 8 placebo participants the rejection rate rises from %s with no delay to %s at ke0 0.7 per hour; with 32 placebo participants it reaches %s; for one SAD cohort of 6 active participants against 8 placebo it stays at or below %s.",
                   g("KA1"), g("KA3-k0.7"), g("KA3-k0.7-p32"),
                   f2(max(as.numeric(get(F1_SERIES[[3]]$ids)$rejection_rate)))),
           "f1", standalone)
}

## ---- F2: example individual and mean loops ---------------------------------------
loop_panel <- function(x_ind, y_ind, x_mean, y_mean, y_se, title, id, standalone, ylab) {
  W <- 340; H <- 270; L <- 46; R <- 12; T <- 26; Bm <- 44
  pw <- W - L - R; ph <- H - T - Bm
  lo <- min(c(y_ind, y_mean - y_se, 0)); hi <- max(c(y_ind, y_mean + y_se, 1))
  tk <- nice_ticks(lo, hi, 5); lo <- min(tk); hi <- max(tk)
  xs <- function(v) L + v * pw
  ys <- function(v) T + (hi - v) / (hi - lo) * ph
  b <- c(sprintf('<defs><marker id="%s-a" viewBox="0 0 10 10" refX="7" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path class="f1" d="M0,1 L9,5 L0,9 z"/></marker></defs>', id),
         sprintf('<text class="tt" x="%.1f" y="16">%s</text>', L, esc(title)))
  for (v in tk) b <- c(b, sprintf('<line class="%s" x1="%.1f" x2="%.1f" y1="%.1f" y2="%.1f"/>', if (v == 0) "ax" else "gr", L, L + pw, ys(v), ys(v)),
                       sprintf('<text class="tx" x="%.1f" y="%.1f" text-anchor="end" dominant-baseline="middle">%s</text>', L - 6, ys(v), format(v)))
  for (v in seq(0, 1, 0.25)) b <- c(b, sprintf('<text class="tx" x="%.1f" y="%.1f" text-anchor="middle">%s</text>', xs(v), T + ph + 18, format(v)))
  b <- c(b, sprintf('<text class="tx" x="%.1f" y="%.1f" text-anchor="middle">Concentration / Cmax</text>', L + pw / 2, H - 6),
         sprintf('<text class="tx" transform="translate(12 %.1f) rotate(-90)" text-anchor="middle">%s</text>', T + ph / 2, esc(ylab)))
  ## individual (noise-free typical participant): thin, muted, dashed
  b <- c(b, sprintf('<polyline class="ind" fill="none" stroke-width="1.5" stroke-dasharray="5 3" points="%s"/>',
                    paste(sprintf("%.1f,%.1f", xs(x_ind), ys(y_ind)), collapse = " ")))
  ## mean loop: SE whiskers, segments with arrowheads in time order, closing segment back to 0 h
  m <- length(x_mean)
  for (j in seq_len(m)) b <- c(b, sprintf('<line class="s1" stroke-width="1" x1="%.1f" x2="%.1f" y1="%.1f" y2="%.1f"/>',
                                       xs(x_mean[j]), xs(x_mean[j]), ys(y_mean[j] - y_se[j]), ys(y_mean[j] + y_se[j])))
  for (j in seq_len(m)) {
    k <- if (j == m) 1 else j + 1
    b <- c(b, sprintf('<line class="s1" stroke-width="2" stroke-linecap="round" %sx1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f"/>',
                      if (j < m) sprintf('marker-end="url(#%s-a)" ', id) else 'stroke-dasharray="2 3" ',
                      xs(x_mean[j]), ys(y_mean[j]), xs(x_mean[k]), ys(y_mean[k])))
  }
  b <- c(b, sprintf('<circle class="f1 ring" cx="%.1f" cy="%.1f" r="4"><title>0 h (predose)</title></circle>', xs(x_mean[1]), ys(y_mean[1])),
         sprintf('<text class="tx" x="%.1f" y="%.1f">0 h</text>', xs(x_mean[1]) + 7, ys(y_mean[1]) + 15))
  svg_wrap(paste(b, collapse = ""), W, H, title,
           "Mean loop in time order with arrows and plus or minus one standard error, and the noise-free typical participant as a dashed line.",
           id, standalone)
}

fig_f2 <- function(standalone = FALSE) {
  set.seed(20261025L + 900L)
  times <- DEFAULT_TIMES
  ## 200 active and 200 placebo participants (more than a trial has) so the expected
  ## shape of each mean loop is visible
  dl <- sim_trial(200, 200, model = "linear"); dd <- sim_trial(200, 200, model = "linear", ke0 = 0.7)
  de <- sim_trial(200, 200, model = "emax")
  fe <- fit_emax(de$C, de$Y)
  tp <- function(...) { p <- typical_profile(times, ...); list(x = p$C / max(p$C), y = p$E, C = p$C) }
  pl <- tp(); pd <- tp(ke0 = 0.7); pe <- tp(model = "emax")
  pe_res <- pe$y - f_shape(fe, pe$C); pe_res <- pe_res - mean(pe_res)
  mk <- function(d, Y) { X <- scale_conc(d$C); list(x = colMeans(X), y = colMeans(Y), se = apply(Y, 2, sd) / sqrt(nrow(Y)),
                                                     A = mean(loop_areas(X, Y))) }
  ml <- mk(dl, dl$Y); md <- mk(dd, dd$Y); me <- mk(de, de$Y); mr <- mk(de, de$Y - fe$fitted)
  panels <- list(
    list(pl, ml, "a. Linear, no delay", "ddQTcF (ms)"),
    list(pd, md, "b. Linear, delay ke0 = 0.7 per h", "ddQTcF (ms)"),
    list(pe, me, "c. Emax, no delay: raw ddQTcF", "ddQTcF (ms)"),
    list(list(x = pe$x, y = pe_res), mr, "d. Emax, no delay: Emax residual", "Residual ddQTcF (ms)"))
  lapply(seq_along(panels), function(i) {
    p <- panels[[i]]
    list(svg = loop_panel(p[[1]]$x, p[[1]]$y, p[[2]]$x, p[[2]]$y, p[[2]]$se, p[[3]], paste0("f2", letters[i]), standalone, p[[4]]),
         A = p[[2]]$A, A_typ = loop_area(p[[1]]$x, p[[1]]$y))
  })
}

## ---- T1: the OC table ---------------------------------------------------------------
METHOD_LABEL <- c(
  area_t_one_sided = "Signed area, placebo-adjusted t, one-sided (raw ddQTcF; equals the linear-f residual area)",
  area_t_two_sided = "Signed area, placebo-adjusted t, two-sided",
  area_signflip_one_sided = "Signed area, participant-level sign-flip, one-sided (exact only with independent ddQTcF errors)",
  area_signflip_two_sided = "Signed area, participant-level sign-flip, two-sided",
  emax_resid_t_one_sided = "Emax-residual area, placebo-adjusted t, one-sided",
  emax_resid_t_two_sided = "Emax-residual area, placebo-adjusted t, two-sided",
  linearity_check_picks_emax = "Linearity check selects Emax (selection rate, not a test)",
  selected_f_resid_t_one_sided = "Area on residuals from the f the linearity check selects, one-sided",
  param_boot_one_sided = "Parametric bootstrap from the fitted model, one-sided (secondary)",
  tmax_gap_individual_gt_1h = "tmax gap > 1 h, median of individual peak times (rate the rule fires)",
  tmax_gap_mean_profile_gt_1h = "tmax gap > 1 h, peak of the mean profile (rate the rule fires)",
  day_m1_t_two_sided = "Day -1 pseudo-loop check, placebo-adjusted t, two-sided",
  day_m1_t_one_sided = "Day -1 pseudo-loop check, placebo-adjusted t, one-sided",
  day_m1_signflip_two_sided = "Day -1 pseudo-loop check, sign-flip, two-sided")
## the MCSE cell: sqrt(p(1 - p) / R) is 0 when no replicate (or every replicate) rejects,
## so those rows show n/a and the exact interval carries the uncertainty
mcse_cell <- function(m) ifelse(is.na(m) | m == "NA", "n/a", f3(m))
design_txt <- function(d) if (d$placebo[1] == "within") sprintf("%s active, each with their own placebo period", d$n[1]) else
  sprintf("%s active, %s placebo", d$n[1], d$n_pbo[1])
table_t1 <- function(oc) {
  rows <- character(0)
  for (sid in unique(oc$scenario)) {
    d <- oc[oc$scenario == sid, ]
    rows <- c(rows, sprintf('<tr class="grp"><th colspan="4" scope="rowgroup">%s: %s (%s; seed %s)</th></tr>',
                            esc(sid), esc(d$label[1]), design_txt(d), d$seed[1]))
    for (i in seq_len(nrow(d))) rows <- c(rows, sprintf('<tr><td>%s</td><td class="num">%s</td><td class="num">%s</td><td class="num">%s to %s</td></tr>',
                                                    esc(METHOD_LABEL[[d$method[i]]]), f3(d$rejection_rate[i]), mcse_cell(d$mcse[i]),
                                                    f3(d$ci95_low[i]), f3(d$ci95_high[i])))
  }
  paste0('<div class="tblwrap"><table class="oc"><caption>T1. Operating characteristics: rejection rate at alpha 0.05 (one-sided unless stated) over 1,000 synthetic replicates per scenario, with its Monte Carlo standard error (MCSE) and exact (Clopper-Pearson) 95% interval. When no replicate, or every replicate, rejects, the MCSE formula gives 0, so the table shows n/a and the interval carries the uncertainty. Scenario k uses seed 20261025 + k. Source: <a href="out/oc_results.csv">out/oc_results.csv</a>.</caption>',
         '<thead><tr><th scope="col">Method</th><th scope="col" class="num">Rate</th><th scope="col" class="num">MCSE</th><th scope="col" class="num">Exact 95% CI</th></tr></thead><tbody>',
         paste(rows, collapse = "\n"), '</tbody></table></div>')
}

## ---- page -------------------------------------------------------------------------------
build_page <- function(mod) {
  out <- file.path(mod, "out")
  oc <- read.csv(file.path(out, "oc_results.csv"), stringsAsFactors = FALSE, colClasses = "character")
  nf <- read.csv(file.path(out, "noise_free_areas.csv"), stringsAsFactors = FALSE)
  ex <- read.csv(file.path(out, "example_check.csv"), stringsAsFactors = FALSE)
  meta <- readLines(file.path(out, "oc_meta.json"))
  rver <- sub('.*"r_version": "([^"]+)".*', "\\1", grep("r_version", meta, value = TRUE))
  rr <- function(sid, m) { r <- oc[oc$scenario == sid & oc$method == m, ]; stopifnot(nrow(r) == 1); r }
  num  <- function(sid, m) as.numeric(rr(sid, m)$rejection_rate)
  rate <- function(sid, m) f3(rr(sid, m)$rejection_rate)
  ## "rate (MCSE x)", or the exact bound when the rate is 0 or 1
  rmc  <- function(sid, m) { r <- rr(sid, m); x <- as.integer(r$rejections); R <- as.integer(r$replicates)
    if (x == 0) return(paste0(f3(r$rejection_rate), " (exact 95% upper bound ", f3(r$ci95_high), ")"))
    if (x == R) return(paste0(f3(r$rejection_rate), " (exact 95% lower bound ", f3(r$ci95_low), ")"))
    paste0(f3(r$rejection_rate), " (MCSE ", f3(r$mcse), ")") }
  nfa  <- function(case, col = "area_12_point_ms") f2(nf[nf$case == case, col])

  ## figures: standalone files in out/, inline copies in the page
  writeLines(fig_f1(oc, TRUE), file.path(out, "f1_rejection_vs_ke0.svg"))
  f2s <- fig_f2(TRUE)
  for (i in seq_along(f2s)) writeLines(f2s[[i]]$svg, file.path(out, sprintf("f2%s_loop.svg", letters[i])))
  f2i <- fig_f2(FALSE)
  f2cap <- c("No delay: the mean path goes out and back along one line.",
             "Delay: the effect is low on the way up and high on the way down, so the loop runs counterclockwise.",
             "Curved direct effect sampled at 12 times: the raw path still encloses area.",
             "The same data after removing the fitted Emax curve: almost no area is left.")
  f2html <- paste(vapply(seq_along(f2i), function(i) paste0(
    '<figure class="loop">', f2i[[i]]$svg, '<figcaption>', f2cap[i], ' Mean signed area: <strong>',
    f2(f2i[[i]]$A), ' ms</strong>.</figcaption></figure>'), ""), collapse = "\n")

  extab <- paste(vapply(seq_len(nrow(ex)), function(i) {
    e <- ex[i, ]
    sprintf('<tr><td data-label="Dataset">%s</td><td data-label="f">%s</td><td class="num" data-label="A-bar, ms (95%% CI); SE (df)">%s<br>(%s, %s)<br><span class="small">SE %s (df %s)</span></td><td class="num" data-label="p, one / two-sided">%s / %s</td><td class="num" data-label="Bootstrap p">%s</td><td class="num" data-label="tmax gap, h (individual / mean)">%s / %s</td><td class="num" data-label="Day -1 A-bar, ms">%s<br>(p %s)</td></tr>',
            esc(e$dataset), e$model_for_f, f2(e$Abar_ms), f2(e$ci95_low), f2(e$ci95_high), f2(e$se_ms), f1(e$df),
            formatC(e$p_one_sided, format = "f", digits = 4), formatC(e$p_two_sided, format = "f", digits = 4),
            f3(e$boot_p_one_sided), f1(e$tmax_gap_individual_h), f1(e$tmax_gap_mean_profile_h),
            f2(e$day_m1_Abar_ms), f3(e$day_m1_p_two_sided))
  }, ""), collapse = "\n")

  nc_rows <- paste(vapply(c(0, 6, 12, 18), function(phi) {
    sid <- paste0("NC1-phi", phi)
    sprintf('<tr><td data-label="Phase">phi = %d h</td><td class="num" data-label="Noise-free area, ms">%s</td><td class="num" data-label="Day 1, one-sided">%s</td><td class="num" data-label="Day 1, two-sided">%s</td><td class="num" data-label="Day -1 check, two-sided">%s</td></tr>',
            phi, nfa(sprintf("Residual time pattern only, phi = %d h", phi)),
            rate(sid, "area_t_one_sided"), rate(sid, "area_t_two_sided"), rate(sid, "day_m1_t_two_sided"))
  }, ""), collapse = "\n")
  nc_rows <- paste0(nc_rows, sprintf('\n<tr><td data-label="Phase">No residual pattern (KA1)</td><td class="num" data-label="Noise-free area, ms">0.00</td><td class="num" data-label="Day 1, one-sided">%s</td><td class="num" data-label="Day 1, two-sided">%s</td><td class="num" data-label="Day -1 check, two-sided">%s</td></tr>',
                                     rate("KA1", "area_t_one_sided"), rate("KA1", "area_t_two_sided"), rate("KA1", "day_m1_t_two_sided")))

  ## guards: the prose below states these comparisons, so stop if a rerun reverses one
  stopifnot(num("KA1", "area_signflip_one_sided") > 0.1, num("KA1-p32", "area_signflip_one_sided") > 0.075,
            num("KA3-k0.7-p32", "area_t_one_sided") > num("KA3-k0.7", "area_t_one_sided"),
            num("NC1-phi0", "area_t_one_sided") > 0.1, num("NC1-phi0", "day_m1_t_two_sided") < 0.5,
            num("NC1-phi12", "day_m1_t_two_sided") < 0.5, num("KA2", "area_t_one_sided") > 0.15,
            num("KA2", "emax_resid_t_one_sided") < 0.05)

  v <- list(
    RVER = esc(rver),
    KA1 = rmc("KA1", "area_t_one_sided"), KA1_TWO = rate("KA1", "area_t_two_sided"), KA1_R = rate("KA1", "area_t_one_sided"),
    KA1_SF = rmc("KA1", "area_signflip_one_sided"), KA1_SF_R = rate("KA1", "area_signflip_one_sided"),
    KA1P16 = rate("KA1-p16", "area_t_one_sided"), KA1P32 = rate("KA1-p32", "area_t_one_sided"),
    KA1P16_SF = rate("KA1-p16", "area_signflip_one_sided"), KA1P32_SF = rate("KA1-p32", "area_signflip_one_sided"),
    KAW_SF = rmc("KA1-within", "area_signflip_one_sided"), KAW_SF2 = rate("KA1-within", "area_signflip_two_sided"),
    KA1_BOOT = rate("KA1", "param_boot_one_sided"), KA1_SEL = rate("KA1", "selected_f_resid_t_one_sided"),
    KA1_PICK = rate("KA1", "linearity_check_picks_emax"),
    KA1_TI = rate("KA1", "tmax_gap_individual_gt_1h"), KA1_TM = rate("KA1", "tmax_gap_mean_profile_gt_1h"),
    KA1_D1 = rmc("KA1", "day_m1_t_two_sided"), KA1_D1_R = rate("KA1", "day_m1_t_two_sided"), KA1_D1_SF = rate("KA1", "day_m1_signflip_two_sided"),
    KA2_RAW = rmc("KA2", "area_t_one_sided"), KA2_EMAX = rmc("KA2", "emax_resid_t_one_sided"),
    KA2_EMAX_R = rate("KA2", "emax_resid_t_one_sided"), KA2_RAW_R = rate("KA2", "area_t_one_sided"),
    KA2_EMAX2 = rate("KA2", "emax_resid_t_two_sided"), KA2_PICK = rate("KA2", "linearity_check_picks_emax"),
    KA2_SEL = rate("KA2", "selected_f_resid_t_one_sided"), KA2_BOOT = rate("KA2", "param_boot_one_sided"),
    KA2D_RAW = rate("KA2-delay", "area_t_one_sided"), KA2D_EMAX = rate("KA2-delay", "emax_resid_t_one_sided"),
    K2 = rate("KA3-k2", "area_t_one_sided"), K07 = rmc("KA3-k0.7", "area_t_one_sided"), K035 = rate("KA3-k0.35", "area_t_one_sided"),
    K07_BOOT = rate("KA3-k0.7", "param_boot_one_sided"),
    K07_P16 = rate("KA3-k0.7-p16", "area_t_one_sided"), K07_P32 = rate("KA3-k0.7-p32", "area_t_one_sided"),
    K07_W = rate("KA3-k0.7-within", "area_signflip_one_sided"), K07_R = rate("KA3-k0.7", "area_t_one_sided"),
    K07_TI = rate("KA3-k0.7", "tmax_gap_individual_gt_1h"), K07_TM = rate("KA3-k0.7", "tmax_gap_mean_profile_gt_1h"),
    KA4_0 = rmc("KA4-direct", "area_t_one_sided"), KA4_0_R = rate("KA4-direct", "area_t_one_sided"),
    KA4_0_SF = rate("KA4-direct", "area_signflip_one_sided"),
    KA4_07 = rate("KA4-k0.7", "area_t_one_sided"), KA4_035 = rate("KA4-k0.35", "area_t_one_sided"),
    KA4_TI = rate("KA4-direct", "tmax_gap_individual_gt_1h"), KA4_TM = rate("KA4-direct", "tmax_gap_mean_profile_gt_1h"),
    KA5_ONE = rmc("KA5", "area_t_one_sided"), KA5_TWO = rmc("KA5", "area_t_two_sided"),
    NF_EMAX12 = nfa("Emax, direct effect"), NF_EMAXD = f3(nf[nf$case == "Emax, direct effect", "area_dense_grid_ms"]),
    NF_LIN = nfa("Linear, direct effect"), NF_DELAY = nfa("Linear, ke0 = 0.7 per h"),
    NF_TOL = nfa("Tolerance, gamma = 3, k_m = 0.35 per h"),
    NC0 = rmc("NC1-phi0", "area_t_one_sided"), NC0_X = f1(num("NC1-phi0", "area_t_one_sided") / 0.05),
    NC6 = rate("NC1-phi6", "area_t_one_sided"), NC6_2 = rate("NC1-phi6", "area_t_two_sided"),
    NC18 = rate("NC1-phi18", "area_t_one_sided"), NC12 = rate("NC1-phi12", "area_t_one_sided"),
    NC12_2 = rate("NC1-phi12", "area_t_two_sided"),
    NC6_D1 = rate("NC1-phi6", "day_m1_t_two_sided"), NC18_D1 = rate("NC1-phi18", "day_m1_t_two_sided"),
    NC0_D1 = rmc("NC1-phi0", "day_m1_t_two_sided"), NC12_D1 = rate("NC1-phi12", "day_m1_t_two_sided"),
    F1 = fig_f1(oc, FALSE), F2 = f2html, T1 = table_t1(oc), EXTAB = extab, NCROWS = nc_rows,
    NSCEN = as.character(length(unique(oc$scenario))),
    EX_DF = sprintf("%s to %s", f1(min(ex$df)), f1(max(ex$df))))
  html <- PAGE_TEMPLATE
  for (k in names(v)) html <- gsub(paste0("{{", k, "}}"), v[[k]], html, fixed = TRUE)
  stopifnot(!grepl("{{", html, fixed = TRUE))
  writeLines(html, file.path(mod, "index.html"), useBytes = TRUE)
  invisible(TRUE)
}

PAGE_TEMPLATE <- r"---(<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>C-QTc Hysteresis Check | Patrick Iben</title>
<meta name="description" content="A prespecified C-QTc hysteresis check: the signed area of each participant's concentration-ddQTcF loop on residuals from the direct-effect model, tested with a standard error that allows for the shared placebo mean, with its operating characteristics on synthetic data.">
<link rel="icon" href="data:,">
<link rel="stylesheet" href="../site.css">
<link rel="stylesheet" href="cqtc.css">
</head>
<body>
<a class="skip" href="#main">Skip to content</a>
<header class="top">
  <div class="wrap">
    <a class="name" href="../index.html">Patrick Iben</a>
    <nav aria-label="Site">
      <a href="../index.html">Home</a>
      <a href="../index.html#lifecycle">Lifecycle</a>
      <a href="../sas_tlf_pseudocode/index.html">SAS library</a>
      <a href="../r_tlf_pseudocode/index.html">R library</a>
    </nav>
  </div>
</header>
<main id="main" class="wrap">
  <section class="page-head">
    <p class="kicker">SAP and mock shells: a prespecified check</p>
    <h1>C-QTc hysteresis check: a signed loop area on model residuals</h1>
    <p class="meta"><span class="lab tools">Tools built</span><span class="lab tools">Runs: cqtc_hysteresis/R/run_oc.R</span><span class="lab tools">Exploratory (synthetic)</span></p>
    <p class="synthetic">Synthetic data only: simulated for this page; not trial data and not a regulatory deliverable.</p>
  </section>

  <div class="note"><p><strong>Tools built:</strong> a small formalization of the standard C-QTc hysteresis check. The signed loop area is established (cyclicity analysis; the hysteresis-loop literature). This page computes it on residuals from the prespecified direct-effect model and documents its operating characteristics on synthetic data. It supplements, and does not replace, the prespecified C-QTc model or effect-compartment modeling.</p></div>

  <ol class="toc">
    <li><a href="#sap-step">The SAP step this formalizes</a></li>
    <li><a href="#statistic">Statistic</a></li>
    <li><a href="#model">Why the model matters</a></li>
    <li><a href="#oc">Operating characteristics</a></li>
    <li><a href="#diurnal">Diurnal confound and the Day -1 check</a></li>
    <li><a href="#sap-text">SAP text</a></li>
    <li><a href="#limits">What it does not do</a></li>
    <li><a href="#credit">Provenance and credit</a></li>
  </ol>

  <h2 id="sap-step">The SAP step this formalizes</h2>
  <p>Concentration-QTc (C-QTc) analysis under ICH E14 Q&amp;A (R3) (Q5.1) fits a prespecified model of ddQTcF (the change from baseline in QTcF minus the time-matched placebo mean) on plasma concentration, usually a linear mixed-effects model (Garnett et al. 2018). That model assumes the effect follows concentration with no delay. Before fitting it, the SAP checks for hysteresis: an effect that lags concentration, from distribution to the site of action, a metabolite or slow channel kinetics.</p>
  <p>The check is usually visual. The registry SAPs listed under credit assess it with joint plots of the mean ddQTcF and mean concentration by time and a "hysteresis plot", and consider other models if "the curve of the hysteresis plot shows a counterclockwise loop" and the time of the peak effect is more than 1 hour from tmax. The CiPA Phase 1 SAP adds a formal one-sided Wilcoxon test at 1% alongside the same 1 hour rule. This page replaces the visual judgment with one number per participant and a test whose size and power are documented on synthetic data, and keeps the tmax gap beside it.</p>

  <h2 id="statistic">Statistic</h2>
  <div class="panel">
    <p><strong>Data.</strong> For each active participant i: actual times t<sub>1</sub> &lt; ... &lt; t<sub>m</sub> over the dosing interval, concentration C<sub>ij</sub> and ddQTcF<sub>ij</sub>. Concentration is scaled to the participant's own Cmax, x<sub>ij</sub> = C<sub>ij</sub> / max<sub>j</sub> C<sub>ij</sub> (prespecified). For each placebo participant k in the pooled placebo group: dQTcF<sub>kj</sub> at the same nominal times, whose mean at each time, pbar<sub>j</sub>, is subtracted from every active participant's dQTcF to give ddQTcF.</p>
    <p><strong>Direct-effect model</strong> (prespecified, no time factor): ddQTcF<sub>ij</sub> = f(C<sub>ij</sub>; theta) + b<sub>i</sub> + e<sub>ij</sub>, with f linear (theta<sub>0</sub> + theta<sub>1</sub> C), or Emax (E<sub>0</sub> + Emax C / (EC50 + C)) if the SAP's linearity check selects it. Residuals r<sub>ij</sub> = ddQTcF<sub>ij</sub> - f-hat(C<sub>ij</sub>) - b-hat<sub>i</sub>.</p>
    <p><strong>Signed area</strong> of the closed path (x<sub>i1</sub>, r<sub>i1</sub>), ..., (x<sub>im</sub>, r<sub>im</sub>), back to the start (the shoelace formula, index m + 1 = 1):</p>
    <p class="eq">A<sub>i</sub> = &#189; &Sigma;<sub>j=1..m</sub> (x<sub>j</sub> r<sub>j+1</sub> - x<sub>j+1</sub> r<sub>j</sub>)</p>
    <p>A<sub>i</sub> &gt; 0 means the loop runs counterclockwise: the effect is lower on the way up than on the way down, so it lags concentration. A<sub>i</sub> is in ms. It is also the off-diagonal of the antisymmetric part of the lag-1 cross-moment &Gamma; = &Sigma;<sub>j</sub> z<sub>j</sub> z<sub>j+1</sub><sup>T</sup> with z<sub>j</sub> = (x<sub>j</sub>, r<sub>j</sub>), so reversing time flips its sign exactly.</p>
    <p><strong>Why the test must allow for the placebo mean.</strong> The statistic is A-bar, the mean of A<sub>i</sub> over the active participants. Under the null (no delay given f, with errors independent of C and symmetric), each A<sub>i</sub> is symmetric about 0, because it is linear in the errors; autocorrelation within a participant is allowed. The A<sub>i</sub> are not independent, though: every active participant's ddQTcF subtracts the same placebo mean, so every A<sub>i</sub> carries minus the area of its x path against the same placebo-mean noise. Because the area is bilinear, A-bar is exactly the mean active area on dQTcF minus the mean of h<sub>k</sub>, where h<sub>k</sub> is the signed area of placebo participant k's dQTcF against the active participants' mean x profile (checked to 1e-10 in the tests). Its variance therefore has a placebo part that shrinks with the number of placebo participants, not the number of active ones. A participant-level sign-flip test of the A<sub>i</sub> leaves that part out: with 32 active and 8 placebo participants and no delay, it rejected in {{KA1_SF}} of trials at a nominal 0.05.</p>
    <p><strong>Test</strong> (pooled placebo, as in SAD and MAD studies). t = A-bar / SE, with SE<sup>2</sup> = s<sup>2</sup><sub>A</sub> / n + s<sup>2</sup><sub>h</sub> / n<sub>pbo</sub>, where s<sup>2</sup><sub>A</sub> is the sample variance of the A<sub>i</sub> (the shared term is nearly the same for every participant, so it nearly drops out of it) and s<sup>2</sup><sub>h</sub> that of the h<sub>k</sub>, computed on each placebo participant's deviation from pbar. The degrees of freedom are Welch-Satterthwaite. This is a two-group (Welch) comparison; its size is approximate, not exact, and was checked on the synthetic designs below. One-sided for counterclockwise loops; two-sided also catches clockwise loops (tolerance). Secondary: a parametric bootstrap from the fitted direct-effect model that also draws the placebo-mean noise (B = 999).</p>
    <p><strong>When the sign-flip test is exact.</strong> If each participant's ddQTcF is corrected by their own placebo profile (a crossover with a placebo period), nothing is shared and the A<sub>i</sub> are independent. A participant-level sign-flip test is then exact: all 2<sup>n</sup> sign vectors when n &le; 20, otherwise B = 9,999 random sign vectors with p = (1 + #{A-bar* &ge; A-bar}) / (B + 1).</p>
    <p><strong>Reported beside the test:</strong> A-bar in ms with a 95% CI from the same SE and degrees of freedom, the model used for f, and the tmax gap (the time of peak ddQTcF minus the median tmax, flagged when it exceeds 1 hour). Two versions of the gap are computed: the median over participants of the time of peak ddQTcF, and the time of the peak of the mean ddQTcF profile, as in the registry SAPs.</p>
  </div>
  <p>One synthetic trial (32 active and 8 placebo participants, seed 20261025) through <code>hysteresis_check()</code>, the function the mock shells mirror:</p>
  <div class="tblwrap"><table class="oc ex stack"><caption>What the check reports for one synthetic dataset per row (<a href="out/example_check.csv">out/example_check.csv</a>). p values and CI from the placebo-adjusted t-test; the bootstrap uses 999 draws. The placebo-mean part dominates the SE, so the Welch-Satterthwaite degrees of freedom ({{EX_DF}} here) are close to the placebo group's size, not the active group's.</caption>
  <thead><tr><th scope="col">Dataset (32 + 8 placebo)</th><th scope="col">f</th><th scope="col" class="num">A-bar, ms (95% CI); SE (df)</th><th scope="col" class="num">p, one / two-sided</th><th scope="col" class="num">Bootstrap p</th><th scope="col" class="num">tmax gap, h (individual / mean)</th><th scope="col" class="num">Day -1 A-bar, ms</th></tr></thead>
  <tbody>
{{EXTAB}}
  </tbody></table></div>

  <h2 id="model">Why the model matters</h2>
  <p>The closed-path area of any straight line (x, a + b x) is exactly 0, and a participant-level constant adds no area. So under a linear f the residual area equals the raw area of ddQTcF itself, whatever the fitted slope and intercepts. A curved direct effect is different. Sampled at 12 times, the path up and the path down pass through different points of the curve and the closing segment cuts a chord, so the raw path encloses area with no delay at all: <strong>{{NF_EMAX12}} ms</strong> for the noise-free typical participant under the Emax model, against {{NF_EMAXD}} ms on a 0.01 h grid and {{NF_DELAY}} ms for a real delay (linear, ke0 = 0.7 per h).</p>
  <p>With noise, 32 active and 8 placebo participants, the raw-area test rejects in <strong>{{KA2_RAW}}</strong> of trials with an Emax direct effect and no delay. On residuals from the Emax fit the rate is <strong>{{KA2_EMAX}}</strong>, and {{KA2_EMAX2}} two-sided. The CiPA-style linearity check (a quadratic term tested two-sided at 5%, then the Emax model kept when its AIC is lower) picks Emax in {{KA2_PICK}} of these trials and {{KA1_PICK}} of the linear ones, and the area on residuals from the f it selects rejects in {{KA2_SEL}} (Emax truth) and {{KA1_SEL}} (linear truth); the MCSE of these rates is at most 0.016. When the Emax effect is also delayed (ke0 = 0.7 per h), both areas keep their power: {{KA2D_RAW}} raw and {{KA2D_EMAX}} on Emax residuals. The residual area is conditional on the prespecified form: it removes the curvature the model describes, not curvature it misses.</p>
  <div class="loops">
{{F2}}
  </div>
  <p class="small">F2. Example loops. Solid: the mean over 200 simulated active participants, corrected by the mean of 200 placebo participants (more than a trial has, so that the expected shape is visible), in time order (arrows; whiskers are plus or minus one standard error; the dotted segment closes the path from 24 h back to 0 h). Dashed: the noise-free typical participant (ka 1.2 per h, ke 0.15 per h). A single noisy participant's loop is mostly noise here (residual SD 5 ms against a peak effect of about 6 ms under the linear model); the test pools the signed areas across participants. Standalone files: <a href="out/f2a_loop.svg">a</a>, <a href="out/f2b_loop.svg">b</a>, <a href="out/f2c_loop.svg">c</a>, <a href="out/f2d_loop.svg">d</a>.</p>

  <h2 id="oc">Operating characteristics</h2>
  <p><strong>Synthetic known-answer design</strong> ({{NSCEN}} scenarios; 1,000 replicates each, so the MCSE of a rate near 0.05 is 0.007; scenario k uses seed 20261025 + k, listed in T1 and in the CSV). 32 active participants and a pooled placebo group of 8 (for example, four cohorts of 8 active and 2 placebo participants), sampled at 0, 0.5, 1, 1.5, 2, 3, 4, 6, 8, 12, 16 and 24 h. One-compartment oral PK with ka = 1.2 exp(N(0, 0.3<sup>2</sup>)) per h, ke = 0.15 exp(N(0, 0.3<sup>2</sup>)) per h and D/V = 2; an effect compartment dCe/dt = ke0 (C - Ce), solved analytically. Every participant's dQTcF carries a common daily rhythm, 4 sin(2&pi;(t + 18)/24) ms, and N(0, 5<sup>2</sup>) noise; active participants add a drug effect of 4 ms &times; Ce, or 20 Ce / (Ce + 0.4) ms for the Emax variant. ddQTcF is active dQTcF minus the time-matched placebo mean, as in the mock shells. One-sided alpha 0.05.</p>
  <ul class="facts">
    <li><strong>KA1, size.</strong> Linear model, direct effect: the placebo-adjusted t-test rejects in {{KA1}}; two-sided, {{KA1_TWO}}; the parametric bootstrap, {{KA1_BOOT}}. With 16 and 32 placebo participants it rejects in {{KA1P16}} and {{KA1P32}}. The one-sample sign-flip test on the same areas rejects in {{KA1_SF_R}}, {{KA1P16_SF}} and {{KA1P32_SF}}: too often whenever the placebo mean is shared. In the crossover variant, where each participant's ddQTcF uses their own placebo period, the sign-flip test is exact and rejects in {{KAW_SF}}; two-sided, {{KAW_SF2}}.</li>
    <li><strong>KA2, curvature.</strong> Emax, no delay: raw area {{KA2_RAW_R}}, Emax-residual area {{KA2_EMAX_R}}, bootstrap from the Emax fit {{KA2_BOOT}} (MCSE at most 0.016).</li>
    <li><strong>KA3, power.</strong> Linear model with delay, 32 active and 8 placebo participants: {{K2}} at ke0 = 2 per h (equilibration half-life 0.35 h), {{K07}} at 0.7 per h (1 h) and {{K035}} at 0.35 per h (2 h). Power rises little beyond ke0 = 0.7 per h (F1), because a still slower effect site makes the effect itself smaller and flatter. The placebo group sets most of the noise: at ke0 = 0.7 per h power is {{K07_P16}} with 16 placebo participants, {{K07_P32}} with 32, and {{K07_W}} in the crossover variant with the sign-flip test (MCSE at most 0.016).</li>
    <li><strong>KA4, one SAD cohort.</strong> 6 active participants against the pooled placebo group of 8: size {{KA4_0}}, against {{KA4_0_SF}} for the one-sample sign-flip test, and power only {{KA4_07}} at ke0 = 0.7 per h and {{KA4_035}} at 0.35 per h. A cohort this size cannot rule a delay in or out; pooling the active cohorts, as the C-QTc model does, gives the 32-participant rows.</li>
    <li><strong>KA5, tolerance.</strong> E = 4 C - 3 M with dM/dt = 0.35 (C - M) produces clockwise loops (noise-free area {{NF_TOL}} ms). The one-sided test rejects in {{KA5_ONE}} and the two-sided test in {{KA5_TWO}}.</li>
    <li><strong>The tmax gap rule</strong> fires in {{KA1_TI}} (individual peaks) and {{KA1_TM}} (mean profile) of trials with no delay, and in {{K07_TI}} and {{K07_TM}} at ke0 = 0.7 per h, where the area test rejects in {{K07}}. In a single SAD cohort of 6 with no delay it fires in {{KA4_TI}} and {{KA4_TM}}. It is reported beside the test, not used as the decision.</li>
  </ul>
  <figure class="f1">
{{F1}}
    <figcaption>F1. Rejection rate of the one-sided placebo-adjusted area test against ke0 (linear model; the x position is the equilibration half-life ln 2 / ke0, with the direct effect, ke0 = &#8734;, at 0). Whiskers are exact 95% intervals; hover a point for its value. Standalone file: <a href="out/f1_rejection_vs_ke0.svg">out/f1_rejection_vs_ke0.svg</a>.</figcaption>
  </figure>
  <p class="legend-inline"><span class="key k1"></span>32 active + 8 placebo <span class="key k1d"></span>32 active + 32 placebo <span class="key k2"></span>6 active (one SAD cohort) + 8 placebo</p>
{{T1}}

  <h2 id="diurnal">Diurnal confound and the Day -1 check</h2>
  <p>QTc has a daily rhythm. The time-matched placebo correction removes the part that active and placebo participants share: every simulated trial carries the common 4 ms rhythm above, and it never reaches ddQTcF (the tests check this to 1e-12). A time pattern the active participants do not share with the placebo group stays in ddQTcF, for example when a cohort's ECGs fall at different clock times from those of the placebo participants it is compared with. It can fake a loop or hide one, depending on where its peak falls relative to tmax. <strong>NC1</strong> adds 3 sin(2&pi;(t + phi)/24) ms to the active participants only, on Day 1 and Day -1, under the linear direct-effect model: the one-sided test rejects in {{NC0}} of trials at phi = 0 h, {{NC18}} at phi = 18 h and {{NC6}} at phi = 6 h (a clockwise artifact; two-sided {{NC6_2}}), against {{KA1}} without it. This is why the SAP requires a time-matched placebo correction from participants studied alongside the active ones.</p>
  <p><strong>NC2, the Day -1 check.</strong> Pair each active participant's Day -1 time-matched QTcF (no drug, centered within the participant, minus the placebo group's centered Day -1 mean, as on Day 1) with that participant's Day 1 x<sub>j</sub>, compute the same signed area and test it the same way, two-sided. With no drug on Day -1, any loop it shows comes from timing alone. Without a residual pattern it keeps nominal size: {{KA1_D1}}. A one-sample sign-flip test of the same areas rejects in {{KA1_D1_SF}}, too often for the same reason as on Day 1. It is a weak detector. It flags the pattern in {{NC18_D1}} of trials at phi = 18 h, where the Day 1 one-sided test rejects in {{NC18}}, and in {{NC6_D1}} at phi = 6 h. At phi = 0 h the primary one-sided Day 1 test is inflated to {{NC0}}, {{NC0_X}} times nominal, but the Day -1 check flags the pattern in only {{NC0_D1}} of trials, so it misses most trials of that kind; at phi = 12 h it flags {{NC12_D1}}. A clean Day -1 check does not rule a residual time pattern out.</p>
  <div class="tblwrap"><table class="oc nc stack"><caption>Residual time pattern (3 ms amplitude, active participants only) left in ddQTcF: rejection rates of the placebo-adjusted test over 1,000 replicates (MCSE at most 0.016). Noise-free area: the pattern alone against the typical participant's x.</caption>
  <thead><tr><th scope="col">Phase</th><th scope="col" class="num">Noise-free area, ms</th><th scope="col" class="num">Day 1, one-sided</th><th scope="col" class="num">Day 1, two-sided</th><th scope="col" class="num">Day -1 check, two-sided</th></tr></thead>
  <tbody>
{{NCROWS}}
  </tbody></table></div>

  <h2 id="sap-text">SAP text</h2>
  <blockquote class="sap"><p>"Before the C-QTc analysis, delay between concentration and ddQTcF will be assessed by the mean signed area of each participant's concentration-ddQTcF loop, computed on residuals from the prespecified direct-effect model with concentrations scaled to each participant's Cmax. Because ddQTcF subtracts the same time-matched placebo mean from every active participant, the mean area will be tested with a t-test whose standard error adds the variance from the placebo mean (from each placebo participant's signed area, about the placebo mean, against the active participants' mean scaled concentration profile), with Welch-Satterthwaite degrees of freedom; one-sided alpha set in the SAP. If each participant's ddQTcF is corrected by their own placebo period, a participant-level sign-flip test will be used instead (exact for 20 or fewer participants per dose, otherwise 9,999 random sign vectors). The tmax gap will be reported alongside, and a Day -1 pseudo-loop check will be reported. Evidence of delay leads to consideration of an effect-compartment model."</p></blockquote>
  <p>A significant result prompts an effect-compartment model (Sheiner et al. 1979) or a metabolite explanation. It does not replace the C-QTc analysis. A non-significant result in a study with a small placebo group is weak evidence of no delay (KA3, KA4).</p>
  <p><strong>Mock shells</strong> that report it, in the TLF libraries (pseudocode; the SAS twins are not executed, no license):</p>
  <ul class="files">
    <li><a href="../r_tlf_pseudocode/sad/f_cqtc_hysteresis.R">sad/f_cqtc_hysteresis.R</a> &middot; <a href="../sas_tlf_pseudocode/sad/f_cqtc_hysteresis.sas">.sas</a><span class="d">Figure 14.3.5.4: mean ddQTcF against mean concentration in time order, one panel per dose</span></li>
    <li><a href="../r_tlf_pseudocode/sad/t_cqtc_hysteresis.R">sad/t_cqtc_hysteresis.R</a> &middot; <a href="../sas_tlf_pseudocode/sad/t_cqtc_hysteresis.sas">.sas</a><span class="d">Table 14.3.5.5: n active and placebo, A-bar (95% CI), placebo-adjusted p values, tmax gap, model for f, Day -1 check</span></li>
    <li><a href="../r_tlf_pseudocode/mad/f_cqtc_hysteresis.R">mad/f_cqtc_hysteresis.R</a> &middot; <a href="../sas_tlf_pseudocode/mad/f_cqtc_hysteresis.sas">.sas</a><span class="d">Figure 14.3.6.4: the same, for each profile day</span></li>
    <li><a href="../r_tlf_pseudocode/mad/t_cqtc_hysteresis.R">mad/t_cqtc_hysteresis.R</a> &middot; <a href="../sas_tlf_pseudocode/mad/t_cqtc_hysteresis.sas">.sas</a><span class="d">Table 14.3.6.5: by dose and profile day</span></li>
  </ul>

  <h2 id="limits">What it does not do</h2>
  <ul class="facts">
    <li>It does not replace the prespecified C-QTc model, its estimate of the effect at the geometric mean Cmax, or effect-compartment modeling. It decides only whether those need a delay term.</li>
    <li>It is conditional on the form of f. It removes curvature that the prespecified model describes (linear or Emax here); curvature the model misses can still look like a loop, as the raw area does under Emax.</li>
    <li>Its size is not exact. Every active participant's ddQTcF shares the time-matched placebo mean, so the A<sub>i</sub> are dependent and the test is a Welch-type t-test whose size was checked only on these synthetic designs: {{KA1_R}} with 32 active and 8 placebo participants and {{KA4_0_R}} with 6 and 8 (MCSE 0.007). The participant-level sign-flip test is exact only when each participant's ddQTcF uses their own placebo profile; applied to pooled-placebo ddQTcF it rejected in {{KA1_SF_R}} of trials with no delay. With an estimated Emax curve the test was slightly conservative, at {{KA2_EMAX_R}}.</li>
    <li>Its power is set mostly by the placebo group. With 8 placebo participants the placebo-mean term is most of the variance of A-bar (the two groups' areas have a similar spread, so with a quarter as many placebo participants it is about four fifths): power at ke0 = 0.7 per h was {{K07_R}}, against {{K07_P32}} with 32 placebo participants.</li>
    <li>It does not estimate the delay. The area grows with the effect size and depends on the sampling times around tmax; it is a test, not a ke0 estimate.</li>
    <li>The synthetic concentrations have no assay error, every participant shares the nominal grid, placebo and active participants have the same noise SD, and multiple-dose steady state was not simulated. Those were not studied.</li>
    <li>A residual time pattern, a period effect or any other time pattern left in ddQTcF can produce a loop with no drug delay. The Day -1 check detects such a pattern only if Day -1 is processed the same way as Day 1, and even then it often misses it (NC2).</li>
    <li>Nothing here is validated or a regulatory deliverable. The R and SAS shells were written by the same author (no independent double programming), the SAS is not executed, and every dataset is synthetic.</li>
  </ul>

  <h2 id="credit">Provenance and credit</h2>
  <p><strong>Established prior art, credited first.</strong></p>
  <ul class="refs">
    <li>ICH E14 (May 2005), E14 Q&amp;A (R3) (10 Dec 2015; Q5.1 on concentration-response modeling) and E14/S7B Q&amp;As (Step 4, 21 Feb 2022).</li>
    <li>Garnett C, Bonate PL, Dang Q, et al. Scientific white paper on concentration-QTc modeling. <em>J Pharmacokinet Pharmacodyn</em> 2018;45(3):383-397, <a href="https://doi.org/10.1007/s10928-017-9558-5">doi:10.1007/s10928-017-9558-5</a>; correction 45(3):399, <a href="https://doi.org/10.1007/s10928-017-9565-6">doi:10.1007/s10928-017-9565-6</a>.</li>
    <li>Sheiner LB, Stanski DR, Vozeh S, Miller RD, Ham J. Simultaneous modeling of pharmacokinetics and pharmacodynamics: application to d-tubocurarine. <em>Clin Pharmacol Ther</em> 1979;25(3):358-371, <a href="https://doi.org/10.1002/cpt1979253358">doi:10.1002/cpt1979253358</a> (the effect compartment).</li>
    <li>Louizos C, Y&aacute;&ntilde;ez JA, Forrest ML, Davies NM. Understanding the hysteresis loop conundrum in pharmacokinetic/pharmacodynamic relationships. <em>J Pharm Pharm Sci</em> 2014;17(1):34-91, <a href="https://doi.org/10.18433/j3gp53">doi:10.18433/j3gp53</a> (review).</li>
    <li>Zhong Y. Development of hysteresis analysis as a model-independent approach to assess temporal dissociation in pharmacokinetics and pharmacodynamics. PhD dissertation, Washington State University, 2016, <a href="https://hdl.handle.net/2376/12054">hdl:2376/12054</a> (model-independent loop metrics, including the loop centroid).</li>
    <li>Upton RN, Doolette DJ. A quantitative alternative to the hysteresis plot for measurement of drug transit time. <em>J Pharmacol Toxicol Methods</em> 2002;47(1):45-51, <a href="https://doi.org/10.1016/s1056-8719(02)00207-1">doi:10.1016/s1056-8719(02)00207-1</a> (a model-independent area method).</li>
    <li>Wang J, Li W. Test hysteresis in pharmacokinetic/pharmacodynamic relationship with mixed-effect models: an instrumental model approach. <em>J Biopharm Stat</em> 2014;24(2):326-343, <a href="https://doi.org/10.1080/10543406.2013.859149">doi:10.1080/10543406.2013.859149</a> (a formal model-based hysteresis test).</li>
    <li>Cyclicity analysis, where the signed area between two series measures which leads: Baryshnikov Y, Schlafly E. Cyclicity in multivariate time series and applications to functional MRI data. 2016 IEEE 55th Conference on Decision and Control, 1625-1630, <a href="https://doi.org/10.1109/CDC.2016.7798498">doi:10.1109/CDC.2016.7798498</a>; Giusti C, Lee D. Iterated integrals and population time series analysis. <a href="https://arxiv.org/abs/1811.03558">arXiv:1811.03558</a> (2018).</li>
    <li>Welch BL. The generalization of "Student's" problem when several different population variances are involved. <em>Biometrika</em> 1947;34(1-2):28-35, <a href="https://doi.org/10.1093/biomet/34.1-2.28">doi:10.1093/biomet/34.1-2.28</a>; Satterthwaite FE. An approximate distribution of estimates of variance components. <em>Biometrics Bulletin</em> 1946;2(6):110-114, <a href="https://doi.org/10.2307/3002019">doi:10.2307/3002019</a> (the degrees of freedom).</li>
    <li>CiPA Phase 1 ECG biomarker validation study, <a href="https://clinicaltrials.gov/study/NCT03070470">NCT03070470</a>, statistical analysis plan (March 2017), section 5.2.1: a one-sided one-sample Wilcoxon test at the 1% level combined with a time gap of more than 1 hour between tmax and the largest mean effect.</li>
    <li>Registry statistical analysis plans for dedicated QTc studies, <a href="https://clinicaltrials.gov/study/NCT06215521">NCT06215521</a> (section 6.2.1) and <a href="https://clinicaltrials.gov/study/NCT04818229">NCT04818229</a> (section 6.1.1): hysteresis judged from the hysteresis plot (a counterclockwise loop), with a delay of more than 1 hour between the peak ddQTcF and tmax among the conditions.</li>
  </ul>
  <p><strong>What is new here is small:</strong> the area computed on residuals from the prespecified direct-effect model, so the check is conditional on the form the SAP already names; a test whose standard error allows for the time-matched placebo mean that every active participant's ddQTcF shares, with the exact sign-flip test kept for designs where nothing is shared; documented operating characteristics, including where the raw area fails under a curved direct effect, how much a one-sample test overstates significance with a pooled placebo, and how far the placebo group limits power; and the Day -1 confound check, with its weakness shown.</p>
  <p class="small"><strong>Provenance note.</strong> The framing, splitting a lag-1 cross-moment into symmetric and antisymmetric parts with a time-reversal null, follows my author draft <em>Anticipating Network Contagions: When Directedness Outperforms Connectedness</em> (with the editor at Applied Network Science; author draft 5 July 2026; <a href="https://github.com/patrickiben/directed-asymmetry-contagion">github.com/patrickiben/directed-asymmetry-contagion</a>).</p>

  <h2 id="rerun">Rerun it</h2>
<pre><code>Rscript cqtc_hysteresis/R/run_oc.R        # from the repository root; about 3 minutes; rewrites out/ and this page
Rscript cqtc_hysteresis/tests/test_area.R # geometry, exactness, the placebo-mean identity, known answers and the shell gates
</code></pre>
  <ul class="files">
    <li><a href="R/sim.R">R/sim.R</a><span class="d">data-generating model, with the pooled placebo group</span></li>
    <li><a href="R/area.R">R/area.R</a><span class="d">area, fits, placebo-adjusted t, sign-flip and bootstrap tests, tmax gap</span></li>
    <li><a href="R/run_oc.R">R/run_oc.R</a><span class="d">scenarios, seeds and outputs</span></li>
    <li><a href="tests/test_area.R">tests/test_area.R</a><span class="d">tests</span></li>
    <li><a href="out/oc_results.csv">out/oc_results.csv</a><span class="d">scenario, n active and placebo, seed, method, rejection rate, MCSE, exact 95% interval</span></li>
    <li><a href="out/noise_free_areas.csv">out/noise_free_areas.csv</a><span class="d">noise-free typical-participant areas</span></li>
  </ul>
  <p class="small">Run with {{RVER}}, base R plus nlme (only for the random-intercept comparison in the tests). Two consecutive runs wrote byte-identical files. The direct-effect fits estimate the participant intercepts as fixed effects (profile least squares); because a constant has no area, the intercepts never change A<sub>i</sub>, and the tests compare the Emax result with an nlme random-intercept fit.</p>
</main>
<footer class="site">
  <div class="wrap">
    <p class="fine">Generated by <code>cqtc_hysteresis/R/run_oc.R</code> from code in this repository. Synthetic data only: simulated for this page; not trial data and not a regulatory deliverable. <a href="../index.html">Back to the home page</a>.</p>
  </div>
</footer>
</body>
</html>)---"
