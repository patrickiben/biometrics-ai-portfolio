# Boundary tests: each rule is checked exactly at, just below and just above its threshold.

test_that("Hy's Law component 1 is ALT or AST >= 3x ULN (exactly 3x counts)", {
  h <- hys_screen(make_liver(c(8, 15), alt = c(3, 1), tbl = c(2.5, 1)))
  expect_true(h$hys)
  h <- hys_screen(make_liver(c(8, 15), alt = c(2.99, 1), tbl = c(2.5, 1)))
  expect_false(h$hys)
  h <- hys_screen(make_liver(c(8, 15), alt = c(1, 1), ast = c(3, 1), tbl = c(2.5, 1)))
  expect_true(h$hys)                          # AST alone qualifies too
})

test_that("TBL must be strictly greater than 2x ULN (exactly 2x does not count)", {
  expect_false(hys_screen(make_liver(c(8, 15), alt = c(4, 4), tbl = c(2, 2)))$hys)
  expect_true(hys_screen(make_liver(c(8, 15), alt = c(4, 4), tbl = c(2, 2.01)))$hys)
})

test_that("floating point: 3.6 mg/dL over a 1.2 ULN is exactly 3x, and 120 over 40 is exactly 3x", {
  d <- make_liver(c(8), alt = 3, tbl = 2.5)
  d$AVAL[d$PARAMCD == "BILI" & d$ADY == 8] <- 3.6
  h <- hys_screen(d)
  expect_true(h$hys)
  expect_equal(r_pattern(3.6 / 1.2 * 2 / 3), "cholestatic")   # 2.0000000000000004 is still 2
})

test_that("timing: TBL > 2x ULN must come on or after the AT elevation, within the window", {
  same_day <- make_liver(c(15), alt = 4, tbl = 2.5)
  expect_true(hys_screen(same_day)$hys)
  before <- make_liver(c(4, 22), alt = c(1, 3.3), tbl = c(2.4, 1.0))       # the CP101-004 pattern
  h <- hys_screen(before)
  expect_false(h$hys)
  expect_true(h$hys_quadrant_only)
  expect_match(h$quadrant, "^Upper right")
  at30 <- make_liver(c(10, 40), alt = c(3.5, 1), tbl = c(1, 2.5))           # 30 days later: inside
  expect_true(hys_screen(at30, window = 30)$hys)
  at31 <- make_liver(c(10, 41), alt = c(3.5, 1), tbl = c(1, 2.5))           # 31 days later: outside
  expect_false(hys_screen(at31, window = 30)$hys)
  expect_true(hys_screen(at31, window = 31)$hys)
})

test_that("a second aminotransferase elevation opens its own window", {
  # ALT 3.2x on Day 4, back to normal, then 4.0x on Day 43 with TBL 2.5x on Day 45: the Day 45 TBL is
  # 41 days after the first elevation but 2 days after the second, so the case qualifies
  d <- make_liver(c(4, 15, 43, 45), alt = c(3.2, 1.0, 4.0, 2.5), tbl = c(0.6, 0.6, 1.0, 2.5))
  h <- hys_screen(d, window = 30)
  expect_true(h$hys)
  expect_equal(c(h$at3_day, h$at3_value, h$tbl_day, h$tbl_at_hit), c(43, 4.0, 45, 2.5))
  expect_equal(h$sev, "RED")
  expect_false(h$hys_quadrant_only)
  expect_false(hys_screen(d, window = 1)$hys)                              # 2 days > a 1-day window
  tm <- TM                                                                 # the same panel in the study
  liver <- c("ALT", "AST", "ALP", "BILI")
  tm$adlb <- rbind(tm$adlb[!(tm$adlb$USUBJID == "CP101-001" & tm$adlb$PARAMCD %in% liver), c("USUBJID", "PARAMCD",
    "AVISIT", "ADY", "AVAL", "ANRLO", "ANRHI", "BASE", "ABLFL")], make_liver(c(4, 15, 43, 45),
    alt = c(3.2, 1.0, 4.0, 2.5), tbl = c(0.6, 0.6, 1.0, 2.5), id = "CP101-001"))
  x <- trialmon_worklist(tm)
  x <- x[x$id == "CP101-001", ]
  expect_true(any(x$check == "Potential Hy's Law" & x$sev == "RED"))
  expect_match(x$value[x$check == "Potential Hy's Law"], "AT 4.0x ULN on Day 43; TBL 2.5x ULN on Day 45")
})

test_that("with the ALP option, each elevation is judged on the ALP in its own draw", {
  d <- make_liver(c(8, 22, 29), alt = c(3.5, 3.5, 1), alp = c(2.5, 1.2, 1), tbl = c(1, 1, 2.5))
  h <- hys_screen(d, alp_convention = TRUE)
  expect_true(h$hys)
  expect_equal(c(h$at3_day, h$alp_at3, h$tbl_day), c(22, 1.2, 29))       # Day 8 had ALP 2.5x: not that one
  expect_equal(hys_screen(d)$at3_day, 8)                                   # without the option, Day 8 qualifies
  d2 <- make_liver(c(8, 22), alt = c(3.5, 1), alp = c(2.5, 1), tbl = c(1, 2.5))
  h2 <- hys_screen(d2, alp_convention = TRUE)
  expect_false(h2$hys)
  expect_equal(c(h2$at3_day, h2$tbl_day), c(8, 22))                       # the timing is still shown
})

test_that("ALP < 2x ULN applies only as the labeled SAP convention", {
  d <- make_liver(c(15, 22), alt = c(4, 4), alp = c(2, 2), tbl = c(1, 2.5))
  expect_true(hys_screen(d, alp_convention = FALSE)$hys)
  expect_false(hys_screen(d, alp_convention = TRUE)$hys)                  # exactly 2x is not < 2x
  d2 <- make_liver(c(15, 22), alt = c(4, 4), alp = c(1.99, 3), tbl = c(1, 2.5))
  expect_true(hys_screen(d2, alp_convention = TRUE)$hys)                  # ALP read at the AT elevation
})

test_that("the confirmation flag uses ALT or AST strictly above 3x ULN", {
  expect_equal(hys_screen(make_liver(c(15), alt = 3, tbl = 1))$sev, "GREEN")    # exactly 3x: no flag
  h <- hys_screen(make_liver(c(15, 17), alt = c(3.01, 2), tbl = c(1, 1)))
  expect_equal(h$sev, "AMBER")
  expect_equal(h$repeat_gap, 2)
  expect_false(h$hys)
})

test_that("FDA discontinuation considerations: > 8x, > 5x for more than 2 weeks, > 3x with TBL > 2x", {
  expect_match(hys_screen(make_liver(c(8), alt = 8.01))$stop_reason, "> 8x")
  expect_equal(hys_screen(make_liver(c(8), alt = 8))$stop_reason, "")
  expect_match(hys_screen(make_liver(c(8, 15, 23), alt = c(5.5, 6, 5.2)))$stop_reason, "more than 2 weeks")
  expect_equal(hys_screen(make_liver(c(8, 15, 22), alt = c(5.5, 6, 5.2)))$stop_reason, "")   # exactly 14 days
  expect_match(hys_screen(make_liver(c(8), alt = 3.1, tbl = 2.1))$stop_reason, "same draw")
})

test_that("R ratio bands: <= 2 cholestatic, 2 < R < 5 mixed, >= 5 hepatocellular", {
  expect_equal(r_pattern(c(2, 2.01, 4.99, 5)), c("cholestatic", "mixed", "mixed", "hepatocellular"))
  h <- hys_screen(make_liver(c(8, 15), alt = c(3, 6), alp = c(1.5, 1), tbl = c(1, 1)))
  expect_equal(h$r_at3, 2)                     # computed at the first draw with ALT >= 3x ULN
  expect_equal(h$pattern, "cholestatic")
})

test_that("QTcF absolute categories: > 450, > 480, > 500 ms (the threshold itself is not over)", {
  expect_equal(qtc_sev(c(450, 451, 480, 481, 500, 501), 0),
               c("GREEN", "watch", "watch", "AMBER", "AMBER", "RED"))
  q <- qtc_screen(rbind(make_qtc(420, c(450, 440), "A"), make_qtc(420, 480, "B"), make_qtc(420, 500, "C")))
  expect_equal(q$gt450, c(FALSE, TRUE, TRUE))
  expect_equal(q$gt480, c(FALSE, FALSE, TRUE))
  expect_equal(q$gt500, c(FALSE, FALSE, FALSE))
})

test_that("QTcF change from baseline: > 30 and > 60 ms (exactly 30 and 60 are not over)", {
  expect_equal(qtc_sev(400, c(30, 31, 60, 61)), c("GREEN", "AMBER", "AMBER", "RED"))
  q <- qtc_screen(rbind(make_qtc(400, 430, "A"), make_qtc(400, 460, "B"), make_qtc(400, 461, "C")))
  expect_equal(q$chg30, c(FALSE, TRUE, TRUE))
  expect_equal(q$chg60, c(FALSE, FALSE, TRUE))
  expect_equal(q$sev, c("GREEN", "AMBER", "RED"))     # a change of exactly 60 ms is still > 30 ms
})

test_that("3+3 reads one DLT against its denominator: 1 of 3 expands, 1 of 6 is escalation-eligible", {
  expect_equal(tpt_state(1, 3), "expand")
  expect_equal(tpt_state(1, 5), "expand")
  expect_equal(tpt_state(1, 6), "escalate")
  expect_equal(tpt_state(0, 3), "escalate")
  expect_equal(tpt_state(0, 2), "accruing")
  expect_equal(tpt_state(2, 3), "exceeded")
  expect_equal(tpt_state(2, 6), "exceeded")
  one_of_three <- dlt_state(with_cohort(TM, "C4", n = 3, n_dlt = 1))
  expect_equal(one_of_three$sev[one_of_three$COHORT == "C4"], "AMBER")
  one_of_six <- dlt_state(with_cohort(TM, "C4", n = 6, n_dlt = 1))
  expect_equal(one_of_six$STATE[one_of_six$COHORT == "C4"], "escalate")
  expect_equal(one_of_six$sev[one_of_six$COHORT == "C4"], "GREEN")
})

test_that("a pending adjudication shows both outcomes and is ranked by the worse one", {
  d <- dlt_state(with_cohort(TM, "C4", n = 6, n_dlt = 1, n_pending = 1))
  r <- d[d$COHORT == "C4", ]
  expect_equal(c(r$STATE, r$STATE_IF_DLT, r$sev), c("escalate", "exceeded", "RED"))
  expect_match(r$text, "If not a DLT: 1 of 6.*If a DLT: 2 of 6")
})

test_that("CTCAE creatinine: v5.0 takes the worse of x ULN and fold over baseline", {
  g5 <- function(aval, base) ctcae_grade("CREAT", aval, 0.6, 1.2, base, "5.0")
  expect_equal(g5(1.21, 0.8), 2L)     # 1.51x baseline, 1.01x ULN
  expect_equal(g5(1.20, 0.8), 0L)     # exactly 1.5x baseline and exactly ULN
  expect_equal(g5(1.80, 0.8), 2L)     # exactly 1.5x ULN is grade 1 on ULN, but 2.25x baseline is grade 2
  expect_equal(g5(2.20, 0.7), 3L)     # 3.14x baseline
  expect_equal(g5(7.21, 0.8), 4L)     # > 6x ULN
})

test_that("CTCAE creatinine: v6.0 uses fold over baseline only when the baseline is below the LLN", {
  g6 <- function(aval, base) ctcae_grade("CREAT", aval, 0.6, 1.2, base, "6.0")
  expect_equal(g6(1.21, 0.8), 1L)     # baseline normal: x ULN only
  expect_equal(g6(1.80, 0.8), 1L)     # exactly 1.5x ULN
  expect_equal(g6(1.81, 0.8), 2L)
  expect_equal(g6(2.20, 0.7), 2L)     # 1.83x ULN
  expect_equal(g6(0.76, 0.5), 2L)     # baseline below LLN: > 1.5x baseline
  expect_equal(g6(0.75, 0.5), 0L)     # exactly 1.5x baseline
  expect_equal(g6(1.51, 0.5), 3L)     # > 3x baseline
})

test_that("CTCAE ALT, bilirubin, ALP, neutrophils, platelets and hemoglobin at their cut points", {
  alt <- function(x, base = 20, v = "6.0") ctcae_grade("ALT", x, 7, 40, base, v)
  expect_equal(alt(c(40, 41, 120, 121, 200, 201, 800, 801)), c(0L, 1L, 1L, 2L, 2L, 3L, 3L, 4L))
  expect_equal(alt(c(75, 76, 100, 101, 200, 201), base = 50), c(1L, 2L, 2L, 3L, 3L, 4L))      # v6.0, baseline > ULN
  expect_equal(alt(c(74, 75, 150, 151), base = 50, v = "5.0"), c(0L, 1L, 1L, 2L))               # v5.0, baseline > ULN
  bili <- function(x, v) ctcae_grade("BILI", x, 0.2, 1.2, 0.6, v)
  expect_equal(bili(c(1.8, 1.81, 3.6, 3.61), "5.0"), c(1L, 2L, 2L, 3L))
  expect_equal(ctcae_grade("ALP", 720, 40, 120, 80, "5.0"), 3L)
  expect_equal(ctcae_grade("ALP", c(720, 100), 40, 120, 80, "6.0"), c(1L, 0L))                 # v6.0: grade 1 only
  neut <- function(x, v) ctcae_grade("NEUT", x, 1.8, 7.5, 3.5, v)
  expect_equal(neut(c(1.5, 0.9, 0.5, 0.49), "5.0"), c(1L, 3L, 3L, 4L))
  expect_equal(neut(c(1.5, 0.9, 0.5, 0.09), "6.0"), c(0L, 2L, 2L, 4L))
  plat <- function(x, v) ctcae_grade("PLAT", x, 150, 400, 250, v)
  expect_equal(plat(c(25, 24, 9), "5.0"), c(3L, 4L, 4L))
  expect_equal(plat(c(25, 24, 9), "6.0"), c(3L, 3L, 4L))
  expect_equal(ctcae_grade("HGB", c(12, 10, 9.99, 8, 7.9), 12, 17, 14), c(0L, 1L, 2L, 2L, 3L))
})

test_that("the eDISH axes widen so the most severe participant stays on the plot", {
  h <- hys_screen(TM$adlb)
  expect_equal(edish_limits(h), list(x = c(.2, 10), y = c(.2, 6)))         # the shipped data fit the default
  h$peak_at[h$USUBJID == "CP101-014"] <- 12; h$peak_tbl[h$USUBJID == "CP101-014"] <- 7
  lim <- edish_limits(h)
  expect_true(all(h$peak_at >= lim$x[1] & h$peak_at <= lim$x[2]))
  expect_true(all(h$peak_tbl >= lim$y[1] & h$peak_tbl <= lim$y[2]))
  h$peak_at[1] <- 0.1
  expect_lt(edish_limits(h)$x[1], 0.1)
  rh <- new.env(); sys.source(file.path(APP_DIR, "..", "trialmon_quarto", "_report-helpers.R"), envir = rh)
  b <- ggplot2::ggplot_build(rh$edish_plot(h, rh$TM_LOOK$light))
  pts <- b$data[[which(vapply(b$plot$layers, function(l) inherits(l$geom, "GeomPoint"), logical(1)))]]
  expect_equal(sum(is.finite(pts$x) & is.finite(pts$y)), 18)              # every participant is drawn
})

test_that("watch rolls up: with only QTcF > 450 ms left, the participant tier is watch, not GREEN", {
  keep <- c("CP101-001", "CP101-002", "CP101-003", "CP101-011", "CP101-012")
  tm <- TM
  for (d in c("adsl", "adlb", "adeg", "adae")) tm[[d]] <- tm[[d]][tm[[d]]$USUBJID %in% keep, ]
  green_study <- study_signals(tm); green_study$LEVEL <- "GREEN"
  r <- trialmon_rollup(tm, study = green_study)
  expect_equal(c(r$participant, r$study, r$overall), c("watch", "GREEN", "watch"))
  expect_equal(c(r$red, r$amber, r$watch), c(0, 0, 2))
  expect_equal(sort(r$worklist$id), c("CP101-011", "CP101-012"))
  expect_equal(participant_status(tm)$status, c("GREEN", "GREEN", "GREEN", "watch", "watch"))
})

test_that("roll-up is worst-of: a single RED is never diluted", {
  expect_equal(worst(c(rep("GREEN", 20), "RED")), "RED")
  expect_equal(worst(c("watch", "GREEN")), "watch")
  expect_equal(worst(character(0)), "GREEN")
  green_study <- study_signals(TM); green_study$LEVEL <- "GREEN"
  r <- trialmon_rollup(TM, study = green_study)
  expect_equal(c(r$participant, r$study, r$overall), c("RED", "GREEN", "RED"))
})
