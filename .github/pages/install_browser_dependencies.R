# CI/build dependencies only. Visitors install nothing.
if (!requireNamespace('pak',quietly=TRUE)) install.packages('pak',repos='https://cloud.r-project.org')
method_packages <- trimws(strsplit(read.dcf('browser_modules/methods/DESCRIPTION')[1,'Imports'],',',fixed=TRUE)[[1]])
engine <- paste(readLines('browser_modules/engine/app.R',warn=FALSE),collapse='\n')
engine_packages <- regmatches(engine,gregexpr('(?<=library\\()[A-Za-z][A-Za-z0-9.]*',engine,perl=TRUE))[[1]]
pak::pkg_install(unique(c('shinylive@0.5.0',method_packages,engine_packages)))
