# Native tests of the exact adapter shipped to webR; the separate browser suite
# executes the same files in WebAssembly and compares exported numeric results.
source('vaccine/browser.R')
count<-0L
check<-function(x,message){count<<-count+1L;if(!isTRUE(x))stop(message,call.=FALSE)}
near<-function(x,y,tol=1e-11)isTRUE(all.equal(x,y,tolerance=tol,check.attributes=FALSE))
throws<-function(expr,pattern)grepl(pattern,tryCatch({force(expr);''},error=conditionMessage),fixed=TRUE)
bad<-function(data,settings,pattern){v<-vaccine_browser_validate(data,settings);!v$ok&&any(grepl(pattern,v$errors$message,fixed=TRUE))}
defaults<-vaccine_browser_defaults()
check(!length(defaults$outputs)&&defaults$study_id==''&&defaults$response_threshold=='','Initial form has no selected study/output/protective definition')
example<-vaccine_browser_example();settings<-example$settings;data<-example$data
check(!any(unlist(settings[c('visits_confirmed','diary_confirmed','review_confirmed')])),'Loading synthetic examples never grants review confirmation')
check(!vaccine_browser_validate(data,settings)$ok,'Synthetic example requires explicit review')
settings[c('visits_confirmed','diary_confirmed','review_confirmed')]<-list(TRUE,TRUE,TRUE)
v<-vaccine_browser_validate(data,settings)
check(v$ok,'Confirmed full synthetic example validates')
check(identical(v$config$followup_visits,c('Day 28','Day 56'))&&is.numeric(v$data$titers$AVAL),'Lists and numeric columns normalize into the canonical contract')
core<-vaccine_browser_engine()
native_cfg<-settings
for(k in c('followup_visits','dose_labels','symptoms'))native_cfg[[k]]<-strsplit(settings[[k]],'\n',fixed=TRUE)[[1]]
native_data<-lapply(names(vaccine_browser_feeds()),function(slot)utils::read.csv(file.path('vaccine/examples',paste0(slot,'.csv')),check.names=FALSE,stringsAsFactors=FALSE));names(native_data)<-names(vaccine_browser_feeds())
native<-core$vaccine_prepare(native_data,native_cfg)
for(id in settings$outputs){a<-core$vaccine_output(id,v$prepared,v$config);b<-core$vaccine_output(id,native,native_cfg)
  check(identical(a$title,b$title)&&identical(a$warnings,b$warnings),paste(id,'titles/assumptions match native'))
  for(i in seq_along(a$components)){
    av<-a$components[[i]]$value;bv<-b$components[[i]]$value
    check(if(is.data.frame(av))near(av,bv)else near(av$data,bv$data),paste(id,'component',i,'matches direct native shared core'))
  }
}
# Independent fixture answers, separate from adapter/core parity.
gmt<-v$prepared$titer_summary
cell<-gmt[gmt$ARM=='Vaccine'&gmt$VISIT=='Baseline',]
check(cell$n_population==5&&cell$n_evaluable==4,'Known immunogenicity population/evaluable counts')
check(near(cell$geometric_mean,(10*20*2.5*40)^(1/4)),'Baseline GMT independently computed from four known values, including LLOQ/2')
fold<-core$vaccine_fold_rise(v$prepared);cell<-fold[fold$ARM=='Vaccine'&fold$VISIT=='Day 28',]
check(cell$n_paired==4&&cell$n_unpaired==1&&near(cell$geometric_mean_fold_rise,(4*4*10*4)^(1/4)),'Independent paired fold-rise counts and product-root answer')
response<-core$vaccine_response(v$prepared,v$config);cell<-response[response$ARM=='Vaccine'&response$VISIT=='Day 28',]
check(cell$n_responders==3&&cell$n_evaluable==4&&cell$percent==75,'Independent conditional response boundary answer')

# Source column names, population flags and assay qualifiers can be client-specific.
mapped<-data;custom<-settings;custom$columns<-list()
for(slot in names(mapped)){
  names(mapped[[slot]])<-paste0('Source ',names(mapped[[slot]]))
  custom$columns[[slot]]<-setNames(as.list(names(mapped[[slot]])),names(vaccine_browser_feeds()[[slot]]))
}
for(k in c('Source IMMFL','Source SAFEFL'))mapped$participants[[k]]<-ifelse(mapped$participants[[k]]=='Y','included','excluded')
custom$yes_value<-'included';custom$no_value<-'excluded'
qual<-c(EXACT='measured',BLQ='<limit',ALQ='>limit',MISSING='not done')
mapped$titers[['Source QUALIFIER']]<-unname(qual[mapped$titers[['Source QUALIFIER']]])
for(q in names(qual))custom[[paste0('qualifier_',tolower(q))]]<-qual[[q]]
m<-vaccine_browser_validate(mapped,custom)
check(m$ok&&near(m$prepared$titer_summary,v$prepared$titer_summary)&&near(m$prepared$diary_maxima,v$prepared$diary_maxima),'Mapped source headers/flags/qualifiers preserve canonical results')
mut<-custom;mut$columns$titers$AVAL<-'absent';check(bad(mapped,mut,'existing source column'),'Missing mapped source column rejected')
mut<-custom;mut$columns$diary$GRADE<-'';check(bad(mapped,mut,'required column'),'Blank grades still require an explicitly mapped grade column')
mut<-custom;mut$columns$participants$ARM<-mut$columns$participants$USUBJID;check(bad(mapped,mut,'distinct source columns'),'Accidental source-column reuse rejected')
shared<-settings;shared$columns<-list(participants=list(IMMFL='SAFEFL',SAFEFL='SAFEFL'))
check(vaccine_browser_validate(data,shared)$ok,'Intentional shared population source flag is allowed')
mut<-settings;mut$qualifier_blq<-mut$qualifier_exact;check(bad(data,mut,'distinct source value'),'Ambiguous assay qualifiers rejected')
mut<-settings;mut$yes_value<-mut$no_value;check(bad(data,mut,'must differ'),'Ambiguous population flags rejected')

# Selected outputs determine required input feeds and threshold applicability.
only<-settings;only$outputs<-'immunogenicity';only$response_threshold<-'';only$fold_threshold<-'';only$baseline_threshold<-'';only$diary_confirmed<-FALSE
check(vaccine_browser_validate(data[c('participants','titers')],only)$ok,'Immunogenicity needs no diary or response definition')
react<-settings;react$outputs<-'reactogenicity';react$visits_confirmed<-FALSE
check(vaccine_browser_validate(data[c('participants','doses','diary')],react)$ok,'Solicited reactions need no titers/visit confirmation')
for(rule in c('threshold','fold_rise','conditional')){
  cfg<-settings;cfg$response_rule<-rule
  for(policy in c('complete','observed')){
    cfg$react_denominator<-policy;x<-vaccine_browser_validate(data,cfg)
    ncfg<-cfg;for(k in c('followup_visits','dose_labels','symptoms'))ncfg[[k]]<-strsplit(cfg[[k]],'\n',fixed=TRUE)[[1]]
    np<-core$vaccine_prepare(native_data,ncfg)
    check(x$ok&&near(core$vaccine_response(x$prepared,x$config),core$vaccine_response(np,ncfg))&&near(core$vaccine_reactogenicity(x$prepared),core$vaccine_reactogenicity(np)),paste('Native parity',rule,policy))
  }
}
for(pair in list(c('confidence',1),c('fold_threshold',1),c('response_threshold',0),c('day_start',1.5),c('max_grade',6))){cfg<-settings;cfg[[pair[[1]]]]<-as.numeric(pair[[2]]);check(!vaccine_browser_validate(data,cfg)$ok,paste('Invalid setting rejected',pair[[1]]))}
cfg<-settings;cfg$review_confirmed<-'TRUE';check(bad(data,cfg,'confirm'),'String TRUE is not review approval')
cfg<-settings;cfg$confidence<-list(list(.95));check(bad(data,cfg,'finite numeric'),'Nested numeric settings are a validation error rather than an evaluation path')
cfg<-settings;cfg$day_start<-TRUE;check(bad(data,cfg,'finite numeric'),'Logical values are not numeric settings, matching guided configuration')
cfg<-settings;cfg$study_id<-123;check(bad(data,cfg,'text value'),'Study identifiers require text rather than implicit conversion')
long<-data;long$participants$ARM[1]<-paste(rep('a',201),collapse='');check(bad(long,settings,'200 characters'),'Source text limit matches guided configuration')
cfg<-settings;cfg$columns<-list(participants=c(ARM='ARM'));check(vaccine_browser_validate(data,cfg)$ok,'Partial named mappings preserve canonical defaults safely')
for(case in c('duplicate','orphan','mixed','blank_grade','censor','fractional','nonfinite','control')){
  x<-data
  if(case=='duplicate')x$titers<-rbind(x$titers,x$titers[1,])
  if(case=='orphan')x$diary$DOSE[1]<-'Not administered'
  if(case=='mixed')x$titers$UNIT[1]<-'Other unit'
  if(case=='blank_grade')x$diary$GRADE[1]<-'missing text'
  if(case=='censor')x$titers$AVAL[x$titers$QUALIFIER=='BLQ']<-'1'
  if(case=='fractional')x$diary$DAY[1]<-'0.5'
  if(case=='nonfinite')x$titers$AVAL[1]<-'Inf'
  if(case=='control')x$participants$ARM[1]<-'two\nlines'
  check(!vaccine_browser_validate(x,settings)$ok,paste('Malformed scientific input rejected:',case))
}

# CSV parsing retains numeric-looking IDs and rejects ragged/malformed records.
scratch<-tempfile('vaccine-browser-qc-');dir.create(scratch)
csv<-file.path(scratch,'input.csv')
writeBin(charToRaw('\ufeffid,label\n001,"A, B"\n002,NA\n'),csv)
parsed<-vaccine_browser_read_csv(csv)
check(identical(parsed$id,c('001','002'))&&parsed$label[2]=='NA','CSV preserves IDs and literal NA text')
writeLines(c('id,label','1,A,extra'),csv);check(throws(vaccine_browser_read_csv(csv),'same number'),'Extra CSV fields rejected')
writeLines(c('id,label','1'),csv);check(throws(vaccine_browser_read_csv(csv),'same number'),'Missing CSV fields rejected')
writeLines(c('id,id','1,2'),csv);check(throws(vaccine_browser_read_csv(csv),'distinct'),'Duplicate CSV headers rejected')
writeChar('USUBJID,ARM,IMMFL,SAFEFL\nS1,A,Y,Y\nS2,A,Y,Y\nS3,A,Y,Y\nS4,A,Y,Y\nS5,A,Y,"Y\n',csv,eos=NULL)
check(throws(vaccine_browser_read_csv(csv),'quoted string'),'Unterminated CSV quote after the header sample is rejected rather than repaired into an eligible participant')
writeChar('id,label\n001,"valid final field"',csv,eos=NULL)
check(vaccine_browser_read_csv(csv)$id=='001','Valid CSV final record does not require a terminal newline')
writeBin(as.raw(c(105,100,10,255)),csv);check(throws(vaccine_browser_read_csv(csv),'encoding'),'Invalid UTF-8 rejected')
writeLines('USUBJID,DOSE,DAY,SYMPTOM,GRADE',csv)
empty<-data;empty$diary<-vaccine_browser_read_csv(csv)
e<-vaccine_browser_validate(empty,settings)
check(e$ok&&all(e$prepared$diary_maxima$n_assessed==0),'Header-only diary stays entirely unassessed')

# Browser capacity checks occur before constructing large expected grids.
large<-data;large$participants<-data.frame(USUBJID=paste0('P',1:10000),ARM='A',IMMFL='Y',SAFEFL='Y')
cfg<-only;cfg$followup_visits<-paste(paste0('V',1:25),collapse='\n');large$titers<-data$titers[FALSE,]
check(bad(large,cfg,'full eligible population'),'Browser immunogenicity grid bound preserves full population')
large$doses<-data.frame(USUBJID=rep(large$participants$USUBJID,each=2),DOSE=rep(c('Dose 1','Dose 2'),10000))
large$diary<-data$diary[FALSE,];cfg<-react;cfg$symptoms<-paste0('S',1:2)
check(bad(large,cfg,'prespecified window and population'),'Browser diary grid bound preserves planned window/population')
cfg<-settings;cfg$dose_labels<-paste0('Dose ',1:17);cfg$symptoms<-paste0('S',1:5)
check(bad(data,cfg,'32 figure pages'),'Figure-page capacity rejected before rendering')
large<-data;large$participants<-large$participants[rep(1,200001),]
check(bad(large,settings,'200,000 records'),'Per-input browser record capacity enforced for direct API too')
limit_errors<-vaccine_browser_validate(large,settings)$errors$message
check(any(grepl('retaining all eligible participants and the full prespecified window',limit_errors,fixed=TRUE))&&!any(grepl('desktop',limit_errors,fixed=TRUE)),'Record-limit guidance preserves the study and does not promise a larger desktop upload limit')
large_csv<-file.path(scratch,'too-large.csv');con<-file(large_csv,'wb');writeBin(as.raw(32),con);seek(con,where=vaccine_browser_limits()$csv_bytes,origin='start');writeBin(as.raw(10),con);close(con)
byte_error<-tryCatch(vaccine_browser_read_csv(large_csv),error=conditionMessage)
check(is.character(byte_error)&&grepl('retaining every required analysis record',byte_error,fixed=TRUE)&&!grepl('desktop',byte_error,fixed=TRUE),'Byte-limit guidance preserves required records without an unsupported desktop recommendation')

# Reproducible exports, complete output rows and inert user text.
inert<-data;label<-"=SUM(1,2) <script>alert('x')</script> & %put PWN; café"
inert$participants$ARM[inert$participants$ARM=='Vaccine']<-label
cfg<-settings;cfg$study_id<-"ÉTUDE <script>x</script> & %put PWN;"
run<-vaccine_browser_run(inert,cfg,file.path(scratch,'run'))
check(length(run$outputs)==6&&all(file.exists(file.path(run$directory,run$files))),'All six outputs have complete on-disk file manifest')
for(id in names(run$outputs))for(i in seq_along(run$outputs[[id]]$components)){
  component<-run$outputs[[id]]$components[[i]]$value;stem<-file.path(run$directory,'outputs',id,sprintf('component-%02d',i))
  if(is.data.frame(component)){
    restored<-readRDS(paste0(stem,'.rds'));check(near(component,restored),paste(id,i,'RDS preserves every row/value'))
    table<-read.csv(paste0(stem,'.csv'),check.names=FALSE,stringsAsFactors=FALSE)
    check(nrow(table)==nrow(component),paste(id,i,'CSV exports every row'))
  }else check(file.info(paste0(stem,'.png'))$size>1000&&file.info(paste0(stem,'.pdf'))$size>1000,paste(id,i,'PNG/PDF exported'))
}
html<-paste(readLines(file.path(run$directory,'analysis_report.html'),encoding='UTF-8'),collapse='\n')
check(grepl('&lt;script&gt;',html,fixed=TRUE)&&!grepl('<script>x</script>',html,fixed=TRUE),'Study text is escaped in HTML')
sas<-paste(readLines(file.path(run$directory,'vaccine_analysis.sas'),encoding='UTF-8'),collapse='\n')
hex<-paste(sprintf('%02x',as.integer(charToRaw(enc2utf8(label)))),collapse='')
check(grepl(paste0("'",hex,"'x"),sas,fixed=TRUE)&&!grepl('%put PWN;',sas,fixed=TRUE),'Unicode and executable-looking SAS input remain inert UTF-8 literals')
check(grepl(paste0('length ARM $',nchar(label,type='bytes'),';'),sas,fixed=TRUE),'SAS text width uses UTF-8 bytes rather than character count')
check(grepl('stop;',vaccine_browser_sas_data('empty',data.frame(ID=character())),fixed=TRUE),'Empty SAS tables explicitly prevent implicit missing row')
csvtext<-paste(readLines(file.path(run$directory,'outputs/immunogenicity/component-01.csv'),encoding='UTF-8'),collapse='\n')
check(grepl("'=SUM",csvtext,fixed=TRUE),'Result CSV neutralizes formula-leading labels')
profile<-jsonlite::fromJSON(file.path(run$directory,'setup_profile.json'),simplifyVector=FALSE)
check(length(profile$values$outputs)==6&&isTRUE(profile$values$review_confirmed),'Export records settings without declaring scientific approval')
check(!isTRUE(run$manifest$approved)&&!jsonlite::fromJSON(file.path(run$directory,'qc.json'))$approved,'Run and QC remain explicitly unapproved')
inventory<-read.csv(file.path(run$directory,'file_inventory.csv'),stringsAsFactors=FALSE)
check(identical(inventory$md5,unname(tools::md5sum(file.path(run$directory,inventory$file)))),'File inventory fingerprints every preserved artifact')
check(throws(vaccine_browser_run(data,settings,run$directory),'new, empty'),'Repeated run cannot overwrite prior results')
previous<-getwd();setwd(run$directory)
replayed<-new.env(parent=globalenv());sys.source('reproduce.R',envir=replayed);setwd(previous)
for(id in names(run$outputs))for(i in seq_along(run$outputs[[id]]$components))if(is.data.frame(run$outputs[[id]]$components[[i]]$value))
  check(near(run$outputs[[id]]$components[[i]]$value,replayed$result$outputs[[id]]$components[[i]]$value),paste(id,i,'preserved source and raw mapping reproduce exact tables'))
unlink(c(scratch,replayed$result$directory),recursive=TRUE)
cat(sprintf('PASS: %d browser-adapter mapping, native-parity, boundary, capacity and reproducible-export checks.\n',count))
