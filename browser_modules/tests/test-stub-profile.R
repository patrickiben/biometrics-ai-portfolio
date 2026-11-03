# The launcher fallback must preserve base::source scoping and return semantics.
p <- new.env(); sys.source('toolkit_launcher/stub_profile.R', p)
tmp <- tempfile(); dir.create(tmp)
script <- file.path(tmp,'ordinary.R'); writeLines('scoped_value <- 41L; scoped_value + 1L', script)
caller <- new.env(); caller$source <- p$source; caller$script <- script
evalq(answer <- source(script, local=TRUE),caller)
stopifnot(caller$scoped_value==41L, caller$answer$value==42L, !exists('scoped_value',.GlobalEnv,inherits=FALSE))
explicit <- new.env(); p$source(script,local=explicit);stopifnot(explicit$scoped_value==41L)
p$source(script,local=FALSE);stopifnot(get('scoped_value',.GlobalEnv)==41L);rm(scoped_value,envir=.GlobalEnv)
slm <- file.path(tmp,'slm_client.R');writeLines(c('.has_httr2 <- TRUE','.has_reticulate <- TRUE'),slm);caller$script<-slm
evalq(source(script,local=TRUE),caller);stopifnot(identical(caller$.has_httr2,FALSE),identical(caller$.has_reticulate,FALSE))
explicit <- new.env();p$source(slm,local=explicit);stopifnot(identical(explicit$.has_httr2,FALSE),identical(explicit$.has_reticulate,FALSE))
unlink(tmp,recursive=TRUE)
cat('Launcher stub source: caller/global/explicit environments and optional-model fallback passed\n')
