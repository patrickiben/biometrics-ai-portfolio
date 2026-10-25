# The shipped synthetic study: each planted case lands where the rules say it should.

h <- hys_screen(TM$adlb)
q <- qtc_screen(TM$adeg)
wl <- trialmon_worklist(TM)
row <- function(id) h[h$USUBJID == id, ]

test_that("the synthetic study has 18 dosed participants in four cohorts, C5 planned", {
  expect_equal(nrow(TM$adsl), 18)
  expect_equal(as.vector(table(TM$adsl$COHORT)), c(3, 3, 6, 6))
  expect_equal(TM$cohorts$STATUS[TM$cohorts$COHORT == "C5"], "Planned; not dosed")
})

test_that("CP101-009 (ALT 4.2x, AST 3.6x, TBL 1.6x ULN) is flagged for confirmation, not green", {
  r <- row("CP101-009")
  expect_equal(c(r$peak_alt, r$peak_ast, r$peak_tbl), c(4.2, 3.6, 1.6))
  expect_false(r$hys)
  expect_equal(r$sev, "AMBER")
  expect_equal(r$repeat_gap, 5)                     # first repeat 5 days later: outside 48 to 72 hours
  x <- wl[wl$id == "CP101-009", ]
  expect_equal(x$check, "Aminotransferase > 3x ULN: confirm")
  expect_match(x$rule, "48 to 72 hours")
  expect_equal(participant_status(TM)$status[participant_status(TM)$USUBJID == "CP101-009"], "AMBER")
})

test_that("CP101-014 is a potential Hy's Law case with the timing and ALP shown", {
  r <- row("CP101-014")
  expect_true(r$hys)
  expect_equal(c(r$at3_day, r$tbl_day), c(15, 22))
  expect_equal(r$alp_at3, 1.1)
  expect_equal(r$pattern, "mixed")
  expect_true(hys_screen(TM$adlb, alp_convention = TRUE)$hys[h$USUBJID == "CP101-014"])
  # each AT elevation opens its own window: with 5 days, the Day 17 repeat (ALT 5.1x) reaches the
  # Day 22 TBL; with 0 days, ALT 5.6x and TBL 3.1x in the same Day 22 draw still qualify
  at_day <- function(w) { x <- hys_screen(TM$adlb, window = w); x$at3_day[x$USUBJID == "CP101-014" & x$hys] }
  expect_equal(c(at_day(30), at_day(5), at_day(0)), c(15, 17, 22))
  expect_true(any(wl$id == "CP101-014" & wl$check == "Potential Hy's Law" & wl$sev == "RED"))
})

test_that("CP101-004 sits in the upper-right quadrant on peaks but is not a potential Hy's Law case", {
  r <- row("CP101-004")
  expect_match(r$quadrant, "^Upper right")
  expect_false(r$hys)
  expect_true(r$hys_quadrant_only)
  expect_equal(r$sev, "AMBER")
  expect_equal(sum(h$hys), 1)
})

test_that("QTcF screens: CP101-018 RED, CP101-006 AMBER, CP101-011 and -012 watch", {
  s <- setNames(q$sev, q$USUBJID)
  expect_equal(unname(s[c("CP101-018", "CP101-006", "CP101-011", "CP101-012")]), c("RED", "AMBER", "watch", "watch"))
  expect_equal(sum(q$gt500), 1)
  expect_equal(sum(q$base450), 2)
  w <- wl[wl$sev == "watch", ]                       # watch is a worklist row, so it reaches the roll-up
  expect_equal(sort(w$id), c("CP101-011", "CP101-012"))
  expect_true(all(w$rule == "QTcF > 450 ms (watch)"))
})

test_that("DLT tally: C3 is 1 of 6, C4 is 1 of 6 with CP101-018 pending adjudication", {
  d <- dlt_state(TM)
  expect_equal(d$STATE[d$COHORT == "C3"], "escalate")
  c4 <- d[d$COHORT == "C4", ]
  expect_equal(c(c4$DLT, c4$EVALUABLE, c4$PENDING), c(1, 6, 1))
  expect_equal(c(c4$STATE, c4$STATE_IF_DLT), c("escalate", "exceeded"))
  expect_equal(d$STATE[d$COHORT == "C5"], "not dosed")
})

test_that("the CTCAE version changes the grade where v5.0 and v6.0 differ", {
  g5 <- lab_grades(TM$adlb, "5.0"); g6 <- lab_grades(TM$adlb, "6.0")
  pick <- function(g, id, p) g$WGRADE[g$USUBJID == id & g$PARAMCD == p]
  expect_equal(c(pick(g5, "CP101-013", "NEUT"), pick(g6, "CP101-013", "NEUT")), c(3L, 2L))
  expect_equal(c(pick(g5, "CP101-011", "CREAT"), pick(g6, "CP101-011", "CREAT")), c(2L, 1L))
  expect_equal(c(pick(g5, "CP101-017", "CREAT"), pick(g6, "CP101-017", "CREAT")), c(2L, 2L))
  expect_true(any(trialmon_worklist(TM, trialmon_settings(ctcae = "5.0"))$id == "CP101-013"))
  expect_false(any(wl$id == "CP101-013"))
  expect_equal(unique(g6$TERM[g6$PARAMCD == "PLAT"]), "Thrombocytopenia")
})

test_that("lab shift counts add up to the participants with post-baseline values", {
  s <- lab_shift(TM$adlb)
  expect_true(all(s$N == s$G0 + s$G1 + s$G2 + s$G3 + s$G4))
  expect_true(all(tapply(s$N, s$PARAMCD, sum) == 18))
})

test_that("AEs are counted once per participant per row, with N = dosed participants", {
  a <- ae_soc_pt(TM)
  expect_equal(unname(attr(a, "N")), c(3, 3, 6, 6, 18))
  expect_equal(a$Total[a$SOC == "Any TEAE"], length(unique(TM$adae$USUBJID)))
  inv <- a[a$SOC == "Investigations" & a$PT == "", ]
  expect_equal(inv$Total, length(unique(TM$adae$USUBJID[TM$adae$AEBODSYS == "Investigations"])))
  expect_true(all(TM$adae$AEBODSYS[TM$adae$AEDECOD %in% c("Nausea", "Diarrhoea")] == "Gastrointestinal disorders"))
  expect_true(all(TM$adae$AEBODSYS[TM$adae$AEDECOD == "Fatigue"] == "General disorders and administration site conditions"))
})

test_that("the study tier carries the former risk console's indicators, with no placeholder signals", {
  s <- study_signals(TM)
  expect_setequal(s$ID, c("QTL-SAE", "MISS-LAB", "SF-RATE", "ENROLL", "QRY-AGE", "PROTDEV", "DATA-LAG"))
  expect_equal(s$LEVEL[s$ID == "SF-RATE"], "AMBER")
  expect_equal(s$LEVEL[s$ID == "QTL-SAE"], "GREEN")
  expect_equal(kri_level(c(10, 10.1, 20.1), 10, 20), c("GREEN", "AMBER", "RED"))
  expect_equal(kri_level(c(-15, -16, -31), -15, -30, "lower"), c("GREEN", "AMBER", "RED"))
})

test_that("overall status and tiers", {
  r <- trialmon_rollup(TM)
  expect_equal(c(r$participant, r$study, r$overall), c("RED", "AMBER", "RED"))
  expect_equal(c(r$red, r$amber, r$watch), c(sum(wl$sev == "RED"), sum(wl$sev == "AMBER"), 2))
  expect_equal(wl$sev[1], "RED")
  expect_equal(tail(wl$sev, 2), c("watch", "watch"))
  expect_true(all(diff(sev_rank(wl$sev)) <= 0))     # ranked RED first
})

test_that("the worklist CSV text round-trips", {
  back <- utils::read.csv(text = as_csv_text(wl), stringsAsFactors = FALSE)
  expect_equal(nrow(back), nrow(wl))
  expect_equal(back$id, wl$id)
})
