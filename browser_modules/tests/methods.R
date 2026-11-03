# Execute from the repository root: Rscript browser_modules/tests/methods.R
# Native parity / adversarial tests; actual webR execution is checked separately.
source("browser_modules/methods/methods.R")
root <- normalizePath(".")
work <- tempfile("methods-qc-")
dir.create(work)
expect_error <- function(expr, pattern = NULL) {
  e <- tryCatch(
    {
      force(expr)
      NULL
    },
    error = identity
  )
  stopifnot(inherits(e, "error"))
  if (!is.null(pattern)) stopifnot(grepl(pattern, conditionMessage(e)))
  invisible(e)
}
config <- function(kind) {
  x <- methods_defaults(kind)
  x$confirmed <- TRUE
  x
}
run <- function(x, label) x <- methods_run(x, root, file.path(work, label))
equal <- function(x, y, tolerance = 1e-10) stopifnot(isTRUE(all.equal(x, y, tolerance = tolerance, check.attributes = FALSE)))
stopifnot(!"PKNCA" %in% loadedNamespaces())
cold_options <- options()
cold <- run(config("study"), "study-first")
stopifnot(identical(options()[names(cold_options)], cold_options))
default_pknca <- lapply(get(".PKNCA.option.check", asNamespace("PKNCA")), function(check) check(default = TRUE))
stopifnot(identical(PKNCA::PKNCA.options(), default_pknca))
cat("PASS study-first cold session restores initialized PKNCA defaults\n")
for (kind in names(METHOD_LABELS)) {
  x <- methods_defaults(kind)
  expect_error(methods_validate(x, root), "Confirm")
}
for (value in list(NA, NaN, Inf, -1, 1.5, "12", c(12, 14), 13, 302)) {
  x <- config("sandbox")
  x$n <- value
  expect_error(methods_validate(x, root))
}
for (key in c("theta", "washouts")) {
  for (value in list(numeric(), c(1, 1), c(1, NA), Inf, "1", rep(1, 13))) {
    x <- config("carryover")
    x[[key]] <- value
    expect_error(methods_validate(x, root))
  }
}
x <- config("carryover")
x$n <- 300
x$replicates <- 2000
expect_error(methods_validate(x, root), "96,000")
x <- config("cqtc")
x$scenarios <- "not-a-scenario"
expect_error(methods_validate(x, root), "valid")
x <- config("cqtc")
x$seed <- .Machine$integer.max
expect_error(methods_validate(x, root))
set.seed(4321)
seed_before <- .Random.seed
wd_before <- getwd()
opts_before <- getOption("toolkit.sandbox.config")
rng_before <- RNGkind()
a <- run(config("sandbox"), "sandbox")
stopifnot(identical(seed_before, .Random.seed), identical(wd_before, getwd()), identical(opts_before, getOption("toolkit.sandbox.config")), identical(rng_before, RNGkind()))
for (f in list.files("sim_lifecycle/out", pattern = "\\.csv$", full.names = TRUE)) stopifnot(identical(unname(tools::md5sum(f)), unname(tools::md5sum(file.path(a$directory, f)))))
x <- config("sandbox")
x$n <- 24
x$seed <- 77
x$true_gmr <- .9
x$within_cv <- .2
b <- run(x, "sandbox-custom-1")
c <- run(x, "sandbox-custom-2")
equal(b$tables, c$tables)
stopifnot(nrow(b$tables[["Participant data"]]) == 24, !identical(a$tables, b$tables))
cat("PASS sandbox baseline nine CSVs byte-identical; custom settings deterministic; global state restored\n")
x <- config("carryover")
x$replicates <- 20
x$theta <- 1
x$washouts <- c(2, 10)
d <- run(x, "carryover")
z <- d$tables[["Operating characteristics"]]
stopifnot(nrow(z) > 0, all(z$n_rep == 20), all(z$be_rate >= 0 & z$be_rate <= 1), all(z$be_rate_mcse >= 0))
equal(z$bias[1], 0.00753843631065385)
equal(z$be_rate[1], 1)
x$seed <- 2
e <- run(x, "carryover-other-seed")
stopifnot(!identical(d$tables, e$tables))
cat("PASS carryover seeded known answer, full requested rows and changed seed\n")
x <- config("cqtc")
x$replicates <- 20
x$scenarios <- "KA3-k0.7-p32"
x$controls <- FALSE
f <- run(x, "cqtc")
e <- new.env()
for (file in c("sim.R", "area.R", "oc_core.R")) sys.source(file.path("cqtc_hysteresis/R", file), e)
i <- which(vapply(e$SCEN, `[[`, "", "id") == x$scenarios)
e$ALPHA <- .05
e$B_SF <- x$sign_vectors
e$B_BOOT <- x$bootstrap
set.seed(x$seed + i)
m <- t(replicate(x$replicates, e$one_rep(e$SCEN[[i]])))
z <- f$tables[["Operating characteristics"]]
equal(z$rejections, unname(colSums(m)))
stopifnot(all(z$seed == x$seed + i))
equal(e$cp_ci(0, 20)[1, 2], 1 - .025^(1 / 20))
equal(e$cp_ci(20, 20)[1, 1], .025^(1 / 20))
x$scenarios <- c("KA1-p32", x$scenarios)
g <- run(x, "cqtc-multiple")
equal(z, g$tables[[1]][g$tables[[1]]$scenario == "KA3-k0.7-p32", ])
cat("PASS C-QTc canonical per-scenario seeding, subset invariance and exact boundary intervals\n")
PKNCA::PKNCA.options(auc.method = "linear")
pknca_before <- get("options", envir = get(".PKNCAEnv", asNamespace("PKNCA")))
locale_before <- Sys.getlocale("LC_COLLATE")
options_before <- options()
h <- run(config("study"), "study")
stopifnot(identical(pknca_before, get("options", envir = get(".PKNCAEnv", asNamespace("PKNCA")))), identical(locale_before, Sys.getlocale("LC_COLLATE")), identical(options_before, options()))
stopifnot(all(h$tables[["Same-author QC ledger"]]$status == "pass"), nrow(h$tables[["Same-author QC ledger"]]) == 40)
for (file in c("study/04_analysis/be_results.csv", "study/04_analysis/be_supplementary.csv", "study/05_qc/qc_ledger.csv")) equal(read.csv(file), read.csv(file.path(h$directory, file)), tolerance = 1e-8)
stopifnot(all(c("study/03_adam/data/adsl.xpt", "study/03_adam/data/adpc.xpt", "study/03_adam/data/adpp.xpt", "study/03_adam/data/adae.xpt", "study/03_adam/spec/adam_spec.xlsx", "study/06_csr/csr_section11.txt", "study/04_analysis/report/report.html") %in% h$files))
cat("PASS full six-stage study, 40 checks, canonical numerical results and transport artifacts\n")
for (result in list(a, b, d, f, h)) {
  stopifnot(all(file.exists(file.path(result$directory, result$files))))
  textfiles <- result$files[grepl("\\.(html|json|log|txt|csv)$", result$files)]
  for (file in textfiles) {
    txt <- paste(readLines(file.path(result$directory, file), warn = FALSE), collapse = "\n")
    stopifnot(!grepl("/Users/|/var/folders/", txt))
  }
  inv <- read.csv(file.path(result$directory, "file_inventory.csv"))
  stopifnot(all(inv$md5 == unname(tools::md5sum(file.path(result$directory, inv$file)))))
}
expect_error(methods_run(config("sandbox"), root, a$directory), "new empty")
missing <- file.path(work, "missing-root")
dir.create(missing)
failed <- file.path(work, "failed")
expect_error(methods_run(config("sandbox"), missing, failed), "Missing reviewed")
stopifnot(!dir.exists(failed))
cat("PASS complete inventories, portable exports, failure cleanup and overwrite protection\n")
unlink(work, recursive = TRUE)
