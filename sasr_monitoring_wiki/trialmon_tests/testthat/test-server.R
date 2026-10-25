# The Shiny server, driven headless with shiny::testServer (no browser).

app_env <- function() {
  e <- new.env()
  old <- setwd(APP_DIR); on.exit(setwd(old))
  sys.source("app.R", envir = e)
  e
}
# the value a browser would send for the what-if radio when the page opens
initial_radio <- function(e) {
  html <- as.character(htmltools::renderTags(e$ui)$html)
  radio <- regmatches(html, regexpr('<div id="kri_level"[\\s\\S]*?</div>\\s*</div>', html, perl = TRUE))
  m <- regmatches(radio, regexpr('value="[A-Z]+" checked', radio))
  if (length(m)) sub('value="([A-Z]+)" checked', "\\1", m) else NA_character_   # no choice checked
}

test_that("the study-tier radio starts on the selected indicator's level (no flicker)", {
  e <- app_env()
  html <- as.character(htmltools::renderTags(e$ui)$html)
  first <- e$KRI0
  lvl <- e$STUDY0$LEVEL[e$STUDY0$ID == first]
  expect_equal(first, "SF-RATE")
  expect_equal(lvl, "AMBER")
  expect_equal(initial_radio(e), lvl)
})

test_that("opening the app with its initial inputs changes no indicator", {
  e <- app_env(); first <- e$KRI0; init <- initial_radio(e)
  shiny::testServer(APP_DIR, {
    session$setInputs(kri = first, kri_level = init, ctcae = "6.0", window = 30, alp = FALSE,
                      meddra = "29.1", pid = "CP101-014")
    expect_identical(study(), S0)
    expect_equal(roll()$overall, "RED")
    expect_equal(roll()$study, "AMBER")
  })
})

test_that("what-if: setting an indicator re-rolls the tiers worst-of, and reset restores the feed", {
  shiny::testServer(APP_DIR, {
    session$setInputs(kri = "SF-RATE", kri_level = "AMBER")
    session$setInputs(kri_level = "RED")
    expect_equal(study()$LEVEL[study()$ID == "SF-RATE"], "RED")
    expect_equal(roll()$study, "RED")
    expect_equal(sum(study()$LEVEL != S0$LEVEL), 1)           # only that indicator moved
    for (k in S0$ID) { session$setInputs(kri = k); session$setInputs(kri_level = "GREEN") }
    expect_equal(roll()$study, "GREEN")
    expect_equal(roll()$overall, "RED")                       # the participant tier still carries RED
    session$setInputs(kri_reset = 1)
    expect_identical(study(), S0)
  })
})

test_that("SAP settings flow through: CTCAE version, Hy's Law window, ALP convention", {
  shiny::testServer(APP_DIR, {
    session$setInputs(ctcae = "6.0", window = 30, alp = FALSE, meddra = "29.1")
    expect_false(any(roll()$worklist$id == "CP101-013"))
    session$setInputs(ctcae = "5.0")
    expect_true(any(roll()$worklist$id == "CP101-013"))      # neutrophils grade 3 under v5.0 only
    session$setInputs(window = 5)
    expect_false(liver()$hys[liver()$USUBJID == "CP101-014"])
    session$setInputs(window = 30, alp = TRUE)
    expect_true(liver()$hys[liver()$USUBJID == "CP101-014"])
    session$setInputs(window = NA)                            # a cleared box falls back to 30
    expect_equal(settings()$hys_window, 30)
  })
})

test_that("CP101-009 is AMBER in the running app", {
  shiny::testServer(APP_DIR, {
    session$setInputs(ctcae = "6.0", window = 30, alp = FALSE, pid = "CP101-009")
    expect_equal(pstat()[["CP101-009"]], "AMBER")
    expect_match(output$packet$html, "confirm \\(repeat within 48 to 72 h\\)")
  })
})

test_that("the download is built in the browser from a CSV string (no downloadHandler)", {
  shiny::testServer(APP_DIR, {
    session$setInputs(ctcae = "6.0", window = 30, alp = FALSE)
    expect_null(dl_payload())
    session$setInputs(dl = 1)
    p <- dl_payload()
    expect_equal(p$filename, "trialmon_worklist_CTCAEv6.0.csv")
    expect_equal(p$type, "text/csv")
    back <- utils::read.csv(text = p$content, stringsAsFactors = FALSE)
    expect_equal(back$id, roll()$worklist$id)
  })
})

test_that("Shinylive readiness: allowed packages only, data inside the app folder, no downloadHandler", {
  files <- c(file.path(APP_DIR, "app.R"), list.files(file.path(APP_DIR, "R"), full.names = TRUE))
  code <- unlist(lapply(files, readLines))
  code <- sub("#.*$", "", code)
  pk <- unique(c(unlist(regmatches(code, gregexpr("(?<=library\\()[A-Za-z0-9.]+", code, perl = TRUE))),
                 unlist(regmatches(code, gregexpr("[A-Za-z0-9.]+(?=::)", code, perl = TRUE)))))
  expect_true(all(pk %in% c("shiny", "bslib", "DT", "ggplot2", "utils", "stats", "base")), info = paste(pk, collapse = ", "))
  expect_false(any(grepl("downloadHandler|downloadButton", code)))
  expect_false(any(grepl("\\.\\./", readLines(file.path(APP_DIR, "app.R")))))
  needed <- c("adsl.csv", "adlb.csv", "adeg.csv", "adae.csv", "cohorts.csv", "study_kri.csv", "notes.csv")
  expect_true(all(file.exists(file.path(APP_DIR, "data", needed))))
})
