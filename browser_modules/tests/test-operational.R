#!/usr/bin/env Rscript
# Browser intake/state contracts, with canonical per-app calculations and editable-state round trips.
# Run from the repository root. These complement each module's own mathematical/server tests.
suppressPackageStartupMessages(library(shiny))
source('browser_modules/shared/browser_workspace.R')
expect_error <- function(expr, pattern = NULL) {
  error <- tryCatch({ force(expr); NULL }, error = identity)
  stopifnot(inherits(error, 'error')); if (!is.null(pattern)) stopifnot(grepl(pattern, conditionMessage(error), fixed = TRUE))
}
stopifnot(identical(bw_parse('id,value\n001,1\n')$id, '001'))
expect_error(bw_parse('id,id\n1,2'), 'unique')
expect_error(bw_parse('id,value\n001,2,3'), 'same number of fields')
expect_error(bw_parse('id,value\n001'), 'same number of fields')
stopifnot(bw_parse('id,value\n001,"line one\nline two"')$value=='line one\nline two')
expect_error(bw_parse('id,value\n"unfinished,3'))
expect_error(bw_convert(bw_parse('x,y\n1,Inf'), data.frame(a=1,b=1), c('x','y')), 'nonfinite')
expect_error(bw_convert(bw_parse('x,y\n1,2'), data.frame(a=1,b=1), c('x','x')), 'distinct')
stopifnot(grepl("'=SUM", bw_csv_safe(data.frame(label='=SUM(A1:A2)')), fixed=TRUE))
apps <- c(risk='risk_monitor/shiny',hours='budget_reconciliation/shiny',uat='uat_irt/shiny',lifecycle='lifecycle_dashboard/shiny',trialmon='sasr_monitoring_wiki/trialmon_shiny')
for (module in names(apps)) {
  directory <- normalizePath(apps[[module]])
  e <- new.env(); old <- setwd(directory); sys.source('app.R', envir=e); setwd(old)
  shiny::testServer(directory, {
    session$flushReact(); stopifnot(!bw$active())
    session$setInputs(bw_action=list(action='example',generation=1,nonce=1)); stopifnot(bw$active())
    if (module=='hours') {
      session$setInputs(need=0,contingency=40); session$setInputs(need=59.5,contingency=50)
      session$setInputs(ledger_cell_edit=list(row=1,col=4,value='78.5'))
    }
    if (module=='uat') {
      session$setInputs(test_set=list(id='RAND-04',status='Pass'))
      session$setInputs(defect_set=list(id='DEF-01',to='Closed'))
      session$setInputs(cover_gap='URS-SUP-005')
    }
    if (module=='risk') {
      session$setInputs(sig=rv$signals$id[1],level=as.character(rv$signals$level[1]),tier='All')
      session$setInputs(level='red')
    }
    if (module=='lifecycle') {
      session$setInputs(study='CP-108',openq=0,dblprog=25); session$setInputs(openq=150)
    }
    if (module=='trialmon') {
      session$setInputs(ctcae='6.0',ae_ctcae='6.0',window=30,alp=FALSE,meddra='29.1',pid='CP101-014',kri='SF-RATE',kri_level='AMBER')
      session$setInputs(window=14,ae_ctcae='5.0',kri_level='RED')
    }
    saved <- bw$snapshot(); stopifnot(length(saved$outputs)>=2, length(saved$inputs)==length(e$BW_TEMPLATES))
    serialized <- jsonlite::toJSON(list(schema=1,module=module,inputs=lapply(saved$inputs,bw_csv),settings=saved$settings),auto_unbox=TRUE,null='null',digits=16)
    # Complete payload arriving before begin must be accepted; the late same-generation begin cannot erase it.
    session$setInputs(bw_payload=list(generation=2,files=list(list(name='workspace.json',text=serialized))))
    stopifnot(!bw$active(),bw$state$state=='mapping'); expect_error(bw$snapshot())
    session$setInputs(bw_begin=list(generation=2)); stopifnot(bw$state$state=='mapping')
    mapping <- list(); for(i in seq_along(e$BW_TEMPLATES)) {
      mapping[[paste0('bw_file_2_',i)]] <- names(e$BW_TEMPLATES)[i]
      for(j in seq_along(e$BW_TEMPLATES[[i]]$data)) mapping[[paste0('bw_map_2_',i,'_',j)]] <- names(e$BW_TEMPLATES[[i]]$data)[j]
    }
    mapping[['bw_confirm_2']] <- TRUE; do.call(session$setInputs,mapping)
    session$setInputs(bw_action=list(action='apply',generation=2,nonce=2)); if (!bw$active()) stop(module, ': restore: ', bw$state$message)
    restored <- bw$snapshot()
    for(name in names(saved$inputs)) stopifnot(identical(bw_csv(saved$inputs[[name]]), bw_csv(restored$inputs[[name]])))
    if(module=='hours') stopifnot(restored$settings$need==59.5, hours_settings()$contingency==50, rv$ledger$eac[1]==78.5)
    if(module=='uat') stopifnot(nrow(rv$tests)==30,rv$defects$Status[rv$defects$DefectID=='DEF-01']=='Closed',rv$tests$Status[rv$tests$TestID=='RAND-04']=='Pass')
    if(module=='trialmon') stopifnot(settings()$hys_window==14,settings()$ae_ctcae=='5.0',study()$LEVEL[study()$ID=='SF-RATE']=='RED')
    # An old upload can never replace a newer workspace or enable exports after a failed replacement.
    session$setInputs(bw_payload=list(generation=1,files=list(list(name='bad.csv',text='bad')))); stopifnot(bw$active())
    session$setInputs(bw_begin=list(generation=3)); stopifnot(!bw$active()); expect_error(bw$snapshot())
    session$setInputs(bw_payload=list(generation=3,files=list(list(name='bad.csv',text='a,a\n1,2')))); stopifnot(!bw$active(),bw$state$state=='error')
    session$setInputs(bw_action=list(action='export',generation=2,nonce=3)); stopifnot(!bw$active())
    session$setInputs(bw_action=list(action='example',generation=4,nonce=4)); stopifnot(bw$active())
    session$setInputs(bw_action=list(action='reset',generation=5,nonce=5)); stopifnot(!bw$active(),is.null(source_data()))
  })
  cat(module, ': blank/example/edit/atomic import/stale/invalid/export/restore/reset passed\n')
}
# Study-specific scientific intake contracts: no inherited example schedule or silently normal missing labs.
old <- setwd(apps[['trialmon']]); e<-new.env();sys.source('app.R',envir=e);setwd(old)
frames <- lapply(e$BW_TEMPLATES,`[[`,'data'); cfg <- e$BW_TM_EXAMPLE_SETTINGS
expect_error(e$bw_tm_validate(frames,NULL),'study schedule')
valid <- e$bw_tm_validate(frames,cfg)
changed <- cfg; changed$schedule <- c('Day 1'=1,'Day 8'=8); changed$sae_limits<-c(0,1)
custom <- e$bw_tm_validate(frames,changed)
st <- study_signals(custom$tm,custom$config$schedule,custom$config$sae_limits,custom$config$missing_limits)
stopifnot(st$LEVEL[st$ID=='QTL-SAE']=='RED',st$VALUE[st$ID=='MISS-LAB']==0)
bad <- frames;bad[['adlb.csv']]<-bad[['adlb.csv']][!(bad[['adlb.csv']]$USUBJID=='CP101-001' & bad[['adlb.csv']]$PARAMCD=='ALT'),]
expect_error(e$bw_tm_validate(bad,cfg),'Every included participant/parameter')
bad<-frames;bad[['adlb.csv']]$AVALU[1]<-'unrecognized';expect_error(e$bw_tm_validate(bad,cfg),'units')
bad<-frames;bad[['adeg.csv']]$CHG[which(bad[['adeg.csv']]$ABLFL!='Y')[1]]<-900;expect_error(e$bw_tm_validate(bad,cfg),'change equal')
bad<-frames;bad[['adsl.csv']]$SAFFL[1]<-'N';excluded<-e$bw_tm_validate(bad,cfg);stopifnot(nrow(excluded$tm$adsl)==17,nrow(excluded$inputs[['adsl.csv']])==18)
cat('TRIALMON study conventions, population exclusions, missing measurements, units and ECG change checks passed\n')
