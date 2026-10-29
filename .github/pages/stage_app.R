# Copy declared shared sources without creating a second maintained analysis engine.
# `files` is the Pages build's reviewed file set after its private-runtime filter.
public_source_path <- function(path, root = getwd()) {
  if (!is.character(path) || length(path) != 1L || is.na(path) || !nzchar(path) ||
      grepl("^/|[\\\\:]", path))
    stop("Public source must use a relative checkout path.", call. = FALSE)
  parts <- strsplit(path, "/", fixed = TRUE)[[1]]
  if (any(parts %in% c("", ".", "..")))
    stop("Public source contains an unsafe path component.", call. = FALSE)
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  source <- file.path(root, path)
  resolved <- normalizePath(source, winslash = "/", mustWork = TRUE)
  if (!startsWith(resolved, paste0(root, "/")) || dir.exists(source))
    stop("Public source is outside the checkout: ", path, call. = FALSE)
  current <- root
  for (part in parts) {
    current <- file.path(current, part)
    link <- Sys.readlink(current)
    if (!is.na(link) && nzchar(link))
      stop("Public source refuses linked files or directories: ", path, call. = FALSE)
  }
  resolved
}

stage_app_shared <- function(spec, files, stage) {
  entries <- spec$extra_files
  if (is.null(entries) || !length(entries)) return(invisible(character()))
  relative_path <- function(x) {
    is.character(x) && length(x) == 1L && !is.na(x) && nzchar(x) &&
      !grepl("^[./]|[\\\\:]", x) &&
      !any(strsplit(x, "/", fixed = TRUE)[[1]] %in% c("", ".", ".."))
  }
  targets <- character()
  for (entry in entries) {
    if (!is.list(entry) || !relative_path(entry$from) || !relative_path(entry$to))
      stop("App extra_files requires safe relative from/to paths.", call. = FALSE)
    if (!entry$from %in% files || !file.exists(entry$from) || dir.exists(entry$from) ||
        (!is.na(Sys.readlink(entry$from)) && nzchar(Sys.readlink(entry$from))))
      stop("App shared source is absent from the public file inventory: ", entry$from, call. = FALSE)
    public_source_path(entry$from)
    destination <- file.path(stage, entry$to)
    if (entry$to %in% targets || file.exists(destination) || entry$to == "portfolio_app.R")
      stop("App shared source would overwrite a staged file: ", entry$to, call. = FALSE)
    targets <- c(targets, entry$to)
  }
  # Validate the full declaration before copying any of it.
  for (entry in entries) {
    destination <- file.path(stage, entry$to)
    dir.create(dirname(destination), recursive = TRUE, showWarnings = FALSE)
    if (!file.copy(entry$from, destination, copy.date = TRUE))
      stop("Could not stage app shared source: ", entry$from, call. = FALSE)
  }
  invisible(targets)
}
