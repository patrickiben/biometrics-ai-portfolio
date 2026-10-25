# The Hy's Law convention grid: known-answer verdicts for the planted cases, the narrative
# assertions in data/narrative_flags.csv, and agreement with the screening rule in logic.R.

source(file.path(APP_DIR, "R", "hyslaw_grid.R"))
HL <- hyslaw_load(file.path(APP_DIR, "data"))
G <- hyslaw_app_grid(TM, HL)
cell <- function(id, w, a = "ALT or AST", p = "not applied")
  G[G$USUBJID == id, HYS_GRID$code[HYS_GRID$W == w & HYS_GRID$A == a & HYS_GRID$P == p]]

test_that("the grid has 12 cells: 3 windows x 2 aminotransferase definitions x 2 ALP rules", {
  expect_equal(nrow(HYS_GRID), 12)
  expect_equal(sort(unique(HYS_GRID$W)), c(14, 30, 60))
  expect_equal(nrow(unique(HYS_GRID[, c("W", "A", "P")])), 12)
})

test_that("the planted cases give exactly the expected verdicts and cell counts", {
  want <- data.frame(
    USUBJID = sprintf("CP101-%03d", 901:907),
    VERDICT = c("Robust", "Convention-dependent: window", "Convention-dependent: ALP rule",
                "Convention-dependent: aminotransferase definition", "Peak-only artifact", "Not flagged",
                "Convention-dependent: window"),
    N = c(12, 4, 6, 6, 0, 0, 8), REF = c(1, 1, 1, 1, 1, 0, 1), stringsAsFactors = FALSE)
  got <- G[match(want$USUBJID, G$USUBJID), ]
  expect_equal(got$VERDICT, want$VERDICT)
  expect_equal(got$N_FLAGGED, want$N)
  expect_equal(got$REF, want$REF)
  expect_true(all(got$SOURCE == "planted case"))
})

test_that("CP101-902 is flagged only with the 60-day window; CP101-907 hits the inclusive bound", {
  expect_equal(c(cell("CP101-902", 14), cell("CP101-902", 30), cell("CP101-902", 60)), c(0L, 0L, 1L))
  # ALT 3.3x on Day 10 and TBL 2.2x on exactly Day 40: 40 <= 10 + 30, so the 30-day window counts
  expect_equal(c(cell("CP101-907", 14), cell("CP101-907", 30), cell("CP101-907", 60)), c(0L, 1L, 1L))
  late <- make_liver(c(10, 41), alt = c(3.3, 1), tbl = c(1, 2.2))           # one day later: outside
  g <- hyslaw_grid(late)
  expect_equal(g[[HYS_GRID$code[HYS_GRID$W == 30 & HYS_GRID$A == "ALT or AST" & HYS_GRID$P == "not applied"]]], 0L)
  expect_equal(g$N_FLAGGED, 4)
})

test_that("the ALP rule and the aminotransferase definition each move only their own cells", {
  expect_equal(c(cell("CP101-903", 30, p = "ALP < 2x ULN"), cell("CP101-903", 30)), c(0L, 1L))
  expect_equal(c(cell("CP101-904", 30, a = "ALT only"), cell("CP101-904", 30)), c(0L, 1L))
  expect_equal(G$ALP_AT3[G$USUBJID == "CP101-903"], 2.6)                   # ALP shown alongside
})

test_that("every status in data/narrative_flags.csv agrees with the computed verdict", {
  chk <- hyslaw_check_narrative(G, HL$flags)
  expect_equal(nrow(chk), nrow(HL$flags))
  expect_equal(chk$USUBJID[!chk$AGREE], character(0))
  expect_setequal(HL$flags$USUBJID, c("CP101-014", "CP101-004", "CP101-009", sprintf("CP101-%03d", 901:907)))
  bad <- HL$flags; bad$STATUS[bad$USUBJID == "CP101-014"] <- "Not flagged"   # an edited narrative
  expect_false(hyslaw_check_narrative(G, bad)$AGREE[bad$USUBJID == "CP101-014"])
})

test_that("the study's cases read as the teaching notes say", {
  v <- setNames(G$VERDICT, G$USUBJID)
  expect_equal(unname(v[c("CP101-014", "CP101-004", "CP101-009")]), c("Robust", "Peak-only artifact", "Not flagged"))
})

test_that("each ALT-or-AST cell equals the console's screening rule at that window and ALP setting", {
  for (src in list(TM$adlb, HL$labs_long)) {
    g <- hyslaw_grid(src)
    for (w in c(14, 30, 60)) for (p in c(FALSE, TRUE)) {
      h <- hys_screen(src, window = w, alp_convention = p)
      code <- HYS_GRID$code[HYS_GRID$W == w & HYS_GRID$A == "ALT or AST" &
                            HYS_GRID$P == if (p) "ALP < 2x ULN" else "not applied"]
      expect_equal(g[[code]], as.integer(h$hys[match(g$USUBJID, h$USUBJID)]), info = sprintf("W %d, ALP %s", w, p))
    }
    h <- hys_screen(src)
    expect_equal(g$REF, as.integer(grepl("^Upper right", h$quadrant[match(g$USUBJID, h$USUBJID)])))
  }
})

test_that("the planted cases live only in labs_long.csv, with background draws inside the ranges", {
  ids <- unique(HL$labs_long$USUBJID)
  expect_equal(sort(ids), sprintf("CP101-%03d", 901:907))
  expect_false(any(ids %in% TM$adsl$USUBJID))
  expect_false(any(ids %in% TM$adlb$USUBJID))
  expect_equal(nrow(TM$adsl), 18)
  ll <- HL$labs_long
  b <- ll[ll$ABLFL %in% "Y", ]
  expect_equal(nrow(b), 7 * 4)                                             # one baseline panel each
  expect_true(all(b$AVAL >= b$ANRLO & b$AVAL <= b$ANRHI))
  expect_true(all(ll$AVAL >= ll$ANRLO))                                    # nothing below the LLN
  expect_equal(sum(ll$AVAL > ll$ANRHI), 30)                                # only planted draws exceed the ULN
})

test_that("the label says potential Hy's Law and names the SAP conventions", {
  expect_match(HYS_GRID_LABEL, "potential Hy's Law", ignore.case = TRUE)
  expect_match(HYS_GRID_LABEL, "SAP")
  expect_match(HYS_GRID_LABEL, "without initial findings of cholestasis")
})

test_that("the console's Convention grid card renders the matrix, the reference column and the note", {
  e <- new.env(); old <- setwd(APP_DIR); sys.source("app.R", envir = e); setwd(old)
  html <- as.character(htmltools::renderTags(e$ui)$html)
  expect_match(html, "Convention grid", fixed = TRUE)
  expect_match(html, "potential Hy&#39;s Law|potential Hy's Law")
  expect_equal(nrow(e$GRID0), 10)
  shiny::testServer(APP_DIR, {
    session$setInputs(ctcae = "6.0", window = 30, alp = FALSE, meddra = "29.1", pid = "CP101-014")
    tbl <- output$grid_tbl
    expect_match(tbl, "screening display, not a grid cell", fixed = TRUE)
    expect_match(tbl, "Convention-dependent: aminotransferase definition", fixed = TRUE)
    expect_match(output$grid_note$html, "Window 30 days, AT&quot;|Window 30 days, AT\"")
    session$setInputs(window = 45, alp = TRUE)
    expect_match(output$grid_note$html, "no grid column", fixed = TRUE)
  })
})
