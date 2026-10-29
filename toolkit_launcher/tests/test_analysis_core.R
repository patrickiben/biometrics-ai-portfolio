# Execute with Rscript from the repository root. No test framework is required.
root <- normalizePath(getwd())
source(file.path(root, 'toolkit_launcher/tests/analysis_fixtures.R'))
source(file.path(root, 'r_tlf_pseudocode/00_setup_helpers.R'))
source(file.path(root, 'r_tlf_pseudocode/01_analysis_models.R'))
checks <- 0L
check <- function(ok, message) {checks <<- checks+1L; if(!isTRUE(ok))stop(message,call.=FALSE)}
near <- function(x,y,tol=1e-10) isTRUE(all.equal(x,y,tolerance=tol,check.attributes=FALSE))
throws <- function(expr, pattern) {msg<-tryCatch({force(expr);''},error=conditionMessage);grepl(pattern,msg,fixed=TRUE)}
options(tfl.settings=list())
d <- tibble(USUBJID=c('A','B','C'),arm='Active',AVAL=c(1,2,4))
s <- pkstats(d,by='arm')
check(near(s$geomean,2), 'Geometric mean known answer')
check(near(s$geocv,100*sqrt(exp(var(log(c(1,2,4))))-1)), 'Geometric CV uses log variance')
check(near(pkstats(mutate(d,AVAL=AVAL*7),by='arm')$geomean,14), 'PK scale equivariance')
check(near(pkstats(d[3:1,],by='arm'),s), 'PK row-order invariance')
check(throws(pkstats(bind_rows(d,d[1,]),by='arm'),'multiple analysis records'), 'Duplicate PK record rejected')
edge <- tibble(USUBJID=letters[1:6],arm='Active',AVAL=c(0,-1,NA,Inf,8,3),AVALC=c('BLQ','','','','BLQ',''))
e <- pkstats(edge,by='arm')
check(e$n==1L&&e$n_input==6L&&e$n_excluded==5L&&e$n_missing==2L&&e$n_nonpositive==2L&&e$n_blq_excluded==2L, 'All excluded PK records accounted for, including flagged positive BLQ')
e <- pkstats(edge[1:4,],by='arm')
check(nrow(e)==1L&&e$n==0L&&is.na(e$mean)&&is.na(e$geomean), 'All nonquantifiable group retained')
e <- descstat(mutate(d,AVAL=NA_real_),by='arm')
check(e$n==0L&&is.na(e$min)&&is.na(e$max)&&e$c_mean=='NE', 'All-missing descriptive cells are not Inf/NaN')
check(flag_any(c('N','Y',NA))&&is.na(flag_any(c('N',NA)))&&is.na(flag_any(c('',NA)))&&!flag_any(c('N','N')), 'Three-state flag collapse')
check(identical(flag_label(c('Y','N','',NA)),c('Yes','No','Unknown','Unknown')), 'Listing flag unknowns preserved')
check(n_pct(0,0)=='0 (NE)', 'Undefined denominator is explicit')

adam <- analysis_fixture('parallel');den <- bign(adam$adsl,'TRT01A')
ae <- ae_hierarchy(adam$adae,'TRT01A',den)
aedup <- ae_hierarchy(bind_rows(adam$adae,adam$adae),'TRT01A',den)
check(identical(ae,aedup),'Repeating AE records does not inflate participant counts')
check(near(ae,ae_hierarchy(adam$adae[nrow(adam$adae):1,],'TRT01A',den)),'AE row-order invariance')
zero <- ae_hierarchy(adam$adae[FALSE,],'TRT01A',den)
check(nrow(zero)==1L&&all(c('Placebo','Test','Total')%in%names(zero))&&all(unlist(zero[den$trt])=='0 (0.0%)'),'No events retains zero row and all population columns')
sev <- ae_hierarchy(adam$adae[FALSE,],'TRT01A',den,severity=TRUE)
check(ncol(sev)==14L&&all(grepl('0 (0.0%)',unlist(sev[-c(1,2)]),fixed=TRUE)),'Zero-event severity retains all four statuses for each arm')
cat <- catfreq(tibble(USUBJID=c('A','B'),TRT01A='Test',SEX=c('M',NA)), 'SEX',by='TRT01A',denom=den)
check(all(c('Test','Placebo','Total')%in%cat$TRT01A)&&any(cat$cat=='Unknown')&&all(cat$n[cat$TRT01A=='Placebo']==0),'Categorical empty arms and unknowns materialized')
ada <- adam$adis;ada$TEADAFL<-NA_character_
a <- ada_summary(ada,'TRT01A')
check(a$Total[a$category=='Treatment-emergent ADA-positive']=='0 (0.0%)'&&a$Total[a$category=='Treatment-emergent ADA-positive — unknown status']=='24 (100.0%)','Missing ADA flags remain unknown, never negative')
check(any(grepl('Neutralizing antibody',a$category)),'NAb output retained')
lab <- adam$adlb;lab$ATOXGRN<-3;lab$BTOXGRN<-NA_real_
l <- marked_lab_summary(lab,'TRT01A',den)
check(all(l$Total[l$criterion=='Any markedly abnormal']=='0 (0.0%)')&&all(l$Total[l$criterion=='Unknown evaluability']=='24 (100.0%)'),'Missing baseline grade is not grade zero')
lab$BTOXGRN<-0;l<-marked_lab_summary(lab,'TRT01A',den)
check(all(l$Total[l$criterion=='Any markedly abnormal']=='24 (100.0%)'),'Known baseline grade allows emergence')
options(tfl.settings=list(baseline_continuous='AGE',baseline_categorical='SEX'))
b <- baseline_summary(adam$adsl[c('USUBJID','SAFFL','TRT01A','AGE','SEX')],'TRT01A')
check(setequal(b$characteristic,c('AGE','SEX'))&&'Total'%in%names(b),'Baseline selectors use only chosen fields and include Total')
check(throws(baseline_summary(adam$adsl[c('USUBJID','SAFFL','TRT01A')],'TRT01A'),'Missing selected baseline'),'Missing selected field actionable error')
options(tfl.settings=list(lab_high_limits='ALT=3\nAST=2'))
check(identical(tfl_setting_map('lab_high_limits',NULL),c(ALT=3,AST=2)),'Point-and-click threshold map parsed')
check(throws({options(tfl.settings=list(lab_high_limits='ALT=3\nALT=2'));tfl_setting_map('lab_high_limits',NULL)},'unique'),'Duplicate threshold definitions rejected')

unit_fixture<-tibble(USUBJID=c('A','B'),PARAMCD='CONC',AVAL=c(1,2),AVALU=c('ng/mL','mg/L'))
check(throws(check_analysis_units(unit_fixture),'Mixed analysis units'),'Inconsistent units rejected before quantitative reporting')
unit_fixture$AVALU[2]<-NA_character_
check(throws(check_analysis_units(unit_fixture),'nonmissing analysis units'),'Missing unit for finite reported value rejected')

# Execute every non-model source against nondegenerate synthetic domains.
# The complementary test_analysis_models.R covers the model methods.
model_stems <- c('t_be_anova','t_dose_proportionality','t_dose_proportionality_ss','t_accumulation','t_pd_summary','f_pd_change','f_pkpd_overlay','t_cqtc_hysteresis','f_cqtc_hysteresis')
run_count<-0L;render_count<-0L;component_count<-0L;failures<-character();warnings_seen<-character()
plotdir<-tempfile('analysis-qc-',tmpdir=Sys.getenv('TMPDIR',tempdir()));dir.create(plotdir)
for(design in c('parallel','crossover','single_sequence','sad','mad')) {
  options(tfl.settings=analysis_fixture_settings(design))
  for(path in list.files(file.path(root,'r_tlf_pseudocode',design),pattern='[.]R$',full.names=TRUE)) {
    stem<-tools::file_path_sans_ext(basename(path));if(stem%in%model_stems)next
    id<-paste(design,stem,sep='/');options(tfl.program=id)
    e<-new.env(parent=.GlobalEnv);e$adam<-analysis_fixture(design);e$env<-list(study='SYNTHETIC-QC',out=plotdir)
    captured<-list();e$print<-function(x,...) {captured[[length(captured)+1L]]<<-x;invisible(x)}
    source_text<-readLines(path,warn=FALSE);source_text<-source_text[!grepl('^source\\(|^env <- setup\\(',source_text)]
    error<-tryCatch(withCallingHandlers({
      eval(parse(text=source_text),e)
      if(!length(captured))stop('No explicitly printed result')
      for(j in seq_along(captured)) {
        x<-captured[[j]]
        if(inherits(x,'ggplot')) {
          outfile<-file.path(plotdir,paste0(design,'-',stem,'-',j,'.png'))
          ggplot2::ggsave(outfile,x,width=10,height=7,dpi=72)
          if(file.info(outfile)$size<1000)stop('Empty plot artifact')
          render_count<-render_count+1L
        } else if(is.data.frame(x)) {
          if(any(vapply(x,is.list,logical(1))))stop('Unresolved list column in report')
        } else if(!inherits(x,'TableTree'))stop('Unsupported printed result class')
      }
      NULL
    },warning=function(w){warnings_seen<<-c(warnings_seen,paste(id,conditionMessage(w)));invokeRestart('muffleWarning')}),error=conditionMessage)
    if(!is.null(error))failures<-c(failures,paste(id,error))
    component_count<-component_count+length(captured);run_count<-run_count+1L
  }
}
if(length(failures))stop(paste(failures,collapse='\n'),call.=FALSE)
check(run_count>=190L,'Complete non-model source inventory executed')
cat(sprintf('PASS: %d known-answer/edge/metamorphic checks; %d source programs; %d printed components; %d rendered figures.\n',checks,run_count,component_count,render_count))
if(length(warnings_seen))cat(sprintf('Reviewable rendering/runtime warnings: %d (unique: %d).\n',length(warnings_seen),length(unique(warnings_seen))))
writeLines(unique(warnings_seen),file.path(plotdir,'warnings.txt'))
cat('QC artifacts:',plotdir,'\n')
