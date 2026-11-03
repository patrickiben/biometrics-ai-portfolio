# Build-only assertion. Runtime package bytes and versions are recorded separately
# in browser-runtime/packages.json; the core webR integrity lock is unchanged.
check_browser_probes <- function(site, required = NULL) {
  if (is.null(required)) {
    required <- shinylive:::resolve_dependencies(c("reticulate", "digest", "httr2"), local = FALSE)
    required <- setdiff(required, rownames(installed.packages(priority = "base")))
  }
  metadata_path <- file.path(site, "shinylive/webr/packages/metadata.rds")
  if (!file.exists(metadata_path)) stop("Browser package metadata is missing.", call. = FALSE)
  metadata <- readRDS(metadata_path)
  bundled <- vapply(required, function(package) {
    entry <- metadata[[package]]
    if (is.null(entry) || !is.character(entry$path) || length(entry$path) != 1L ||
        is.na(entry$path) || !startsWith(entry$path, "packages/") ||
        grepl("(^|/)\\.\\.(/|$)|\\\\", entry$path)) return(FALSE)
    file.exists(file.path(site, "shinylive/webr", entry$path))
  }, logical(1))
  if (!all(bundled)) stop("Missing bundled browser probe dependencies: ",
                         paste(required[!bundled], collapse = ", "), call. = FALSE)
  message("Verified same-origin browser probe closure: ", paste(required, collapse = ", "))
  invisible(required)
}
