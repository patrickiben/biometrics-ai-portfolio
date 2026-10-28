# Independent known-answer, boundary and engine-export checks for all eight monitors.
root<-normalizePath(getwd())
source(file.path(root,'toolkit_launcher/analysis_monitor.R'))
source(file.path(root,'toolkit_launcher/analysis_runner.R'))
build<-tempfile('monitor-build-',tmpdir=Sys.getenv('TMPDIR',tempdir()));dir.create(file.path(build,'inputs'),recursive=TRUE)
write_feed<-function(name,value)utils::write.csv(value,file.path(build,'inputs',paste0(name,'.csv')),row.names=FALSE,na='')
count<-0L
check<-function(value,message){count<<-count+1L;if(!isTRUE(value))stop(message,call.=FALSE)}
throws<-function(expr,pattern){msg<-tryCatch({force(expr);''},error=conditionMessage);grepl(pattern,msg,fixed=TRUE)}
cfg<-list(study_id='SYNTHETIC-MONITOR-QC',checks=c('liver','qtcf','ae','dlt','enrollment','queries','visits','irt'),
  alt_threshold=3,ast_threshold=3,bilirubin_threshold=2,qtcf_amber=450,qtcf_red=500,delta_amber=30,delta_red=60,
  enrollment_ratio=.8,query_days=14,analysis_date='2026-02-01')
feeds<-list(
  liver=data.frame(USUBJID=paste0('L',1:5),alt_x=c(3,2.99,1,9,6),ast_x=c(1,2.99,3,1,1),tbl_x=c(2.01,5,2.01,2,3),alp_x=c(1,2,2,3,2)),
  qtcf=data.frame(USUBJID=paste0('Q',1:6),QTCF=c(450,450.01,500,500.01,400,400),DQTCF=c(30,0,60,0,30.01,60.01)),
  ae=data.frame(USUBJID=c('A','A','B','C','D','E'),COHORT=c('1','1','1','1','2','2'),AESER=c('Y','Y','N','Y','N','N'),AETOXGR=c(2,3,3,5,1,4),TRTEMFL=c('Y','Y','Y','N','Y','N')),
  dlt=data.frame(USUBJID=paste0('D',1:7),COHORT=c('1','1','1','2','2','3','3'),DLT_EVAL=c('Y','Y','N','Y','Y','Y','Y'),DLTFL=c('Y','N','Y','Y','Y','N','N')),
  enrollment=data.frame(N_ENROLLED=c(7,8,9),N_PLANNED_TO_DATE=10),
  queries=data.frame(OPEN_FL=c('Y','Y','Y','N'),QUERY_AGE_DAYS=c(13,14,15,99)),
  visits=data.frame(USUBJID=paste0('V',1:6),VISIT='Day 1',ACTDT=c('2026-01-12','2026-01-13','2026-01-08',NA,NA,NA),PLANDT=c('2026-01-10','2026-01-10','2026-01-10','2026-02-01','2026-01-31','2026-01-20'),WINDOW_DAYS=c(2,2,2,2,2,2)),
  clinical=data.frame(USUBJID=c('I1','I2','I3'),TRT01P=c('Test','Reference','Test')),
  randomization=data.frame(USUBJID=c('I1','I2','I4'),IXRS_TRT=c('Test','Test','Reference')))
for(name in names(feeds))write_feed(name,feeds[[name]])

liver<-analysis_monitor('liver',build,cfg)
check(identical(liver$flagged,c(TRUE,FALSE,TRUE,FALSE,TRUE)),'Liver ALT/AST inclusive and bilirubin strict boundaries')
check(identical(liver$r_ratio,c(3,1.495,.5,3,3)),'Liver R ratios known answers')
check(all(liver$alt_threshold==3)&all(liver$bilirubin_threshold==2),'Liver configured thresholds visible')
qt<-analysis_monitor('qtcf',build,cfg)
check(identical(qt$severity,c('NO FLAG','AMBER','AMBER','RED','AMBER','RED')),'QTc strict absolute/change boundaries and maximum severity')
check(all(qt$absolute_red_ms==500)&all(qt$change_red_ms==60),'QTc thresholds recorded')
ae<-analysis_monitor('ae',build,cfg)
check(identical(ae$n_sae_participants,c(1L,0L))&&identical(ae$n_sae_events,c(2L,0L)),'AE participant and event counts differ correctly')
check(identical(ae$n_grade3_participants,c(2L,0L))&&identical(ae$n_ae_participants,c(2L,1L)),'Nonemergent events excluded and grade3 participants distinct')
check(identical(ae$severity,c('AMBER','NO FLAG')),'AE empty qualifying cohort retained')
write_feed('ae',feeds$ae[c(6:1),]);check(identical(analysis_monitor('ae',build,cfg),ae),'AE record order invariant');write_feed('ae',feeds$ae)
dlt<-analysis_monitor('dlt',build,cfg)
check(identical(dlt$n_evaluable,c(2L,2L,2L))&&identical(dlt$n_dlt,c(1L,2L,0L)),'Only completed DLT windows counted')
check(identical(dlt$severity,c('AMBER','RED','NO FLAG')),'DLT count classifications')
check(dlt$n_pending[1]==1L&&dlt$n_pending_dlt_flags[1]==1L,'Pending flagged DLT remains visible separately')
enroll<-analysis_monitor('enrollment',build,cfg)
check(identical(enroll$ratio,c(.7,.8,.9))&&identical(enroll$severity,c('AMBER','NO FLAG','NO FLAG')),'Enrollment lower threshold boundary')
queries<-analysis_monitor('queries',build,cfg)
check(queries$n_open==3L&&queries$n_aged==1L&&queries$age_threshold_days==14,'Only open queries older than strict age threshold counted')
visits<-analysis_monitor('visits',build,cfg)
check(identical(visits$severity,c('NO FLAG','AMBER','NO FLAG','NO FLAG','AMBER','AMBER')),'Visit completed windows inclusive; missing visits past planned date flagged')
check(identical(visits$missing_past_window,c(FALSE,FALSE,FALSE,FALSE,FALSE,TRUE)),'Planned-date delay distinguished from missing beyond window')
check(all(visits$analysis_date==as.Date('2026-02-01')),'Explicit analysis date used instead of system time')
irt<-analysis_monitor('irt',build,cfg)
check(identical(irt$USUBJID,c('I1','I2','I3','I4'))&&identical(irt$severity,c('NO FLAG','AMBER','AMBER','AMBER')),'Reconciliation includes both unmatched feeds and assignment mismatch')
check(irt$flag[3]=='In clinical feed; absent from randomization feed'&&irt$flag[4]=='In randomization feed; absent from clinical feed','Reconciliation direction labels correct')

# Canonical runtime validation also protects reopened packages from malformed data.
bad<-feeds$ae;bad$AESER[1]<-NA;write_feed('ae',bad)
check(throws(analysis_monitor('ae',build,cfg),'missing required'),'Missing seriousness flag never silently No')
bad$AESER[1]<-'Unknown';write_feed('ae',bad)
check(throws(analysis_monitor('ae',build,cfg),'canonical Y or N'),'Unknown seriousness requires correction')
bad<-feeds$ae;bad$AETOXGR[1]<-2.5;write_feed('ae',bad)
check(throws(analysis_monitor('ae',build,cfg),'integers'),'Fractional toxicity grade rejected');write_feed('ae',feeds$ae)
bad<-feeds$dlt;bad$DLT_EVAL[1]<-NA;write_feed('dlt',bad)
check(throws(analysis_monitor('dlt',build,cfg),'missing required'),'Missing DLT evaluability rejected')
write_feed('dlt',rbind(feeds$dlt,feeds$dlt[1,]))
check(throws(analysis_monitor('dlt',build,cfg),'duplicate'),'Duplicate DLT participant not counted twice')
bad<-feeds$dlt;bad$DLT_EVAL[bad$COHORT=='1']<-'N';write_feed('dlt',bad)
check(throws(analysis_monitor('dlt',build,cfg),'No completed evaluable'),'No evaluable DLT denominator errors');write_feed('dlt',feeds$dlt)
bad<-feeds$liver;bad$alp_x[1]<-0;write_feed('liver',bad)
check(throws(analysis_monitor('liver',build,cfg),'must be positive'),'Zero liver denominator rejected');write_feed('liver',feeds$liver)
bad<-feeds$qtcf;bad$QTCF[1]<-Inf;write_feed('qtcf',bad)
check(throws(analysis_monitor('qtcf',build,cfg),'finite numeric'),'Nonfinite QTc rejected');write_feed('qtcf',feeds$qtcf)
badcfg<-cfg;badcfg$qtcf_red<-440
check(throws(analysis_monitor('qtcf',build,badcfg),'exceed amber'),'Inverted QTc thresholds rejected')
bad<-feeds$enrollment;bad$N_PLANNED_TO_DATE[1]<-0;write_feed('enrollment',bad)
check(throws(analysis_monitor('enrollment',build,cfg),'denominator must be positive'),'Zero enrollment denominator rejected')
bad<-feeds$enrollment;bad$N_ENROLLED[1]<-1.5;write_feed('enrollment',bad)
check(throws(analysis_monitor('enrollment',build,cfg),'integers'),'Fractional enrollment counts rejected');write_feed('enrollment',feeds$enrollment)
bad<-feeds$queries;bad$OPEN_FL[1]<-NA;write_feed('queries',bad)
check(throws(analysis_monitor('queries',build,cfg),'missing required'),'Missing query state rejected')
bad<-feeds$queries;bad$QUERY_AGE_DAYS[1]<--1;write_feed('queries',bad)
check(throws(analysis_monitor('queries',build,cfg),'cannot be negative'),'Negative query age rejected');write_feed('queries',feeds$queries)
bad<-feeds$visits;bad$ACTDT[1]<-'2026-02-30';write_feed('visits',bad)
check(throws(analysis_monitor('visits',build,cfg),'valid YYYY-MM-DD'),'Invalid actual date cannot be recoded as absent')
bad<-feeds$visits;bad$WINDOW_DAYS[1]<--1;write_feed('visits',bad)
check(throws(analysis_monitor('visits',build,cfg),'nonnegative whole days'),'Negative window rejected');write_feed('visits',feeds$visits)
badcfg<-cfg;badcfg$analysis_date<-'2026-2-1'
check(throws(analysis_monitor('visits',build,badcfg),'valid explicit analysis date'),'Ambiguous analysis date rejected')
write_feed('clinical',rbind(feeds$clinical,feeds$clinical[1,]))
check(throws(analysis_monitor('irt',build,cfg),'duplicate'),'Duplicate reconciliation keys rejected before cartesian join')
bad<-feeds$clinical;bad$TRT01P[1]<-NA;write_feed('clinical',bad)
check(throws(analysis_monitor('irt',build,cfg),'missing required'),'Missing treatment assignment rejected');write_feed('clinical',feeds$clinical)
check(throws(analysis_monitor('unknown',build,cfg),'Unknown monitoring check'),'Unsupported check rejected')

# Actual common engine exports all eight calculations and honest failure reports.
jsonlite::write_json(list(values=cfg),file.path(build,'setup_profile.json'),auto_unbox=TRUE)
run<-tempfile('monitor-run-',tmpdir=Sys.getenv('TMPDIR',tempdir()));dir.create(run)
plan<-list(schema=1L,module_id='sas_monitor',build_root=build,run_root=run,source_root=root,build_id='synthetic-build',run_id='synthetic-run',bundle_sha256='synthetic',engine_sha256='synthetic')
check(run_analysis(plan),'Actual common runner completes all eight checks')
status<-read.csv(file.path(run,'execution_status.csv'))
check(nrow(status)==8L&&all(status$status=='completed'),'All eight execution statuses verified')
for(id in cfg$checks) {
  dir<-file.path(run,'outputs',id)
  check(file.exists(file.path(dir,'component-01.csv'))&&file.exists(file.path(dir,'component-01.rds'))&&file.exists(file.path(dir,'index.html')),paste(id,'complete CSV/RDS/HTML export'))
}
check(identical(readRDS(file.path(run,'outputs/ae/component-01.rds')),ae),'Engine preserves exact independently checked AE results')
html<-paste(readLines(file.path(run,'analysis_report.html'),warn=FALSE),collapse='\n')
check(grepl('Light / dark',html,fixed=TRUE)&&grepl('All selected outputs completed.',html,fixed=TRUE),'Rendered report has themes and truthful success statement')
bad<-feeds$ae;bad$AESER[1]<-NA;write_feed('ae',bad)
failed<-tempfile('monitor-failure-',tmpdir=Sys.getenv('TMPDIR',tempdir()));dir.create(failed);plan$run_root<-failed
check(!run_analysis(plan),'Invalid selected monitor makes overall run fail')
check(!file.exists(file.path(failed,'outputs/ae/component-01.csv'))&&file.exists(file.path(failed,'outputs/ae/error.txt')),'Failed output has diagnostics and no partial numerical result')
qc<-jsonlite::fromJSON(file.path(failed,'qc.json'))
check(!qc$passed&&!qc$approved,'Failed run remains unapproved')
cat(sprintf('PASS: %d monitoring known-answer/boundary/export checks; all eight checks executed, with one expected rejection run.\n',count))
cat('Monitoring QC artifacts:',run,'\n')
