# ---------------------------------------------------------------------------
# logic.R: the screening rules behind TRIALMON, in base R (no Shiny), on SYNTHETIC data.
#
# Every function flags a position for a human reviewer (medical monitor, Safety Review
# Committee). None of them adjudicates a DLT or a Hy's Law case, and none of them makes a
# dose-escalation decision. In a real study the numbers a committee relies on come from
# validated programs on ADaM; this demo is not one of them.
#
# Rules (one definition, used by the app, the Quarto pages, the SRC packet and the tests):
#   Potential Hy's Law (FDA, Drug-Induced Liver Injury: Premarketing Clinical Evaluation, July 2009):
#     ALT or AST >= 3x ULN, AND total bilirubin (TBL) > 2x ULN on or after the day of an
#     aminotransferase (AT) elevation and within `window` days of it (30 by default; an SAP
#     convention). Every draw with ALT or AST >= 3x ULN opens its own window, so a second elevation
#     weeks after the first is screened too; the first draw that qualifies is the one reported.
#     ALP is shown alongside. "ALP < 2x ULN" at that draw is applied only when `alp_convention = TRUE`,
#     as a labeled SAP convention: FDA says only that ALP "should not be substantially elevated".
#   AT elevation needing confirmation: ALT or AST > 3x ULN (strictly greater, as in the FDA text)
#     -> repeat ALT, AST, ALP and TBL within 48 to 72 hours. Not a Hy's Law finding.
#   FDA (2009) discontinuation considerations that these data can show: ALT or AST > 8x ULN;
#     > 5x ULN for more than 2 weeks; > 3x ULN with TBL > 2x ULN in the same draw. (INR and
#     symptoms are not in these data.)
#   eDISH quadrants: peak post-baseline ALT or AST (x ULN) against peak TBL (x ULN), lines at 3x and
#     2x. Peaks need not be concurrent, so the upper-right quadrant is a prompt to check timing.
#   R ratio = (ALT/ULN)/(ALP/ULN) at the reported AT elevation draw (the qualifying one for a
#     potential Hy's Law case, otherwise the first), or at the first draw with ALT >= 3x ULN when
#     only AST reached 3x in that draw: >= 5 hepatocellular, 2 < R < 5 mixed, <= 2 cholestatic.
#   QTcF (ICH E14 categorical analysis; E14/S7B Q&As): post-baseline QTcF > 450, > 480, > 500 ms;
#     change from baseline > 30 and > 60 ms. Screen tiers: RED > 500 or change > 60;
#     AMBER > 480 or change > 30; watch > 450.
#   Lab grades: NCI CTCAE v6.0 by default, v5.0 when the protocol says so (ctcae_grade()).
#   DLT tally against 3+3, shown only as an illustrative rule reference (tpt_state()).
#   Roll-up: worst-of at every level (participant, cohort, study tier, overall), watch included.
#     Never an average.
# ---------------------------------------------------------------------------

SEV_LEVELS <- c("GREEN", "watch", "AMBER", "RED")
sev_rank <- function(x) match(x, SEV_LEVELS)
worst <- function(v) {
  v <- v[!is.na(v)]
  if (!length(v)) return("GREEN")
  SEV_LEVELS[max(sev_rank(v))]
}

trialmon_settings <- function(ctcae = "6.0", hys_window = 30, alp_convention = FALSE, meddra = "29.1") {
  ctcae <- match.arg(as.character(ctcae), c("6.0", "5.0"))
  list(ctcae = ctcae, hys_window = as.numeric(hys_window), alp_convention = isTRUE(alp_convention),
       meddra = as.character(meddra))
}

trialmon_load <- function(dir = NULL) {
  cand <- c(dir, "data", "../data", "trialmon_shiny/data", "../trialmon_shiny/data",
            "sasr_monitoring_wiki/trialmon_shiny/data")
  base <- Find(function(d) file.exists(file.path(d, "adsl.csv")), cand)
  if (is.null(base)) stop("Cannot find adsl.csv (run R/gen_data.R from the app folder first)")
  rd <- function(f) utils::read.csv(file.path(base, f), stringsAsFactors = FALSE, na.strings = "")
  tm <- list(adsl = rd("adsl.csv"), adlb = rd("adlb.csv"), adeg = rd("adeg.csv"), adae = rd("adae.csv"),
             cohorts = rd("cohorts.csv"), kri = rd("study_kri.csv"), notes = rd("notes.csv"))
  tm$adsl$DLTFL[is.na(tm$adsl$DLTFL)] <- ""
  tm
}

# comparisons on 8 significant digits, so 120/40 counts as exactly 3 (as admiral does)
.s <- function(x) signif(x, 8)
.gt <- function(a, b) !is.na(a) & !is.na(b) & .s(a) > .s(b)
.ge <- function(a, b) !is.na(a) & !is.na(b) & .s(a) >= .s(b)
.lt <- function(a, b) !is.na(a) & !is.na(b) & .s(a) < .s(b)

r_pattern <- function(r) ifelse(is.na(r), NA_character_,
  ifelse(.ge(r, 5), "hepatocellular", ifelse(.gt(r, 2), "mixed", "cholestatic")))

# ---- liver ------------------------------------------------------------------
# one row per participant and draw: ALT, AST, ALP and TBL as multiples of ULN
liver_panel <- function(adlb) {
  x <- adlb[adlb$PARAMCD %in% c("ALT", "AST", "ALP", "BILI"), ]
  x$XULN <- x$AVAL / x$ANRHI
  w <- unique(x[, c("USUBJID", "ADY", "AVISIT")])
  kw <- paste(w$USUBJID, w$ADY, w$AVISIT)
  for (p in c("ALT", "AST", "ALP", "BILI")) {
    s <- x[x$PARAMCD == p, ]
    w[[p]] <- s$XULN[match(kw, paste(s$USUBJID, s$ADY, s$AVISIT))]
  }
  w <- w[order(w$USUBJID, w$ADY), ]
  rownames(w) <- NULL
  w
}

liver_one <- function(d, window, alp_convention) {
  post <- d[d$ADY > 1, ]
  at <- pmax(post$ALT, post$AST, na.rm = TRUE)
  out <- list(USUBJID = d$USUBJID[1],
    peak_alt = max(post$ALT, na.rm = TRUE), peak_ast = max(post$AST, na.rm = TRUE),
    peak_at = max(at, na.rm = TRUE), peak_tbl = max(post$BILI, na.rm = TRUE),
    peak_alp = max(post$ALP, na.rm = TRUE),
    at3_day = NA_real_, at3_value = NA_real_, alp_at3 = NA_real_, r_at3 = NA_real_,
    tbl_day = NA_real_, tbl_at_hit = NA_real_, hys = FALSE, hys_quadrant_only = FALSE,
    at3x_day = NA_real_, at3x_value = NA_real_, repeat_day = NA_real_, repeat_at = NA_real_,
    stop_reason = "")
  i3 <- which(.ge(post$ALT, 3) | .ge(post$AST, 3))
  if (length(i3)) {
    # every AT elevation opens its own window: TBL > 2x ULN from that day to `window` days later
    hits <- lapply(i3, function(i) which(post$ADY >= post$ADY[i] & post$ADY <= post$ADY[i] + window &
                                         .gt(post$BILI, 2)))
    has_tbl <- lengths(hits) > 0
    alp_ok <- if (alp_convention) .lt(post$ALP[i3], 2) else rep(TRUE, length(i3))
    k <- which(has_tbl & alp_ok)[1]            # the first elevation that qualifies
    if (is.na(k)) k <- which(has_tbl)[1]       # TBL in a window, but the ALP option excluded it
    if (is.na(k)) k <- 1                       # no TBL > 2x ULN in any window: the first elevation
    i <- i3[k]
    out$at3_day <- post$ADY[i]; out$at3_value <- at[i]; out$alp_at3 <- post$ALP[i]
    ia <- if (.ge(post$ALT[i], 3)) i else which(.ge(post$ALT, 3))[1]
    if (!is.na(ia)) out$r_at3 <- post$ALT[ia] / post$ALP[ia]
    if (has_tbl[k]) {
      j <- hits[[k]][1]
      out$tbl_day <- post$ADY[j]; out$tbl_at_hit <- post$BILI[j]
      out$hys <- alp_ok[k]
    }
  }
  out$hys_quadrant_only <- !out$hys & .ge(out$peak_at, 3) & .gt(out$peak_tbl, 2)
  ix <- which(.gt(post$ALT, 3) | .gt(post$AST, 3))
  if (length(ix)) {
    dx <- post$ADY[ix[1]]
    out$at3x_day <- dx; out$at3x_value <- at[ix[1]]
    full <- which(post$ADY > dx & !is.na(post$ALT) & !is.na(post$AST) & !is.na(post$ALP) & !is.na(post$BILI))
    if (length(full)) { out$repeat_day <- post$ADY[full[1]]; out$repeat_at <- at[full[1]] }
  }
  # FDA (2009) discontinuation considerations computable from these data
  why <- character(0)
  if (any(.gt(at, 8))) why <- c(why, "ALT or AST > 8x ULN")
  r5 <- rle(.gt(at, 5)); ends <- cumsum(r5$lengths); starts <- ends - r5$lengths + 1
  if (any(r5$values & (post$ADY[ends] - post$ADY[starts] > 14))) why <- c(why, "ALT or AST > 5x ULN for more than 2 weeks")
  if (any(.gt(at, 3) & .gt(post$BILI, 2))) why <- c(why, "ALT or AST > 3x ULN with TBL > 2x ULN in the same draw")
  out$stop_reason <- paste(why, collapse = "; ")
  as.data.frame(out, stringsAsFactors = FALSE)
}

# per-participant hepatic screen (the potential Hy's Law definition is in the header)
hys_screen <- function(adlb, window = 30, alp_convention = FALSE) {
  lp <- liver_panel(adlb)
  out <- do.call(rbind, lapply(split(lp, lp$USUBJID), liver_one, window = window, alp_convention = alp_convention))
  out$pattern <- r_pattern(out$r_at3)
  out$quadrant <- ifelse(.ge(out$peak_at, 3) & .gt(out$peak_tbl, 2), "Upper right: AT >= 3x and TBL > 2x",
                  ifelse(.ge(out$peak_at, 3), "Lower right: AT >= 3x, TBL <= 2x",
                  ifelse(.gt(out$peak_tbl, 2), "Upper left: TBL > 2x, AT < 3x", "Lower left: below both lines")))
  out$repeat_gap <- out$repeat_day - out$at3x_day
  out$sev <- ifelse(out$hys | nzchar(out$stop_reason), "RED", ifelse(!is.na(out$at3x_day), "AMBER", "GREEN"))
  rownames(out) <- NULL
  out
}

# ---- QTcF -------------------------------------------------------------------
qtc_sev <- function(qtcf, chg) {
  ifelse(.gt(qtcf, 500) | .gt(chg, 60), "RED",
  ifelse(.gt(qtcf, 480) | .gt(chg, 30), "AMBER",
  ifelse(.gt(qtcf, 450), "watch", "GREEN")))
}

qtc_screen <- function(adeg) {
  post <- adeg[adeg$ABLFL != "Y" | is.na(adeg$ABLFL), ]
  post <- post[post$ADY >= 1, ]
  out <- do.call(rbind, lapply(split(post, post$USUBJID), function(d) {
    i <- which.max(d$AVAL); j <- which.max(d$CHG)
    data.frame(USUBJID = d$USUBJID[1], base = d$BASE[1], max_qtcf = d$AVAL[i], max_day = d$ADY[i],
               max_chg = d$CHG[j], chg_day = d$ADY[j], stringsAsFactors = FALSE)
  }))
  out$gt450 <- .gt(out$max_qtcf, 450); out$gt480 <- .gt(out$max_qtcf, 480); out$gt500 <- .gt(out$max_qtcf, 500)
  out$chg30 <- .gt(out$max_chg, 30); out$chg60 <- .gt(out$max_chg, 60)
  out$base450 <- .gt(out$base, 450)
  out$sev <- qtc_sev(out$max_qtcf, out$max_chg)
  rownames(out) <- NULL
  out
}

# ---- CTCAE lab grades ---------------------------------------------------------
# v5.0: NCI CTCAE v5.0 (2017-11-27). v6.0: as transcribed in admiral 1.5.0 `atoxgr_criteria_ctcv6`
# (not re-checked here against the NCI v6.0 workbook). Grades come from x ULN, x LLN or fold over
# baseline as each term specifies, never from absolute mg/dL alone. `base` is the participant's
# baseline value (NA when grading the baseline record itself: reference-range criteria only).
CTCAE_TERMS <- list(
  "5.0" = c(ALT = "Alanine aminotransferase increased", AST = "Aspartate aminotransferase increased",
            ALP = "Alkaline phosphatase increased", BILI = "Blood bilirubin increased",
            CREAT = "Creatinine increased", HGB = "Anemia", NEUT = "Neutrophil count decreased",
            PLAT = "Platelet count decreased"),
  "6.0" = c(ALT = "Alanine aminotransferase increased", AST = "Aspartate aminotransferase increased",
            ALP = "Alkaline phosphatase increased", BILI = "Blood bilirubin increased",
            CREAT = "Creatinine increased", HGB = "Anemia", NEUT = "Neutrophil count decreased",
            PLAT = "Thrombocytopenia"))

ctcae_grade <- function(paramcd, aval, anrlo, anrhi, base = NA, version = "6.0") {
  version <- match.arg(as.character(version), c("6.0", "5.0"))
  n <- length(aval); paramcd <- rep_len(paramcd, n); anrlo <- rep_len(anrlo, n)
  anrhi <- rep_len(anrhi, n); base <- rep_len(base, n)
  g <- rep(NA_integer_, n)
  pick <- function(...) {   # first matching condition wins, listed from grade 4 down
    a <- list(...); out <- rep(0L, n)
    done <- rep(FALSE, n)
    for (k in seq(1, length(a), by = 2)) {
      hit <- !done & a[[k]]; out[hit] <- a[[k + 1]]; done <- done | hit
    }
    out
  }
  U <- anrhi; L <- anrlo; B <- base
  bh <- !is.na(B) & .gt(B, U)     # baseline above ULN
  bl <- !is.na(B) & .lt(B, L)     # baseline below LLN
  v6 <- version == "6.0"
  for (p in unique(paramcd)) {
    i <- paramcd == p
    gi <- switch(p,
      ALT = , AST = if (v6) pick(
          !bh & .gt(aval, 20 * U), 4L, bh & .gt(aval, 4 * B), 4L,
          !bh & .gt(aval, 5 * U), 3L,  bh & .gt(aval, 2 * B), 3L,
          !bh & .gt(aval, 3 * U), 2L,  bh & .gt(aval, 1.5 * B), 2L,
          !bh & .gt(aval, U), 1L,      bh & .ge(aval, B), 1L)
        else pick(
          !bh & .gt(aval, 20 * U), 4L, bh & .gt(aval, 20 * B), 4L,
          !bh & .gt(aval, 5 * U), 3L,  bh & .gt(aval, 5 * B), 3L,
          !bh & .gt(aval, 3 * U), 2L,  bh & .gt(aval, 3 * B), 2L,
          !bh & .gt(aval, U), 1L,      bh & .ge(aval, 1.5 * B), 1L),
      BILI = if (v6) pick(
          !bh & .gt(aval, 10 * U), 4L, bh & .gt(aval, 10 * B), 4L,
          !bh & .gt(aval, 3 * U), 3L,  bh & .gt(aval, 2.5 * B), 3L,
          !bh & .gt(aval, 1.5 * U), 2L, bh & .gt(aval, 1.5 * B), 2L,
          !bh & .gt(aval, U), 1L,      bh & .ge(aval, B), 1L)
        else pick(
          !bh & .gt(aval, 10 * U), 4L, bh & .gt(aval, 10 * B), 4L,
          !bh & .gt(aval, 3 * U), 3L,  bh & .gt(aval, 3 * B), 3L,
          !bh & .gt(aval, 1.5 * U), 2L, bh & .gt(aval, 1.5 * B), 2L,
          !bh & .gt(aval, U), 1L,      bh & .gt(aval, B), 1L),
      ALP = if (v6) pick(.gt(aval, U) & (is.na(B) | .gt(aval, B)), 1L)
        else pick(
          !bh & .gt(aval, 20 * U), 4L, bh & .gt(aval, 20 * B), 4L,
          !bh & .gt(aval, 5 * U), 3L,  bh & .gt(aval, 5 * B), 3L,
          !bh & .gt(aval, 2.5 * U), 2L, bh & .gt(aval, 2.5 * B), 2L,
          !bh & .gt(aval, U), 1L,      bh & .ge(aval, 2 * B), 1L),
      # creatinine: v5.0 takes the worse of x ULN and fold over baseline; v6.0 uses fold over
      # baseline only when the baseline is below the LLN
      CREAT = if (v6) pick(
          .gt(aval, 6 * U), 4L,
          (!bl & .gt(aval, 3 * U)) | (bl & .gt(aval, 3 * B)), 3L,
          (!bl & .gt(aval, 1.5 * U)) | (bl & .gt(aval, 1.5 * B)), 2L,
          .gt(aval, U), 1L)
        else pick(
          .gt(aval, 6 * U), 4L,
          .gt(aval, 3 * U) | .gt(aval, 3 * B), 3L,
          .gt(aval, 1.5 * U) | .gt(aval, 1.5 * B), 2L,
          .gt(aval, U), 1L),
      HGB = pick(.lt(aval, 8), 3L, .lt(aval, 10), 2L, .lt(aval, L), 1L),   # g/dL; grade 4 is clinical
      NEUT = if (v6) pick(.lt(aval, 0.1), 4L, .lt(aval, 0.5), 3L, .lt(aval, 1.0), 2L, .lt(aval, 1.5), 1L)
        else pick(.lt(aval, 0.5), 4L, .lt(aval, 1.0), 3L, .lt(aval, 1.5), 2L, .lt(aval, L), 1L),
      PLAT = if (v6) pick(.lt(aval, 10), 4L, .lt(aval, 50), 3L, .lt(aval, 75), 2L, .lt(aval, L), 1L)
        else pick(.lt(aval, 25), 4L, .lt(aval, 50), 3L, .lt(aval, 75), 2L, .lt(aval, L), 1L),
      rep(NA_integer_, n))
    g[i] <- gi[i]
  }
  g[is.na(aval)] <- NA_integer_
  g
}

# baseline grade and worst post-baseline grade, one row per participant and test
lab_grades <- function(adlb, version = "6.0") {
  x <- adlb
  isb <- x$ABLFL == "Y" & !is.na(x$ABLFL)
  x$GRADE <- ctcae_grade(x$PARAMCD, x$AVAL, x$ANRLO, x$ANRHI, ifelse(isb, NA, x$BASE), version)
  key <- unique(x[, c("USUBJID", "PARAMCD")])
  b <- x[isb, ]; p <- x[x$ADY > 1, ]
  key$BGRADE <- b$GRADE[match(paste(key$USUBJID, key$PARAMCD), paste(b$USUBJID, b$PARAMCD))]
  wg <- tapply(p$GRADE, paste(p$USUBJID, p$PARAMCD), max, na.rm = TRUE)
  key$WGRADE <- as.integer(wg[paste(key$USUBJID, key$PARAMCD)])
  key$TERM <- CTCAE_TERMS[[version]][key$PARAMCD]
  key <- key[order(key$PARAMCD, key$USUBJID), ]
  rownames(key) <- NULL
  key
}

# shift counts: baseline grade (rows) by worst post-baseline grade (columns 0 to 4)
lab_shift <- function(adlb, version = "6.0", params = c("ALT", "AST", "BILI", "ALP", "CREAT", "HGB", "NEUT", "PLAT")) {
  g <- lab_grades(adlb, version)
  g <- g[g$PARAMCD %in% params & !is.na(g$WGRADE), ]
  out <- do.call(rbind, lapply(params, function(p) {
    s <- g[g$PARAMCD == p, ]
    do.call(rbind, lapply(sort(unique(s$BGRADE)), function(bg) {
      t <- s[s$BGRADE == bg, ]
      data.frame(PARAMCD = p, TERM = CTCAE_TERMS[[version]][[p]], BGRADE = bg, N = nrow(t),
                 G0 = sum(t$WGRADE == 0), G1 = sum(t$WGRADE == 1), G2 = sum(t$WGRADE == 2),
                 G3 = sum(t$WGRADE == 3), G4 = sum(t$WGRADE == 4), stringsAsFactors = FALSE)
    }))
  }))
  rownames(out) <- NULL
  out
}

# ---- dose escalation (3+3 as an illustrative rule reference) --------------------
# state codes: "accruing" (fewer than 3 evaluable, no DLT), "expand" (1 DLT, fewer than 6
# evaluable), "escalate" (0 of >= 3, or 1 of >= 6: escalation-eligible under the rule),
# "exceeded" (>= 2 DLTs: the dose exceeds the MTD under the rule). The MTD needs 6 treated.
tpt_state <- function(n_dlt, n_eval) {
  ifelse(n_dlt >= 2, "exceeded",
  ifelse(n_dlt == 1 & n_eval < 6, "expand",
  ifelse(n_dlt == 0 & n_eval < 3, "accruing", "escalate")))
}
TPT_TEXT <- c(accruing = "fewer than 3 DLT-evaluable so far",
              expand = "under the rule, expand the cohort to 6",
              escalate = "escalation-eligible under the rule",
              exceeded = "under the rule, the dose exceeds the MTD")
TPT_SEV <- c(accruing = "GREEN", expand = "AMBER", escalate = "GREEN", exceeded = "RED")

dlt_state <- function(tm) {
  s <- tm$adsl; co <- tm$cohorts
  do.call(rbind, lapply(seq_len(nrow(co)), function(i) {
    x <- s[s$COHORT == co$COHORT[i], ]
    n <- nrow(x); ev <- sum(x$DLTEVLFL == "Y"); nd <- sum(x$DLTFL == "Y"); np <- sum(x$DLTADJ == "Pending")
    now <- if (n) tpt_state(nd, ev) else "not dosed"
    ifp <- if (np) tpt_state(nd + np, ev) else now
    sev <- if (!n) "GREEN" else worst(c(TPT_SEV[[now]], TPT_SEV[[ifp]]))
    text <- if (!n) "not dosed" else if (np && ifp != now)
      sprintf("%d of %d confirmed, %d pending adjudication. If not a DLT: %d of %d, %s. If a DLT: %d of %d, %s",
              nd, ev, np, nd, ev, TPT_TEXT[[now]], nd + np, ev, TPT_TEXT[[ifp]])
      else sprintf("%d of %d: %s", nd, ev, TPT_TEXT[[now]])
    data.frame(COHORT = co$COHORT[i], DOSEMG = co$DOSEMG[i], STATUS = co$STATUS[i], N = n,
               EVALUABLE = ev, DLT = nd, PENDING = np, STATE = now, STATE_IF_DLT = ifp,
               sev = sev, text = text, stringsAsFactors = FALSE)
  }))
}

# ---- adverse events ----------------------------------------------------------
# participant counts n (%) by SOC and PT, columns by cohort and total (N = dosed participants)
ae_soc_pt <- function(tm) {
  ae <- tm$adae[tm$adae$TRTEMFL == "Y", ]
  s <- tm$adsl[tm$adsl$SAFFL == "Y", ]
  ae$COHORT <- s$COHORT[match(ae$USUBJID, s$USUBJID)]
  cohs <- unique(s$COHORT)
  Ns <- c(sapply(cohs, function(c) sum(s$COHORT == c)), Total = nrow(s))
  cnt <- function(rows) c(sapply(cohs, function(c) length(unique(rows$USUBJID[rows$COHORT == c]))),
                          Total = length(unique(rows$USUBJID)))
  out <- list(data.frame(SOC = "Any TEAE", PT = "", t(cnt(ae)), check.names = FALSE, stringsAsFactors = FALSE))
  socs <- names(sort(-table(ae$AEBODSYS)))
  socs <- socs[order(-sapply(socs, function(x) length(unique(ae$USUBJID[ae$AEBODSYS == x]))), socs)]
  for (so in socs) {
    a <- ae[ae$AEBODSYS == so, ]
    out[[length(out) + 1]] <- data.frame(SOC = so, PT = "", t(cnt(a)), check.names = FALSE, stringsAsFactors = FALSE)
    pts <- unique(a$AEDECOD)
    pts <- pts[order(-sapply(pts, function(x) length(unique(a$USUBJID[a$AEDECOD == x]))), pts)]
    for (pt in pts) out[[length(out) + 1]] <- data.frame(SOC = so, PT = pt, t(cnt(a[a$AEDECOD == pt, ])),
                                                        check.names = FALSE, stringsAsFactors = FALSE)
  }
  res <- do.call(rbind, out); rownames(res) <- NULL
  attr(res, "N") <- Ns
  res
}

cohort_summary <- function(tm) {
  s <- tm$adsl; ae <- tm$adae[tm$adae$TRTEMFL == "Y", ]
  co <- tm$cohorts
  do.call(rbind, lapply(seq_len(nrow(co)), function(i) {
    x <- s[s$COHORT == co$COHORT[i], ]; a <- ae[ae$USUBJID %in% x$USUBJID, ]
    data.frame(COHORT = co$COHORT[i], DOSEMG = co$DOSEMG[i], STATUS = co$STATUS[i], N = nrow(x),
               DLT_EVAL = sum(x$DLTEVLFL == "Y"), DISC = sum(x$EOTSTT == "DISCONTINUED"),
               ANY_TEAE = length(unique(a$USUBJID)), G3 = length(unique(a$USUBJID[a$AETOXGR >= 3])),
               SAE = length(unique(a$USUBJID[a$AESER == "Y"])),
               REL = length(unique(a$USUBJID[a$AREL %in% c("Related", "Possibly related")])),
               stringsAsFactors = FALSE)
  }))
}

# ---- study tier (merged from the former risk console) --------------------------
kri_level <- function(value, amber, red, worse = "higher") {
  hi <- worse == "higher"
  ifelse(hi & .gt(value, red), "RED", ifelse(hi & .gt(value, amber), "AMBER",
  ifelse(!hi & .lt(value, red), "RED", ifelse(!hi & .lt(value, amber), "AMBER", "GREEN"))))
}

study_signals <- function(tm) {
  k <- tm$kri
  op <- data.frame(ID = k$ID, INDICATOR = k$INDICATOR, CATEGORY = k$CATEGORY, VALUE = k$VALUE, UNIT = k$UNIT,
                   LEVEL = kri_level(k$VALUE, k$AMBER, k$RED, k$WORSE),
                   RULE = ifelse(k$WORSE == "higher", sprintf("AMBER > %s, RED > %s", k$AMBER, k$RED),
                                 sprintf("AMBER < %s, RED < %s", k$AMBER, k$RED)),
                   DETAIL = k$DETAIL, SOURCE = "operational feed (synthetic)", stringsAsFactors = FALSE)
  s <- tm$adsl; ae <- tm$adae
  nsae <- length(unique(ae$USUBJID[ae$AESER == "Y" & ae$TRTEMFL == "Y"]))
  sae_pct <- round(100 * nsae / nrow(s), 1)
  sched <- c("Screening" = -14, "Day 1" = 1, "Day 4" = 4, "Day 8" = 8, "Day 15" = 15, "Day 22" = 22,
             "Day 29" = 29, "Day 43" = 43)
  exp_n <- sum(sapply(s$LSTVISDY, function(d) sum(sched <= d)))
  seen <- unique(tm$adlb[tm$adlb$AVISIT %in% names(sched), c("USUBJID", "AVISIT")])
  miss <- exp_n - nrow(seen)
  miss_pct <- round(100 * miss / exp_n, 1)
  calc <- data.frame(
    ID = c("QTL-SAE", "MISS-LAB"),
    INDICATOR = c("Participants with a treatment-emergent SAE (trial-level acceptable range)",
                  "Scheduled safety-lab visits with no labs"),
    CATEGORY = c("Safety", "Data"), VALUE = c(sae_pct, miss_pct), UNIT = c("% of dosed", "% of visits"),
    LEVEL = c(kri_level(sae_pct, 10, 20), kri_level(miss_pct, 2, 5)),
    RULE = c("AMBER > 10, RED > 20", "AMBER > 2, RED > 5"),
    DETAIL = c(sprintf("%d of %d dosed participants", nsae, nrow(s)),
               sprintf("%d of %d scheduled visits", miss, exp_n)),
    SOURCE = "computed from ADAE / ADLB", stringsAsFactors = FALSE)
  rbind(calc, op)
}

# ---- worklist and worst-of roll-up -------------------------------------------
trialmon_worklist <- function(tm, settings = trialmon_settings(), study = NULL) {
  wl <- list()
  add <- function(tier, id, sev, check, value, rule)
    wl[[length(wl) + 1]] <<- data.frame(tier = tier, id = id, sev = sev, check = check, value = value,
                                        rule = rule, stringsAsFactors = FALSE)
  h <- hys_screen(tm$adlb, settings$hys_window, settings$alp_convention)
  alp_txt <- if (settings$alp_convention) " and ALP < 2x ULN (SAP convention)" else ""
  for (j in which(h$hys)) add("Participant", h$USUBJID[j], "RED", "Potential Hy's Law",
      sprintf("AT %.1fx ULN on Day %d; TBL %.1fx ULN on Day %d; ALP %.1fx ULN then; R %.1f (%s); peak AT %.1fx ULN",
              h$at3_value[j], h$at3_day[j], h$tbl_at_hit[j], h$tbl_day[j], h$alp_at3[j], h$r_at3[j], h$pattern[j],
              h$peak_at[j]),
      sprintf("ALT or AST >= 3x ULN and TBL > 2x ULN on or after it within %g days%s", settings$hys_window, alp_txt))
  for (j in which(nzchar(h$stop_reason))) add("Participant", h$USUBJID[j], "RED",
      "FDA (2009) discontinuation consideration", h$stop_reason[j], "for the investigator and medical monitor")
  for (j in which(!is.na(h$at3x_day) & !h$hys)) {
    rep_txt <- if (is.na(h$repeat_day[j])) "no repeat panel in the data" else
      sprintf("first repeat on Day %d (%d days later; AT %.1fx ULN)", h$repeat_day[j], h$repeat_gap[j], h$repeat_at[j])
    add("Participant", h$USUBJID[j], "AMBER", "Aminotransferase > 3x ULN: confirm",
        sprintf("AT %.1fx ULN on Day %d, TBL peak %.1fx ULN; %s", h$at3x_value[j], h$at3x_day[j], h$peak_tbl[j], rep_txt),
        "repeat ALT, AST, ALP and TBL within 48 to 72 hours")
  }
  q <- qtc_screen(tm$adeg)
  qrule <- c(RED = "QTcF > 500 ms or change > 60 ms", AMBER = "QTcF > 480 ms or change > 30 ms",
             watch = "QTcF > 450 ms (watch)")
  for (j in which(q$sev %in% names(qrule))) add("Participant", q$USUBJID[j], q$sev[j], "QTcF (ICH E14 categories)",
      sprintf("%d ms on Day %d (baseline %d; change %d ms)", q$max_qtcf[j], q$max_day[j], q$base[j], q$max_chg[j]),
      qrule[[q$sev[j]]])
  g <- lab_grades(tm$adlb, settings$ctcae)
  g <- g[g$PARAMCD %in% c("CREAT", "HGB", "NEUT", "PLAT") & !is.na(g$WGRADE) & g$WGRADE >= 3 & g$WGRADE > g$BGRADE, ]
  for (j in seq_len(nrow(g))) add("Participant", g$USUBJID[j], if (g$WGRADE[j] >= 4) "RED" else "AMBER",
      sprintf("Lab grade %d or higher", g$WGRADE[j]),
      sprintf("%s grade %d (baseline grade %d)", g$TERM[j], g$WGRADE[j], g$BGRADE[j]),
      sprintf("NCI CTCAE v%s", settings$ctcae))
  ae <- tm$adae[tm$adae$AESER == "Y" & tm$adae$TRTEMFL == "Y", ]
  for (id in unique(ae$USUBJID)) add("Participant", id, "RED", "Serious adverse event",
      paste(ae$AEDECOD[ae$USUBJID == id], collapse = "; "), "investigator-reported seriousness")
  ds <- dlt_state(tm)
  for (j in which(ds$sev != "GREEN")) add("Cohort", paste0(ds$COHORT[j], " (", ds$DOSEMG[j], " mg)"), ds$sev[j],
      "DLT tally against 3+3 (rule reference)", ds$text[j], "the committee adjudicates DLTs and decides")
  st <- if (is.null(study)) study_signals(tm) else study
  for (j in which(st$LEVEL != "GREEN")) add("Study", st$ID[j], st$LEVEL[j], st$INDICATOR[j],
      sprintf("%s %s: %s", st$VALUE[j], st$UNIT[j], st$DETAIL[j]), st$RULE[j])
  if (!length(wl)) return(data.frame(tier = character(0), id = character(0), sev = character(0),
                                     check = character(0), value = character(0), rule = character(0)))
  out <- do.call(rbind, wl)
  out <- out[order(-sev_rank(out$sev), match(out$tier, c("Participant", "Cohort", "Study")), out$id), ]
  rownames(out) <- NULL
  out
}

# worst-of per participant (for the roster, the eDISH colors and the packet)
participant_status <- function(tm, settings = trialmon_settings()) {
  wl <- trialmon_worklist(tm, settings)
  ids <- tm$adsl$USUBJID
  data.frame(USUBJID = ids, status = vapply(ids, function(i)
    worst(wl$sev[wl$tier == "Participant" & wl$id == i]), character(1)),
    stringsAsFactors = FALSE, row.names = NULL)
}

# tiers and overall status: the worst level present wins, so one RED is never diluted, and a
# participant at watch keeps the participant tier off GREEN
trialmon_rollup <- function(tm, settings = trialmon_settings(), study = NULL) {
  wl <- trialmon_worklist(tm, settings, study)
  part <- worst(wl$sev[wl$tier %in% c("Participant", "Cohort")])
  stdy <- worst(wl$sev[wl$tier == "Study"])
  list(participant = part, study = stdy, overall = worst(c(part, stdy)),
       red = sum(wl$sev == "RED"), amber = sum(wl$sev == "AMBER"), watch = sum(wl$sev == "watch"),
       worklist = wl)
}

trialmon_kpis <- function(tm) {
  ae <- tm$adae[tm$adae$TRTEMFL == "Y", ]
  list(n = nrow(tm$adsl), cohorts = length(unique(tm$adsl$COHORT)),
       g3ae = length(unique(ae$USUBJID[ae$AETOXGR >= 3])),
       sae = length(unique(ae$USUBJID[ae$AESER == "Y"])),
       dlt = sum(tm$adsl$DLTFL == "Y"), pending = sum(tm$adsl$DLTADJ == "Pending"))
}

# liver tests by draw for one participant, as x ULN (for the trajectory plot)
liver_trajectory <- function(tm, id) {
  lp <- liver_panel(tm$adlb[tm$adlb$USUBJID == id, ])
  long <- do.call(rbind, lapply(c("ALT", "AST", "ALP", "BILI"), function(p)
    data.frame(ADY = lp$ADY, AVISIT = lp$AVISIT, test = p, xuln = lp[[p]], stringsAsFactors = FALSE)))
  long$test <- factor(long$test, levels = c("ALT", "AST", "ALP", "BILI"), labels = c("ALT", "AST", "ALP", "TBL"))
  long[!is.na(long$xuln), ]
}

# CSV text for a client-side download (no downloadHandler, so the app runs under Shinylive)
as_csv_text <- function(df) {
  con <- textConnection("csv_lines", "w", local = TRUE)
  utils::write.csv(df, con, row.names = FALSE)
  close(con)
  paste(csv_lines, collapse = "\n")
}
