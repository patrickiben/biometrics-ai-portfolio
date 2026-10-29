# Shinylive rescans exported sources at launch, without the build's .renvignore.
# Test that actual dependency discovery does not fetch an unused TableTree stack.
renderer <- normalizePath("toolkit_launcher/analysis_runner.R", mustWork = TRUE)
stage <- tempfile("renderer-runtime-scan-"); dir.create(stage)
stopifnot(file.copy(renderer, file.path(stage, "analysis_runner.R")))
writeLines(c("Package: rendererProbe", "Version: 0.1.0", "Imports: ggplot2, jsonlite"),
           file.path(stage, "DESCRIPTION"))
writeLines('source("analysis_runner.R")', file.path(stage, "app.R"))
stopifnot(!file.exists(file.path(stage, ".renvignore")))
deps <- renv::dependencies(stage, errors = "fatal", progress = FALSE)
stopifnot(!"rtables" %in% deps$Package)
unlink(stage, recursive = TRUE)
stopifnot(!"rtables" %in% loadedNamespaces())
source(renderer)
folder <- tempfile("renderer-without-rtables-"); dir.create(folder)
plain <- list(components = list(list(name = "Plain table", value = data.frame(x = 1:3)),
                               list(name = "Matrix", value = matrix(1:4, ncol = 2))), warnings = character())
invisible(analysis_render(plain, folder, "plain", "", "Synthetic dependency check"))
stopifnot(!"rtables" %in% loadedNamespaces(),
          identical(readRDS(file.path(folder, "component-01.rds"))$x, 1:3),
          nrow(readRDS(file.path(folder, "component-02.rds"))) == 2L)
unlink(folder, recursive = TRUE)
cat("Renderer dependency QC passed: runtime renv discovery and ordinary rendering do not require rtables.\n")
