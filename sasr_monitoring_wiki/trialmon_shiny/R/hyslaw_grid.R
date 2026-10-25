# ---------------------------------------------------------------------------
# hyslaw_grid.R: potential Hy's Law under every combination of three SAP conventions, on
# SYNTHETIC data. A structured sensitivity analysis of SAP conventions, not a new rule; every
# flag is a position for a reviewer, and nothing here adjudicates a case.
#
# Needs logic.R first (liver_panel() and the 8-significant-digit comparisons .ge, .gt, .lt).
#
# For participant i, the post-baseline draws j (study day t_ij > 1) carry ALT (a), AST (s),
# total bilirubin (b) and ALP (p) as multiples of ULN. Cell (W, A, P) flags the participant when
# there are draws j and j' with
#     AT_ij >= 3,   t_ij <= t_ij' <= t_ij + W,   b_ij' > 2,   and (P not applied, or p_ij < 2),
# where AT_ij = max(a_ij, s_ij) under "ALT or AST" and a_ij under "ALT only".
#   W  window after the aminotransferase draw: 14, 30 or 60 days
#   A  aminotransferase definition: ALT or AST; ALT only
#   P  ALP rule: ALP < 2x ULN at the aminotransferase draw; not applied
# 3 x 2 x 2 = 12 cells. The window and the ALP rule are SAP conventions: FDA's July 2009 DILI
# guidance requires TBL on or after the aminotransferase elevation and says only "without
# initial findings of cholestasis".
#
# Reference column, shown but not a grid cell: peak versus peak (peak ALT or AST >= 3x ULN and
# peak TBL > 2x ULN, not necessarily on the same day), the eDISH upper-right quadrant.
#
# Verdict rule (fixed before the known-answer cases were planted):
#   Robust                 flagged in 12 of 12 cells
#   Convention-dependent   flagged in 1 to 11 cells; names each factor for which two cells that
#                          differ only in that factor disagree
#   Not flagged            0 of 12, and not flagged in the reference column
#   Peak-only artifact     0 of 12, but flagged in the reference column
# data/narrative_flags.csv states the verdict each narrative implies;
# hyslaw_check_narrative() lists any disagreement and the tests fail on one.
# ---------------------------------------------------------------------------

HYS_GRID <- expand.grid(P = c("ALP < 2x ULN", "not applied"), A = c("ALT or AST", "ALT only"),
                        W = c(14, 30, 60), stringsAsFactors = FALSE)[, c("W", "A", "P")]
HYS_GRID$code <- sprintf("W%d_%s_%s", HYS_GRID$W, ifelse(HYS_GRID$A == "ALT only", "ALT", "AT"),
                         ifelse(HYS_GRID$P == "not applied", "noALP", "ALP2"))
HYS_FACTORS <- c(window = "W", "aminotransferase definition" = "A", "ALP rule" = "P")

# the card's label: results are potential Hy's Law flags, with ALP shown alongside
HYS_GRID_LABEL <- paste(
  "Potential Hy's Law under 12 combinations of SAP conventions: the window after the aminotransferase",
  "draw (14, 30 or 60 days), the aminotransferase definition (ALT or AST, or ALT only) and the ALP rule",
  "(ALP < 2x ULN at that draw, or not applied). ALP is shown alongside. The window and the ALP rule are SAP",
  "conventions: FDA's July 2009 DILI guidance requires total bilirubin on or after the aminotransferase",
  "elevation and says only \"without initial findings of cholestasis\". A structured sensitivity analysis",
  "of SAP conventions: it flags positions for the medical monitor and does not adjudicate a case.")

# one cell: 1 if some aminotransferase draw opens a window that holds a TBL > 2x ULN draw
hys_grid_cell <- function(post, W, A, P) {
  at <- if (A == "ALT only") post$ALT else pmax(post$ALT, post$AST, na.rm = TRUE)
  idx <- which(.ge(at, 3) & (P == "not applied" | .lt(post$ALP, 2)))
  for (i in idx) {
    if (any(post$ADY >= post$ADY[i] & post$ADY <= post$ADY[i] + W & .gt(post$BILI, 2))) return(1L)
  }
  0L
}

# the verdict from the 12 flags (in HYS_GRID order) and the reference column
hyslaw_verdict <- function(f, ref) {
  n <- sum(f)
  if (n == nrow(HYS_GRID)) return("Robust")
  if (n == 0) return(if (ref == 1) "Peak-only artifact" else "Not flagged")
  g <- HYS_GRID; g$f <- f
  dep <- vapply(HYS_FACTORS, function(fac) {
    rest <- setdiff(HYS_FACTORS, fac)
    any(tapply(g$f, interaction(g[rest], drop = TRUE), function(v) length(unique(v)) > 1))
  }, logical(1))
  paste0("Convention-dependent: ", paste(names(HYS_FACTORS)[dep], collapse = ", "))
}

# one row per participant: the 12 flags, the reference column, the count and the verdict,
# with peak values and the ALP at the first aminotransferase draw >= 3x ULN
hyslaw_grid <- function(adlb, source = "") {
  lp <- liver_panel(adlb)
  rows <- lapply(split(lp, lp$USUBJID), function(d) {
    post <- d[d$ADY > 1, ]
    if (!nrow(post)) return(NULL)
    f <- vapply(seq_len(nrow(HYS_GRID)), function(k)
      hys_grid_cell(post, HYS_GRID$W[k], HYS_GRID$A[k], HYS_GRID$P[k]), integer(1))
    at <- pmax(post$ALT, post$AST, na.rm = TRUE)
    pk <- function(v) if (all(is.na(v))) NA_real_ else max(v, na.rm = TRUE)
    ref <- as.integer(.ge(pk(at), 3) & .gt(pk(post$BILI), 2))
    i3 <- which(.ge(at, 3))[1]
    out <- data.frame(USUBJID = d$USUBJID[1], SOURCE = source, stringsAsFactors = FALSE)
    out[HYS_GRID$code] <- as.list(f)
    out$REF <- ref; out$N_FLAGGED <- sum(f); out$VERDICT <- hyslaw_verdict(f, ref)
    out$PEAK_AT <- pk(at); out$PEAK_TBL <- pk(post$BILI); out$PEAK_ALP <- pk(post$ALP)
    out$AT3_DAY <- if (is.na(i3)) NA_real_ else post$ADY[i3]
    out$ALP_AT3 <- if (is.na(i3)) NA_real_ else post$ALP[i3]
    out
  })
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}

# the planted known-answer cases and the narrative assertions (both in the app's data/ folder)
hyslaw_load <- function(dir = NULL) {
  cand <- c(dir, "data", "../data", "trialmon_shiny/data", "../trialmon_shiny/data",
            "sasr_monitoring_wiki/trialmon_shiny/data")
  base <- Find(function(d) file.exists(file.path(d, "labs_long.csv")), cand)
  if (is.null(base)) stop("Cannot find labs_long.csv (run R/gen_data.R from the app folder first)")
  rd <- function(f) utils::read.csv(file.path(base, f), stringsAsFactors = FALSE, na.strings = "")
  list(labs_long = rd("labs_long.csv"), flags = rd("narrative_flags.csv"))
}

# the grid shown in the app: CP-101 participants with any aminotransferase >= 3x ULN or TBL > 2x ULN
# after baseline, plus every planted case
hyslaw_app_grid <- function(tm, hl) {
  s <- hyslaw_grid(tm$adlb, "CP-101 data")
  s <- s[.ge(s$PEAK_AT, 3) | .gt(s$PEAK_TBL, 2) | s$USUBJID %in% hl$flags$USUBJID, ]
  out <- rbind(s, hyslaw_grid(hl$labs_long, "planted case"))
  rownames(out) <- NULL
  out
}

# each asserted status against the computed verdict
hyslaw_check_narrative <- function(grid, flags) {
  m <- grid[match(flags$USUBJID, grid$USUBJID), ]
  data.frame(USUBJID = flags$USUBJID, ASSERTED = flags$STATUS, COMPUTED = m$VERDICT,
             N_FLAGGED = m$N_FLAGGED, AGREE = !is.na(m$VERDICT) & m$VERDICT == flags$STATUS,
             stringsAsFactors = FALSE)
}
