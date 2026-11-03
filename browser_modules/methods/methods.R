# Browser execution adapters for canonical synthetic method programs.
# Every run uses an isolated virtual workspace; no command shell or analysis server.
METHOD_LABELS <- c(sandbox = "PK, NCA and bioequivalence sandbox", carryover = "Residual carryover operating characteristics", cqtc = "C-QTc hysteresis operating characteristics", study = "Worked bioequivalence study: all six stages")
METHOD_STUDY_PACKAGES <- c("PowerTOST", "blockrand", "PKNCA", "admiral", "admiraldev", "metacore", "metatools", "xportr", "datasetjson", "rtables", "tern", "formatters", "r2rtf", "NonCompart", "diffdf", "dplyr", "tidyr", "lubridate", "haven", "openxlsx", "readxl", "commonmark", "ggplot2", "knitr", "rmarkdown", "renv", "nlme")
methods_defaults <- function(kind = "sandbox") {
  switch(kind,
    sandbox = list(kind = kind, n = 40, seed = 2026, true_gmr = 1, within_cv = .15, confirmed = FALSE),
    carryover = list(kind = kind, n = 24, seed = 20261025, replicates = 200, half_life = 24, theta = c(.8, .95, 1, 1.25), disposition = "mono", washouts = c(2, 3, 4, 5, 6, 8, 10), configurations = "base", confirmed = FALSE),
    cqtc = list(kind = kind, seed = 20261025, replicates = 100, scenarios = c("KA1-p32", "KA3-k0.7-p32"), sign_vectors = 9999, bootstrap = 999, controls = TRUE, confirmed = FALSE),
    study = list(kind = kind, confirmed = FALSE),
    stop("Select a method module.", call. = FALSE)
  )
}
methods_escape <- function(x) {
  x <- gsub("&", "&amp;", as.character(x), fixed = TRUE)
  x <- gsub("<", "&lt;", x, fixed = TRUE)
  x <- gsub(">", "&gt;", x, fixed = TRUE)
  gsub('"', "&quot;", x, fixed = TRUE)
}
methods_env <- function(root) {
  e <- new.env(parent = globalenv())
  # Canonical scripts were written as one R session. Give them a job-local global
  # environment and retain the launcher's deterministic, no-model drafting path.
  e$source <- function(file, local = e, ...) {
    target <- if (is.environment(local)) local else e
    result <- base::source(file, local = target, ...)
    if (basename(file) == "slm_client.R") {
      target$.has_httr2 <- FALSE
      target$.has_reticulate <- FALSE
    }
    invisible(result)
  }
  e
}
methods_cqtc_catalog <- function(root) {
  e <- new.env(parent = baseenv())
  sys.source(file.path(root, "cqtc_hysteresis/R/oc_core.R"), e)
  data.frame(id = vapply(e$SCEN, `[[`, "", "id"), label = vapply(e$SCEN, `[[`, "", "label"), stringsAsFactors = FALSE)
}
methods_validate <- function(config, root) {
  if (!is.list(config) || !is.character(config$kind) || length(config$kind) != 1L || !config$kind %in% names(METHOD_LABELS)) stop("Choose a supported method module.", call. = FALSE)
  cfg <- modifyList(methods_defaults(config$kind), config)
  number <- function(key, lo, hi, integer = FALSE) {
    x <- cfg[[key]]
    if (!is.numeric(x) || length(x) != 1L || is.na(x) || !is.finite(x) || x < lo || x > hi || (integer && x %% 1 != 0)) stop(key, " must be ", if (integer) "a whole number " else "numeric ", "between ", lo, " and ", hi, ".", call. = FALSE)
  }
  values <- function(key, allowed) {
    x <- cfg[[key]]
    if (!is.character(x) || !length(x) || anyNA(x) || anyDuplicated(x) || any(!x %in% allowed)) stop("Select valid, distinct ", key, ".", call. = FALSE)
  }
  if (!identical(cfg$confirmed, TRUE)) stop("Confirm the synthetic-method scope and selected assumptions before running.", call. = FALSE)
  if (cfg$kind != "study") number("seed", 0, .Machine$integer.max - 100, TRUE)
  if (cfg$kind %in% c("sandbox", "carryover")) {
    number("n", 12, 300, TRUE)
    if (cfg$n %% 2) stop("Use an even participant count for the balanced 2x2 crossover.", call. = FALSE)
  }
  if (cfg$kind == "sandbox") {
    number("true_gmr", .5, 2)
    number("within_cv", .01, .8)
  }
  if (cfg$kind == "carryover") {
    number("replicates", 20, 2000, TRUE)
    number("half_life", 1, 240)
    for (key in c("theta", "washouts")) {
      x <- cfg[[key]]
      lim <- if (key == "theta") c(.5, 2) else c(.5, 20)
      if (!is.numeric(x) || !length(x) || length(x) > 12 || anyNA(x) || any(!is.finite(x)) || any(x < lim[1] | x > lim[2]) || anyDuplicated(x)) stop("Supply 1–12 distinct ", key, " values between ", lim[1], " and ", lim[2], ".", call. = FALSE)
    }
    values("disposition", c("mono", "biexp"))
    values("configurations", c("base", "assay", "extended"))
    if (cfg$n * cfg$replicates > 96000) stop("Browser limit: participants × replicates must be at most 96,000 per scenario. Reduce the requested simulation size, not a study analysis population.", call. = FALSE)
    if (length(cfg$theta) * length(cfg$disposition) > 16) stop("Choose at most 16 theta/disposition scenarios per run.", call. = FALSE)
  }
  if (cfg$kind == "cqtc") {
    number("replicates", 20, 1000, TRUE)
    number("sign_vectors", 99, 9999, TRUE)
    number("bootstrap", 99, 999, TRUE)
    values("scenarios", methods_cqtc_catalog(root)$id)
    if (!is.logical(cfg$controls) || length(cfg$controls) != 1 || is.na(cfg$controls)) stop("controls must be true or false.", call. = FALSE)
  }
  cfg
}
methods_copy <- function(root, work, files) {
  for (relative in unique(files)) {
    if (grepl("(^/|(^|/)\\.\\.(/|$)|\\\\)", relative) || !file.exists(file.path(root, relative))) stop("Missing reviewed method source: ", relative, call. = FALSE)
    destination <- file.path(work, relative)
    dir.create(dirname(destination), recursive = TRUE, showWarnings = FALSE)
    if (!file.copy(file.path(root, relative), destination, overwrite = TRUE)) stop("Cannot stage method source.", call. = FALSE)
  }
}
methods_source_files <- function(root, kind) {
  common <- c("assets/toolkit.css", "assets/ui.js", "assets/theme/tokens.css", "browser_modules/methods/methods.R")
  sim <- c("sim_lifecycle/priors.R", "sim_lifecycle/simulate_adam.R", "sim_lifecycle/run_lifecycle.R")
  interpret <- paste0("tlf_interpret/R/", c("slm_client.R", "extract_facts.R", "validate_interpretation.R", "interpret.R"))
  switch(kind,
    sandbox = c(common, sim, interpret),
    carryover = c(common, sim, paste0("sim_lifecycle/carryover_oc/R/", c("dgm.R", "nca_m13a.R", "analyze.R"))),
    cqtc = c(common, paste0("cqtc_hysteresis/R/", c("sim.R", "area.R", "oc_core.R"))),
    study = c(
      common, sim, "tlf_interpret/R/validate_interpretation.R", "study/renv.lock", "study/study.css",
      list.files(file.path(root, "study"), pattern = "\\.R$", recursive = TRUE, full.names = FALSE) |> paste0("study/", x = _),
      paste0("_partials/", as.vector(outer(c("_head-d", "_topbar-example-d"), 1:3, paste0)), ".html")
    )
  )
}
methods_table_html <- function(x) {
  if (!nrow(x)) {
    return("<p>No rows.</p>")
  }
  paste0('<div class="tblwrap"><table class="data"><thead><tr>', paste0("<th>", methods_escape(names(x)), "</th>", collapse = ""), "</tr></thead><tbody>", paste(apply(as.data.frame(x), 1, function(r) paste0("<tr>", paste0("<td>", methods_escape(ifelse(is.na(r), "", r)), "</td>", collapse = ""), "</tr>")), collapse = ""), "</tbody></table></div>")
}
methods_page <- function(title, body, depth = 0L) {
  up <- paste(rep("../", depth), collapse = "")
  paste0('<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="dark light"><title>', methods_escape(title), '</title><script>(function(d){try{var t=localStorage.getItem("bp-theme");if(t==="light"||t==="dark")d.dataset.theme=t}catch(e){}})(document.documentElement)</script><link rel="stylesheet" href="', up, 'assets/toolkit.css"><script defer src="', up, 'assets/ui.js"></script></head><body><main class="wrap" style="padding:24px 16px;overflow-wrap:anywhere"><button class="theme-toggle" type="button" aria-label="Toggle light or dark theme">Light / dark</button><p class="kicker">Trial biostatistics toolkit · synthetic methods</p><h1>', methods_escape(title), '</h1><p class="synthetic">Synthetic examples and exploratory methods. No scientific approval, client validation or regulatory qualification is implied.</p>', body, "</main></body></html>")
}
methods_csv <- function(x, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(x, path, row.names = FALSE, na = "")
}
# Exercise both integration engines and their exception boundary before the study.
# These are runtime known answers, separate from the study's scientific QC ledger.
methods_cubature_checks <- function() {
  scalar <- cubature::hcubature(function(x) x^2, 0, 1)$integral
  vector <- cubature::hcubature(function(x) c(x[1] * x[2], x[1]^2 + x[2]^2), c(0, 0), c(1, 1), fDim = 2)$integral
  expected_error <- tryCatch({cubature::hcubature(function(x) stop("QC expected error"), 0, 1); "not caught"}, error = conditionMessage)
  recovered <- cubature::hcubature(function(x) x^2, 0, 1)$integral
  cuba <- function(f) cubature::cuhre(f, lowerLimit = c(0, 0), upperLimit = c(1, 1), flags = list(verbose = 0L))$integral
  cuba_value <- cuba(function(x) x[1] * x[2])
  cuba_error <- tryCatch({cuba(function(x) stop("QC expected Cuba error")); "not caught"}, error = conditionMessage)
  cuba_recovered <- cuba(function(x) x[1] * x[2])
  actual <- c(scalar, vector, as.numeric(identical(expected_error, "QC expected error")), recovered, cuba_value, as.numeric(identical(cuba_error, "QC expected Cuba error")), cuba_recovered)
  expected <- c(1/3, 1/4, 2/3, 1, 1/3, 1/4, 1, 1/4)
  checks <- data.frame(check = c("hcubature scalar", "hcubature vector product", "hcubature vector quadratic", "hcubature expected error caught", "hcubature recovery", "Cuba cuhre product", "Cuba expected error caught", "Cuba recovery"), actual = actual, expected = expected, tolerance = 1e-9, status = ifelse(abs(actual - expected) <= 1e-9, "pass", "fail"))
  if (any(checks$status != "pass")) stop("The integration runtime self-check failed; the study was not run.", call. = FALSE)
  checks
}

methods_study <- function(e, work, progress) {
  missing <- METHOD_STUDY_PACKAGES[!vapply(METHOD_STUDY_PACKAGES, requireNamespace, TRUE, quietly = TRUE)]
  if (length(missing)) stop("Study packages unavailable in this runtime: ", paste(missing, collapse = ", "), call. = FALSE)
  methods_csv(methods_cubature_checks(), "runtime_compatibility_checks.csv")
  stages <- c("R/common.R", "01_design/design.R", "02_sap/sap.R", "03_adam/01_sdtm.R", "03_adam/02_adsl.R", "03_adam/03_adpc.R", "03_adam/04_adae.R", "04_analysis/01_nca.R", "03_adam/05_adpp.R", "03_adam/spec/build_spec.R", "03_adam/06_checks_xpt.R", "04_analysis/02_be.R", "04_analysis/03_tlf.R", "05_qc/qc.R", "06_csr/csr.R", "R/pages.R")
  for (i in seq_along(stages)) {
    progress((i - 1) / length(stages), paste("Worked study:", stages[i]))
    sys.source(file.path("study", stages[i]), e)
  }
  if (any(e$qc_ledger$status != "pass")) stop("The worked-study QC ledger contains a failed check.", call. = FALSE)
  sections <- list("Bioequivalence estimates" = e$be_results, "Supplementary analyses" = e$be_supplementary, "PK acceptability checks" = e$pk_checks, "Population counts" = data.frame(population = c("Safety", "PK concentration", "PK parameter", "Bioequivalence"), n = vapply(c("SAFFL", "PKCFL", "PKPFL", "BEFL"), function(k) sum(e$adsl[[k]] == "Y"), 0)), "Same-author QC ledger" = e$qc_ledger)
  body <- paste0('<p>All six canonical R stages executed in this browser. This HTML report replaces the native Quarto presentation step; it does not replace any numerical analysis. Package versions are recorded with this run and can differ from the native lockfile.</p><p><a href="../../index.html">Study stages</a> · <a href="../../05_qc/qc_ledger.html">QC ledger</a> · <a href="../../06_csr/csr_section11.html">Number-checked CSR text</a></p>', paste(vapply(names(sections), function(n) paste0("<h2>", methods_escape(n), "</h2>", methods_table_html(sections[[n]])), ""), collapse = ""))
  e$write_text(methods_page("Worked bioequivalence study: browser report", body, 3), e$sp("04_analysis/report/report.html"))
  e$write_json_det(list(study = e$STUDY$studyid, synthetic = TRUE, seed = e$STUDY$seed, r_version = R.version.string, packages = as.list(e$VERS), stages = stages, report_renderer = "Browser HTML; Quarto not required", results = list(be_shown = e$be_pass, n_be_set = sum(e$adsl$BEFL == "Y"), qc_pass = sum(e$qc_ledger$status == "pass"), qc_checks = nrow(e$qc_ledger))), e$sp("run_manifest.json"))
  sections
}
# Keep extracted reports self-contained. Site navigation that is not part of the
# run remains a clearly external link to the public toolkit, never a broken path.
methods_portable_study_pages <- function(work) {
  paths <- list.files("study", pattern = "\\.html$", recursive = TRUE, full.names = TRUE)
  relative <- function(path) {
    bits <- strsplit(path, "/", fixed = TRUE)[[1]]
    out <- character()
    for (bit in bits) {
      if (bit == "..") out <- head(out, -1L) else if (bit != "." && nzchar(bit)) out <- c(out, bit)
    }
    paste(out, collapse = "/")
  }
  for (path in paths) {
    html <- paste(readLines(path, warn = FALSE), collapse = "\n")
    html <- gsub("pins R 4.6.0 and the package versions below.", "records native reference versions; actual runtime versions for this run appear below.", html, fixed = TRUE)
    html <- gsub("Generated by <code>study/run_all.R</code>", "Generated by the browser adapter using the canonical stages from <code>study/run_all.R</code>", html, fixed = TRUE)
    html <- gsub("Quarto results report", "browser HTML results report", html, fixed = TRUE)
    html <- gsub("a Quarto results report", "a browser HTML results report", html, fixed = TRUE)
    html <- gsub("Package versions (renv.lock)", "Package versions used by this run", html, fixed = TRUE)
    html <- gsub("(pinned in renv.lock)", "(actual runtime; native reference lockfile retained)", html, fixed = TRUE)
    note <- paste0('<aside class="synthetic"><strong>Browser reproduction.</strong> All canonical R stages executed for this run; the HTML renderer replaces Quarto. The native rerun commands and lockfile below are reference materials. Actual browser versions are recorded in <a href="', paste(rep("../", length(strsplit(path, "/", fixed = TRUE)[[1]]) - 1L), collapse = ""), 'software_versions.csv">software_versions.csv</a>; no claim that this browser used the native lockfile is made.</aside>')
    html <- sub("(<body[^>]*>)", paste0("\\1", note), html)
    matches <- regmatches(html, gregexpr('(?:href|src)="[^"#]+"', html, perl = TRUE))[[1]]
    for (m in unique(matches)) {
      target <- sub('^[^=]+="(.*)"$', "\\1", m)
      if (grepl("^(https?:|data:|mailto:|javascript:|/)", target)) next
      bare <- strsplit(target, "[?#]", perl = TRUE)[[1]][1]
      if (file.exists(file.path(dirname(path), bare))) next
      public <- paste0("https://patrickiben.github.io/biometrics-ai-portfolio/", relative(file.path(dirname(path), target)))
      html <- gsub(m, sub(target, public, m, fixed = TRUE), html, fixed = TRUE)
    }
    writeLines(html, path, useBytes = TRUE)
  }
}

methods_figures <- function(kind, tables) {
  plots <- list()
  if (kind == "sandbox") {
    x <- tables[["Computed summary"]]
    x <- x[x$SECTION == "PK_GEO" & x$STAT == "GEOMEAN", ]
    plots[["Geometric PK summaries"]] <- ggplot2::ggplot(x, ggplot2::aes(GROUP, VALUE, fill = GROUP)) +
      ggplot2::geom_col() +
      ggplot2::facet_wrap(~PARAMCD, scales = "free_y") +
      ggplot2::scale_y_log10() +
      ggplot2::labs(x = "Treatment", y = "Geometric mean (log scale; parameter-specific units)", fill = "Treatment", caption = "Synthetic outputs; parameter-specific units are documented in the ADPP data.")
  }
  if (kind == "carryover") {
    d <- tables[["Operating characteristics"]]
    d <- d[d$endpoint == "AUC", ]
    d$panel <- paste(d$config, d$disposition, "true GMR", d$theta)
    panels <- unique(d$panel)
    for (i in seq_along(split(panels, ceiling(seq_along(panels) / 4)))) {
      ps <- split(panels, ceiling(seq_along(panels) / 4))[[i]]
      x <- d[d$panel %in% ps, ]
      x$washout <- factor(x$washout, levels = unique(d$washout))
      plots[[paste("Carryover AUC operating characteristics", i)]] <- ggplot2::ggplot(x, ggplot2::aes(washout, be_rate, colour = arm, group = arm)) +
        ggplot2::geom_line() +
        ggplot2::geom_point() +
        ggplot2::facet_wrap(~panel, ncol = 2) +
        ggplot2::scale_y_continuous(limits = c(0, 1)) +
        ggplot2::labs(x = "Washout / median half-life (KA1 = control)", y = "BE declaration fraction", colour = "Analysis arm", caption = "All simulated studies form the denominator. Monte Carlo SEs, evaluability and paired contrasts are in the complete tables.")
    }
  }
  if (kind == "cqtc") {
    d <- tables[["Operating characteristics"]]
    panels <- unique(d$scenario)
    for (i in seq_along(split(panels, ceiling(seq_along(panels) / 4)))) {
      ps <- split(panels, ceiling(seq_along(panels) / 4))[[i]]
      x <- d[d$scenario %in% ps, ]
      plots[[paste("C-QTc rejection fractions", i)]] <- ggplot2::ggplot(x, ggplot2::aes(rejection_rate, method)) +
        ggplot2::geom_errorbar(ggplot2::aes(xmin = ci95_low, xmax = ci95_high), orientation = "y", width = .2) +
        ggplot2::geom_point() +
        ggplot2::facet_wrap(~scenario, ncol = 1) +
        ggplot2::scale_x_continuous(limits = c(0, 1)) +
        ggplot2::labs(x = "Fraction of replicates (exact 95% interval)", y = "Method", caption = "Synthetic selected scenarios. Some rows are model-selection or tmax diagnostics, not treatment-effect tests.")
    }
  }
  if (length(plots)) {
    dir.create("figures", showWarnings = FALSE)
    for (i in seq_along(plots)) {
      plots[[i]] <- plots[[i]] + ggplot2::theme_bw(base_size = 11) + ggplot2::theme(plot.caption = ggplot2::element_text(hjust = 0), legend.position = "bottom") + ggplot2::labs(title = names(plots)[i])
      for (ext in c("png", "pdf")) ggplot2::ggsave(sprintf("figures/figure-%02d.%s", i, ext), plots[[i]], width = 11, height = if (kind == "cqtc") 12 else 7, units = "in", dpi = 130, limitsize = FALSE)
    }
  }
  plots
}

methods_run <- function(config, root, out, progress = function(value, detail) {}) {
  root <- normalizePath(root, mustWork = TRUE)
  cfg <- methods_validate(config, root)
  if (dir.exists(out) && length(list.files(out, all.files = TRUE, no.. = TRUE))) stop("Run output must be a new empty directory.", call. = FALSE)
  dir.create(out, recursive = TRUE, showWarnings = FALSE)
  out <- normalizePath(out, mustWork = TRUE)
  complete <- FALSE
  on.exit(if (!complete) unlink(out, recursive = TRUE), add = TRUE)
  files <- methods_source_files(root, cfg$kind)
  methods_copy(root, out, files)
  oldlocale <- Sys.getlocale("LC_COLLATE")
  oldwd <- getwd()
  oldopts <- options()
  oldpknca <- NULL
  oldrng <- RNGkind()
  hadseed <- exists(".Random.seed", globalenv(), inherits = FALSE)
  if (hadseed) oldseed <- get(".Random.seed", globalenv())
  on.exit(
    {
      setwd(oldwd)
      invisible(Sys.setlocale("LC_COLLATE", oldlocale))
      introduced <- setdiff(names(options()), names(oldopts))
      if (length(introduced)) options(setNames(rep(list(NULL), length(introduced)), introduced))
      options(oldopts)
      # PKNCA 0.12.1 rejects some of its own defaults through its public setter.
      # Restore the exact prior option store without revalidating or changing it.
      if (!is.null(oldpknca)) assign("options", oldpknca$value, envir = oldpknca$storage)
      do.call(RNGkind, as.list(oldrng))
      if (hadseed) assign(".Random.seed", oldseed, globalenv()) else if (exists(".Random.seed", globalenv(), inherits = FALSE)) rm(".Random.seed", envir = globalenv())
    },
    add = TRUE
  )
  if (cfg$kind == "study") {
    missing <- METHOD_STUDY_PACKAGES[!vapply(METHOD_STUDY_PACKAGES, requireNamespace, TRUE, quietly = TRUE)]
    # Namespace startup may add defaults (notably xportr's column-name options).
    # Keep those initialized defaults for later runs; restore all pre-existing
    # values and remove options added by the actual analysis below.
    initialized <- options()
    oldopts <- c(oldopts, initialized[setdiff(names(initialized), names(oldopts))])
    if (length(missing)) stop("Study packages unavailable in this runtime: ", paste(missing, collapse = ", "), call. = FALSE)
  }
  # A study may be the first run in a fresh session. Initialize and snapshot
  # PKNCA before canonical NCA changes its options, with cleanup already armed.
  if (cfg$kind == "study" || "PKNCA" %in% loadedNamespaces()) {
    storage <- get(".PKNCAEnv", envir = loadNamespace("PKNCA"))
    if (cfg$kind == "study") PKNCA::PKNCA.options()
    oldpknca <- list(storage = storage, value = get("options", envir = storage))
  }
  setwd(out)
  e <- methods_env(out)
  tables <- list()
  warnings <- character()
  log <- character()
  start <- proc.time()[["elapsed"]]
  log <- capture.output(withCallingHandlers(
    {
      if (cfg$kind == "sandbox") {
        options(toolkit.sandbox.config = cfg[c("n", "seed", "true_gmr", "within_cv")])
        sys.source("sim_lifecycle/run_lifecycle.R", e)
        tables <- list("Computed summary" = e$rs, "Adverse events" = e$ae_result, "Participant data" = e$adam$adsl)
      }
      if (cfg$kind == "carryover") {
        for (f in c("dgm.R", "nca_m13a.R", "analyze.R")) sys.source(file.path("sim_lifecycle/carryover_oc/R", f), e)
        settings <- e$oc_settings(n = as.integer(cfg$n), t_half = cfg$half_life)
        configs <- e$oc_configs(settings)[cfg$configurations]
        cells <- expand.grid(theta = cfg$theta, disposition = cfg$disposition, stringsAsFactors = FALSE)
        streams <- e$oc_streams(nrow(cells), as.integer(cfg$seed))
        e$use_stream(streams[[nrow(cells) + 1L]])
        lloq <- e$lloq_from_population(100000L, settings)
        runs <- vector("list", nrow(cells))
        for (i in seq_len(nrow(cells))) {
          progress((i - 1) / nrow(cells), paste("Carryover scenario", i, "of", nrow(cells)))
          e$use_stream(streams[[i]])
          pop <- e$draw_population(as.integer(cfg$replicates), settings)
          runs[[i]] <- e$run_cell(pop, cells$theta[i], cells$disposition[i], configs, cfg$washouts, lloq, adequate = TRUE, set = settings)
        }
        results <- do.call(rbind, lapply(runs, `[[`, "results"))
        results$arm_label <- unname(e$OC_ARMS[results$arm])
        decomp <- do.call(rbind, lapply(runs, `[[`, "decomposition"))
        tables <- list("Operating characteristics" = results, "Bias decomposition" = decomp)
        methods_csv(results, "results/oc_results.csv")
        methods_csv(decomp, "results/oc_bias_decomposition.csv")
        jsonlite::write_json(list(settings = settings, lloq = lloq, cells = cells, rng = "L'Ecuyer-CMRG; one stream per selected cell"), "results/method_settings.json", auto_unbox = TRUE, pretty = TRUE)
        e$source("sim_lifecycle/simulate_adam.R")
        RNGkind("Mersenne-Twister", "Inversion", "Rejection")
        demo <- e$simulate_study(e$sample_design(archetype = "BE", N = 40), seed = 2026, washout_h = 48)
        for (nm in c("adpc", "adpp")) methods_csv(demo[[nm]], paste0("results/canonical_adam_demo/", nm, ".csv"))
      }
      if (cfg$kind == "cqtc") {
        for (f in c("sim.R", "area.R", "oc_core.R")) sys.source(file.path("cqtc_hysteresis/R", f), e)
        all_scenarios <- e$SCEN
        indices <- which(vapply(all_scenarios, `[[`, "", "id") %in% cfg$scenarios)
        e$REPS <- as.integer(cfg$replicates)
        e$ALPHA <- .05
        e$B_SF <- as.integer(cfg$sign_vectors)
        e$B_BOOT <- as.integer(cfg$bootstrap)
        RNGkind("Mersenne-Twister", "Inversion", "Rejection")
        runs <- vector("list", length(indices))
        for (j in seq_along(indices)) {
          i <- indices[j]
          progress((j - 1) / length(indices), paste("C-QTc scenario", j, "of", length(indices)))
          e$SCEN <- all_scenarios[i]
          e$SEED <- as.integer(cfg$seed + i - 1)
          runs[[j]] <- e$run_all()
        }
        oc <- do.call(rbind, runs)
        tables <- list("Operating characteristics" = oc)
        methods_csv(oc, "results/oc_results.csv")
        if (isTRUE(cfg$controls)) {
          e$SEED <- as.integer(cfg$seed)
          tables[["Noise-free controls"]] <- e$noise_free()
          tables[["Fixed worked checks"]] <- e$example_check()
          methods_csv(tables[["Noise-free controls"]], "results/noise_free_areas.csv")
          methods_csv(tables[["Fixed worked checks"]], "results/example_check.csv")
        }
      }
      if (cfg$kind == "study") tables <- methods_study(e, out, progress)
    },
    warning = function(w) {
      warnings <<- c(warnings, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  ))
  plots <- withCallingHandlers(methods_figures(cfg$kind, tables), warning = function(w) {
    warnings <<- c(warnings, conditionMessage(w))
    invokeRestart("muffleWarning")
  })
  elapsed <- proc.time()[["elapsed"]] - start
  # Never retain machine-specific source/library paths in portable audit files.
  for (prefix in c(root, out, .libPaths())) log <- gsub(prefix, "<runtime>", log, fixed = TRUE)
  writeLines(log, "execution.log", useBytes = TRUE)
  writeLines(unique(warnings), "warnings.txt", useBytes = TRUE)
  jsonlite::write_json(cfg, "configuration.json", auto_unbox = TRUE, pretty = TRUE, digits = 16)
  versions <- data.frame(component = c("R", loadedNamespaces()), version = c(R.version.string, vapply(loadedNamespaces(), function(p) as.character(utils::packageVersion(p)), "")))
  methods_csv(versions, "software_versions.csv")
  saveRDS(tables, "results.rds")
  jsonlite::write_json(list(status = "succeeded", module = cfg$kind, synthetic = TRUE, approved = FALSE, elapsed_seconds = elapsed, warnings = unique(warnings)), "execution_status.json", auto_unbox = TRUE, pretty = TRUE)
  previews <- character()
  for (i in seq_along(tables)) {
    file <- sprintf("tables/table-%02d.csv", i)
    methods_csv(tables[[i]], file)
    # Every row is retained in CSV/RDS. HTML tables are paginated, not truncated.
    chunks <- if (nrow(tables[[i]])) split(seq_len(nrow(tables[[i]])), ceiling(seq_len(nrow(tables[[i]])) / 250L)) else list(integer())
    links <- character()
    for (j in seq_along(chunks)) {
      html <- sprintf("tables/table-%02d-page-%03d.html", i, j)
      writeLines(methods_page(paste(names(tables)[i], "page", j, "of", length(chunks)), paste0('<p><a href="../report.html">Report index</a> · <a href="', basename(file), '">Complete CSV</a></p>', methods_table_html(tables[[i]][chunks[[j]], , drop = FALSE])), 1), html, useBytes = TRUE)
      links <- c(links, paste0('<a href="', html, '">', j, "</a>"))
    }
    previews <- c(previews, paste0("<li><strong>", methods_escape(names(tables)[i]), "</strong>: ", nrow(tables[[i]]), ' rows. <a href="', file, '">Complete CSV</a>. HTML pages: ', paste(links, collapse = " · "), "</li>"))
  }
  body <- paste0('<p>Canonical R programs executed in this browser session. Results are synthetic and must not be interpreted as a client study or as approval. Simulation rates describe the selected scenarios; Monte Carlo uncertainty is retained.</p><p><a href="configuration.json">Run configuration</a> · <a href="software_versions.csv">Software versions</a> · <a href="execution.log">Execution log</a> · <a href="warnings.txt">Warnings</a> · <a href="results.rds">Complete R table objects</a></p>', if (cfg$kind == "study") '<p><a href="study/index.html">All six study stages</a> · <a href="study/04_analysis/report/report.html">Study results report</a></p>' else "", "<h2>Tables</h2><ul>", paste(previews, collapse = ""), "</ul>", if (length(plots)) paste0("<h2>Figures</h2>", paste(vapply(seq_along(plots), function(i) paste0('<figure><img style="max-width:100%;height:auto" src="figures/figure-', sprintf("%02d", i), '.png" alt="', methods_escape(names(plots)[i]), '"><figcaption>', methods_escape(names(plots)[i]), ' · <a href="figures/figure-', sprintf("%02d", i), '.pdf">PDF</a></figcaption></figure>'), ""), collapse = "")) else "", "<p>Source files and all generated artifacts are included in this download. SAS is not executed by these method examples.</p>")
  writeLines(methods_page(METHOD_LABELS[[cfg$kind]], body), "report.html", useBytes = TRUE)
  writeLines(c("# Reproduce this configured synthetic method run from the extracted folder.", 'source("browser_modules/methods/methods.R")', 'config <- jsonlite::read_json("configuration.json", simplifyVector=TRUE)', 'methods_run(config, getwd(), tempfile("methods-reproduction-"))'), "reproduce.R")
  if (cfg$kind == "study") methods_portable_study_pages(out)
  files <- sort(list.files(out, recursive = TRUE, full.names = FALSE, all.files = TRUE))
  files <- files[!dir.exists(file.path(out, files))]
  inventory <- data.frame(file = files, bytes = file.info(file.path(out, files))$size, md5 = unname(tools::md5sum(file.path(out, files))))
  methods_csv(inventory, "file_inventory.csv")
  complete <- TRUE
  progress(1, "Completed")
  list(config = cfg, tables = tables, plots = plots, files = c(files, "file_inventory.csv"), directory = out, elapsed = elapsed, warnings = unique(warnings))
}
