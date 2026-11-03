# CI/build dependencies only. Visitors install nothing.
if (!requireNamespace('pak', quietly = TRUE)) {
  # Official prebuilt bootstrap: compiling pak's bundled curl requires headers
  # absent from a clean Ubuntu runner. pak then manages package system needs.
  # https://pak.r-lib.org/reference/install.html
  pak_repository <- sprintf('https://r-lib.github.io/p/pak/stable/%s/%s/%s',
                            .Platform$pkgType, R.Version()$os, R.Version()$arch)
  install.packages('pak', repos = pak_repository)
  if (!requireNamespace('pak', quietly = TRUE)) stop('Could not initialize the pak dependency installer.')
}
method_packages <- trimws(strsplit(read.dcf('browser_modules/methods/DESCRIPTION')[1,'Imports'],',',fixed=TRUE)[[1]])
engine <- paste(readLines('browser_modules/engine/app.R',warn=FALSE),collapse='\n')
engine_packages <- regmatches(engine,gregexpr('(?<=library\\()[A-Za-z][A-Za-z0-9.]*',engine,perl=TRUE))[[1]]
pak::pkg_install(unique(c('shinylive@0.5.0',method_packages,engine_packages)))
