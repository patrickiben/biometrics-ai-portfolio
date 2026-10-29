# Independent arithmetic, known-answer, adversarial and sourceable-output checks.
source(file.path('vaccine','analysis.R'))
count <- 0L
check <- function(x, message) { count <<- count + 1L; if (!isTRUE(x)) stop(message, call.=FALSE) }
near <- function(x,y,tol=1e-11) isTRUE(all.equal(as.numeric(x),as.numeric(y),tolerance=tol,check.attributes=FALSE))
throws <- function(expr, pattern) grepl(pattern,tryCatch({force(expr);''},error=conditionMessage),fixed=TRUE)

# Known t critical values are constants, independent of the implementation's qt call.
s <- vaccine_log_summary(log(c(4,16,64)), .95)
check(near(s$estimate,16), 'GMT known product-root answer')
check(near(s$lower,exp(log(16)-4.30265272974946*log(4)/sqrt(3))), 'Log-t lower CI independent known t2 quantile')
check(near(s$upper,exp(log(16)+4.30265272974946*log(4)/sqrt(3))), 'Log-t upper CI independent known t2 quantile')
check(s$n==3 && s$confidence==.95,'GMT n/confidence exposed')
check(is.na(vaccine_log_summary(numeric())$estimate),'Empty geometric summary does not manufacture zero')
check(near(vaccine_log_summary(log(7))$estimate,7) && is.na(vaccine_log_summary(log(7))$lower),'Singleton estimate has no estimated CI')
s <- vaccine_log_summary(log(rep(7,4))); check(near(c(s$estimate,s$lower,s$upper),rep(7,3)), 'Constant values have zero observed variance')
s2 <- vaccine_log_summary(log(c(4,16,64)*100)); check(near(s2$estimate,1600) && near(s2$lower,100*vaccine_log_summary(log(c(4,16,64)))$lower),'Multiplicative unit conversion scales GMT and CI')
check(throws(vaccine_log_summary(c(NA,1)),'finite'),'Missing log values require prior evaluability selection')
check(throws(vaccine_log_summary(1,1),'confidence'),'Invalid confidence rejected')
s <- vaccine_log_summary(c(-700,700)); check(is.na(s$lower)&&is.na(s$upper)&&grepl('numeric range',s$status),'Out-of-range CI is explicit NA, not Inf/zero')

ci <- vaccine_exact_ci(0,10);check(near(ci$upper_percent,100*(1-.025^(1/10)))&&ci$lower_percent==0,'Zero-event exact CI analytic answer')
ci <- vaccine_exact_ci(10,10);check(near(ci$lower_percent,100*.025^(1/10))&&ci$upper_percent==100,'All-event exact CI analytic answer')
ci <- vaccine_exact_ci(5,10);check(near(c(ci$lower_percent,ci$upper_percent),c(18.708602845,81.291397155),1e-9),'Interior exact CI independently tabulated 5/10 answer')
check(is.na(vaccine_exact_ci(0,0)$percent),'Zero denominator gives no rate')
check(vaccine_exact_ci(1,1)$percent==100&&near(vaccine_exact_ci(1,1)$lower_percent,2.5),'Singleton exact binomial boundary')
check(throws(vaccine_exact_ci(1.5,2),'whole numbers')&&throws(vaccine_exact_ci(3,2),'whole numbers'),'Invalid binomial counts rejected')

cfg <- list(study_id='SYNTHETIC-VAX-QC',outputs=c('immunogenicity','fold_rise','response','titer_plot','reactogenicity','diary_profile'),assay='Assay',antigen='Antigen',unit='AU/mL',baseline_visit='Baseline',followup_visits=c('Post'),confidence=.95,blq_policy='exclude',alq_policy='exclude',response_rule='conditional',response_threshold=40,fold_threshold=4,baseline_threshold=20,dose_labels=c('Dose 1','Dose 2'),symptoms='Pain',day_start=0,day_end=2,max_grade=3,react_denominator='complete')
p <- data.frame(USUBJID=c(paste0('A',1:4),paste0('B',1:2)),ARM=c(rep('A',4),rep('B',2)),IMMFL='Y',SAFEFL='Y')
t <- data.frame(USUBJID=rep(p$USUBJID,each=2),ASSAY='Assay',ANTIGEN='Antigen',UNIT='AU/mL',VISIT=rep(c('Baseline','Post'),6),AVAL=as.vector(rbind(c(10,20,40,80,5,5),c(40,40,160,NA,10,10))),QUALIFIER='EXACT',LLOQ=2,ULOQ=200)
t$QUALIFIER[is.na(t$AVAL)] <- 'MISSING'
doses <- data.frame(USUBJID=c(p$USUBJID,'A1'),DOSE=c(rep('Dose 1',6),'Dose 2'))
diary <- expand.grid(USUBJID=p$USUBJID,DAY=0:2,stringsAsFactors=FALSE);diary$DOSE<-'Dose 1';diary$SYMPTOM<-'Pain';diary$GRADE<-0
for(day in 0:2)diary$GRADE[diary$USUBJID=='A1'&diary$DAY==day]<-day
diary$GRADE[diary$USUBJID=='A2'&diary$DAY==0]<-1
diary$GRADE[diary$USUBJID=='A2'&diary$DAY==1]<-NA
diary<-diary[!(diary$USUBJID=='A2'&diary$DAY==2)&diary$USUBJID!='A4',]
diary<-rbind(diary,data.frame(USUBJID='A1',DAY=0:2,DOSE='Dose 2',SYMPTOM='Pain',GRADE=0))
data <- list(participants=p,titers=t,doses=doses,diary=diary)
prepared <- vaccine_prepare(data,cfg)
summary <- prepared$titer_summary
cell <- function(d,arm='A',visit='Post') d[d$ARM==arm&d$VISIT==visit,,drop=FALSE]
s <- cell(summary);check(s$n_population==4&&s$n_evaluable==3&&s$n_not_evaluable==1,'GMT population and missing denominators retained')
check(near(s$geometric_mean,(40*40*160)^(1/3)),'GMT post independent product-root answer')
f <- cell(vaccine_fold_rise(prepared));check(near(f$geometric_mean_fold_rise,(4*2*4)^(1/3))&&f$n_paired==3&&f$n_unpaired==1,'GMFR known paired answer')
check(!near(f$geometric_mean_fold_rise,s$geometric_mean/cell(summary,visit='Baseline')$geometric_mean),'GMFR is not ratio of unmatched GMTs')
check(f$n_post_unavailable==1&&f$n_baseline_unavailable==0,'Pair exclusion direction reported')
r <- cell(vaccine_response(prepared,cfg));check(r$n_responders==2&&r$n_evaluable==3&&r$n_not_evaluable==1,'Conditional baseline equality selects fold branch and inclusive fold equality works')
cf <- cfg;cf$response_rule<-'fold_rise';r<-cell(vaccine_response(prepared,cf));check(r$n_responders==2,'Fold rule inclusive threshold exactly4')
cf$response_rule<-'threshold';r<-cell(vaccine_response(prepared,cf));check(r$n_responders==3,'Absolute rule inclusive40 boundary')
bad<-data;bad$titers$QUALIFIER[1]<-'MISSING';bad$titers$AVAL[1]<-NA;pr<-vaccine_prepare(bad,cf);r<-cell(vaccine_response(pr,cf));check(r$n_evaluable==3&&r$n_unpaired==2,'Absolute response does not need baseline but reports unpaired')
cf<-cfg;cf$baseline_visit<-'Post';cf$followup_visits<-'Baseline';back<-cell(vaccine_fold_rise(vaccine_prepare(data,cf)),visit='Baseline');check(near(back$geometric_mean_fold_rise,1/f$geometric_mean_fold_rise),'Paired GMFR reverses reciprocally')

# Row shuffling and compatible assay-unit changes preserve analysis.
set.seed(21);shuffled<-lapply(data,function(d)d[sample(seq_len(nrow(d))),,drop=FALSE]);ps<-vaccine_prepare(shuffled,cfg)
check(identical(ps$titer_summary,prepared$titer_summary),'Immunogenicity independent of input row order')
check(identical(vaccine_fold_rise(ps),vaccine_fold_rise(prepared)),'Paired joins independent of row order')
check(identical(vaccine_reactogenicity(ps),vaccine_reactogenicity(prepared)),'Reactogenicity independent of row order')
scaled<-data;scaled$titers$AVAL<-scaled$titers$AVAL*100;scaled$titers$LLOQ<-scaled$titers$LLOQ*100;scaled$titers$ULOQ<-scaled$titers$ULOQ*100;scaled$titers$UNIT<-'new-unit';cf<-cfg;cf$unit<-'new-unit';cf$response_threshold<-4000;cf$baseline_threshold<-2000
ps<-vaccine_prepare(scaled,cf);check(near(vaccine_fold_rise(ps)$geometric_mean_fold_rise,vaccine_fold_rise(prepared)$geometric_mean_fold_rise),'GMFR invariant to unit scaling')
check(identical(vaccine_response(ps,cf)$n_responders,vaccine_response(prepared,cfg)$n_responders),'Responder outcomes invariant when units and thresholds scale together')

# Assay censoring is explicit and does not use the numeric payload of a censored record.
cens<-data;cens$titers$QUALIFIER[1]<-'BLQ';cens$titers$AVAL[1]<-NA;cens$titers$QUALIFIER[2]<-'ALQ';cens$titers$AVAL[2]<-NA
pc<-vaccine_prepare(cens,cfg);check(cell(pc$titer_summary,visit='Baseline')$n_evaluable==3&&cell(pc$titer_summary)$n_evaluable==2,'Excluded censoring reduces evaluability')
cf<-cfg;cf$blq_policy<-'half_lloq';cf$alq_policy<-'uloq';pc<-vaccine_prepare(cens,cf)
check(pc$pairs$baseline_value[pc$pairs$USUBJID=='A1']==1&&pc$pairs$post_value[pc$pairs$USUBJID=='A1']==200,'Configured LLOQ/2 and ULOQ substitution applied')
check(cell(pc$titer_summary,visit='Baseline')$n_substituted==1&&cell(pc$titer_summary)$n_substituted==1,'Substitutions disclosed per visit')
cf$blq_policy<-'lloq';pc<-vaccine_prepare(cens,cf);check(pc$pairs$baseline_value[pc$pairs$USUBJID=='A1']==2,'LLOQ substitution distinct from LLOQ/2')
bad<-cens;bad$titers$LLOQ[1]<-NA;check(throws(vaccine_prepare(bad,cf),'requires a positive LLOQ'),'Missing required censoring limit rejected')

react <- vaccine_reactogenicity(prepared)
rcell<-function(d,arm='A',dose='Dose 1')d[d$ARM==arm&d$DOSE==dose,,drop=FALSE]
r<-rcell(react$rates);check(r$n_dosed==4&&r$n_complete==2&&r$n_partial==1&&r$n_unassessed==1,'Complete/partial/allmissing diary populations known answer')
check(r$n_denominator==2&&r$n_reaction==1&&r$percent==50&&r$n_partial_positive==1,'Complete-window incidence excludes and discloses partial positive')
check(r$n_missing_day_assessments==5,'Absent rows and blank grades counted as missing days')
cf<-cfg;cf$react_denominator<-'observed';pr<-vaccine_prepare(data,cf);r<-rcell(vaccine_reactogenicity(pr)$rates);check(r$n_denominator==3&&r$n_reaction==2&&near(r$percent,200/3),'Observed policy uses at leastone assessedday and reports partial positives')
r<-rcell(react$rates,'B');check(r$n_dosed==2&&r$n_reaction==0&&r$percent==0&&r$upper_percent>0,'Zero-event comparator retained with exact upper bound')
r<-rcell(react$rates,'B','Dose 2');check(r$n_dosed==0&&is.na(r$percent),'Arm/dose with no actual administrations retained without fake zero rate')
dist<-rcell(react$distribution);check(sum(dist$n_grade[dist$scope=='Complete-window maximum'])==2&&sum(dist$n_grade[dist$scope=='Observed maximum over available days'])==3,'Separate complete/observed max-grade distributions')
maxima<-prepared$diary_maxima;check(maxima$observed_max_grade[maxima$USUBJID=='A1'&maxima$DOSE=='Dose 1']==2,'Repeated daily reactions counted by participant maximum once')
check(is.na(maxima$observed_max_grade[maxima$USUBJID=='A4']),'Allmissing diary has unknown maximum rather than0')
daily<-vaccine_daily(prepared);r<-rcell(daily);check(identical(r$n_assessed,c(3L,2L,2L))&&near(r$percent,c(100/3,50,50)),'Daily assessed denominators and event rates known answers')
cf<-cfg;cf$day_start<-1;cf$day_end<-1;pr<-vaccine_prepare(data,cf);r<-rcell(vaccine_reactogenicity(pr)$rates);check(r$n_complete==2&&r$n_reaction==1,'Single-day inclusive window works')

# Zero-evaluable cells and populations remain reviewable, including actual figure construction.
empty<-data;empty$titers<-empty$titers[FALSE,];empty$diary<-empty$diary[FALSE,];pe<-vaccine_prepare(empty,cfg)
check(all(pe$titer_summary$n_evaluable==0)&&all(is.na(pe$titer_summary$geometric_mean)),'Entirely absent immunogenicity rows retain each population/visit')
check(all(vaccine_reactogenicity(pe)$rates$n_denominator==0),'Entirely absent diaries retain dosed roster without negative imputation')
empty<-data;empty$participants$IMMFL[empty$participants$ARM=='B']<-'N';empty$participants$SAFEFL[empty$participants$ARM=='B']<-'N';pn<-vaccine_prepare(empty,cfg)
check(all(pn$titer_summary$n_population[pn$titer_summary$ARM=='B']==0)&&all(vaccine_reactogenicity(pn)$rates$n_dosed[vaccine_reactogenicity(pn)$rates$ARM=='B']==0),'Empty individual arms retain zero population cells')
for(id in cfg$outputs) {
 out<-vaccine_output(id,prepared,cfg)
 check(is.list(out$title)&&length(out$components)>=2&&all(vapply(out$components,function(z)!is.null(z$value),logical(1))),paste(id,'complete runner components'))
 for(component in out$components)if(inherits(component$value,'ggplot')){ggplot2::ggplot_build(component$value);check(TRUE,paste(id,'figure builds'))}
}
for(id in c('titer_plot','diary_profile')) {out<-vaccine_output(id,pe,cfg);ggplot2::ggplot_build(out$components[[1]]$value);check(TRUE,paste(id,'empty figure renders honestly'))}

# Strict contracts prevent silent merges, nonfinite summaries and misleading denominators.
bad<-data;bad$participants<-rbind(bad$participants,bad$participants[1,]);check(throws(vaccine_prepare(bad,cfg),'duplicate keys'),'Duplicate participants rejected')
bad<-data;bad$participants$IMMFL[1]<-'Unknown';check(throws(vaccine_prepare(bad,cfg),'canonical Y or N'),'Unknown population flag rejected')
bad<-data;bad$titers<-rbind(bad$titers,bad$titers[1,]);check(throws(vaccine_prepare(bad,cfg),'duplicate keys'),'Duplicate participant visit rejected')
bad<-data;bad$titers$UNIT[1]<-'mg/mL';check(throws(vaccine_prepare(bad,cfg),'Mixed or unexpected units'),'Mixed units cannot be silently subset')
bad<-data;bad$titers$AVAL[1]<-0;check(throws(vaccine_prepare(bad,cfg),'positive'),'Nonpositive exact titer rejected')
bad<-data;bad$titers$AVAL[1]<-Inf;check(throws(vaccine_prepare(bad,cfg),'finite numeric'),'Infinite titer rejected')
bad<-data;bad$titers$USUBJID[1]<-'orphan';check(throws(vaccine_prepare(bad,cfg),'orphan'),'Orphan titer rejected')
bad<-data;bad$titers$QUALIFIER[1]<-'unknown';check(throws(vaccine_prepare(bad,cfg),'QUALIFIER'),'Unknown assay qualifier rejected')
bad<-data;bad$titers$QUALIFIER[1]<-'MISSING';check(throws(vaccine_prepare(bad,cfg),'cannot have an AVAL'),'Conflicting missing qualifier/value rejected')
bad<-data;bad$titers$LLOQ[1]<-300;check(throws(vaccine_prepare(bad,cfg),'quantification limits'),'Inverted assay limits rejected')
bad<-data;bad$doses<-rbind(bad$doses,bad$doses[1,]);check(throws(vaccine_prepare(bad,cfg),'duplicate keys'),'Duplicate actual dose rejected')
bad<-data;bad$diary<-rbind(bad$diary,bad$diary[1,]);check(throws(vaccine_prepare(bad,cfg),'duplicate keys'),'Duplicate daily diary rejected')
bad<-data;bad$diary$GRADE[1]<-4;check(throws(vaccine_prepare(bad,cfg),'max_grade'),'Above-scale grade rejected')
bad<-data;bad$diary$GRADE[1]<-1.5;check(throws(vaccine_prepare(bad,cfg),'whole numbers'),'Fractional grade rejected')
bad<-data;bad$diary$DAY[1]<-.5;check(throws(vaccine_prepare(bad,cfg),'whole numbers'),'Fractional diary day rejected')
bad<-data;bad$diary$DOSE[1]<-'Not given';check(throws(vaccine_prepare(bad,cfg),'orphan doses'),'Diary without actual dose rejected')
cf<-cfg;cf$day_start<-3;check(throws(vaccine_prepare(data,cf),'ordered'),'Reversed window rejected')
cf<-cfg;cf$followup_visits<-'Baseline';check(throws(vaccine_prepare(data,cf),'distinct'),'Baseline reused as followup rejected')
cf<-cfg;cf$fold_threshold<-1;check(throws(vaccine_prepare(data,cf),'must exceed 1'),'Nonrise fold threshold rejected')
cf<-cfg;cf$confidence<-0;check(throws(vaccine_prepare(data,cf),'confidence'),'Invalid configured confidence rejected')
check(throws(vaccine_output('unsupported',prepared,cfg),'not selected'),'Unselected output rejected')

# Direct-run guards match the guided provider, including nonselected population rows.
bad<-data;bad$titers$QUALIFIER[1]<-'BLQ';check(throws(vaccine_prepare(bad,cfg),'cannot have an AVAL'),'Censored numeric payload cannot override qualifier')
bad$titers$AVAL[1]<-NA;bad$titers$LLOQ[1]<-NA;check(throws(vaccine_prepare(bad,cfg),'even when excluded'),'BLQ bound required even with exclusion')
bad<-data;bad$titers$QUALIFIER[1]<-'ALQ';bad$titers$AVAL[1]<-NA;bad$titers$ULOQ[1]<-NA;check(throws(vaccine_prepare(bad,cfg),'even when excluded'),'ALQ bound required even with exclusion')
bad<-data;bad$titers$AVAL[1]<-1;check(throws(vaccine_prepare(bad,cfg),'within supplied'),'EXACT below LLOQ rejected')
bad<-data;bad$titers$AVAL[1]<-201;check(throws(vaccine_prepare(bad,cfg),'within supplied'),'EXACT above ULOQ rejected')
bad<-data;bad$titers$LLOQ[1]<-10;bad$titers$ULOQ[1]<-10;check(throws(vaccine_prepare(bad,cfg),'LLOQ < ULOQ'),'Equal quantification limits rejected')
bad<-data;bad$participants$IMMFL[1]<-'N';bad$titers<-rbind(bad$titers,bad$titers[1,]);check(throws(vaccine_prepare(bad,cfg),'duplicate'),'Selected duplicate outside immunogenicity population rejected')
bad<-data;extra<-bad$diary[1,];extra$DAY<-50;bad$diary<-rbind(bad$diary,extra,extra);check(throws(vaccine_prepare(bad,cfg),'duplicate'),'Duplicate diary outside selected window rejected')
bad<-data;bad$participants$IMMFL<-'N';check(throws(vaccine_prepare(bad,cfg),'No participants'),'Entirely empty immunogenicity population rejected')
bad<-data;bad$participants$SAFEFL<-'N';check(throws(vaccine_prepare(bad,cfg),'No safety-population'),'Entirely empty dose denominator roster rejected')
cf<-cfg;cf$followup_visits<-paste0('Visit',1:51);check(throws(vaccine_prepare(data,cf),'1–50'),'Oversized visit list rejected')
cf<-cfg;cf$outputs<-'reactogenicity';cf$symptoms<-paste0('Symptom',1:50);cf$day_end<-60
large<-data;large$participants<-data.frame(USUBJID=paste0('P',1:400),ARM='A',IMMFL='Y',SAFEFL='Y');large$doses<-data.frame(USUBJID=large$participants$USUBJID,DOSE='Dose 1');large$diary<-data$diary[FALSE,]
check(throws(vaccine_prepare(large,cf),'1,000,000'),'Expected-grid guard runs before constructing over one million assessments')
check(identical(vaccine_fold_response(c(40,39.99999999,1e308,1e308),c(10,10,1e308,1e307),4),c(TRUE,FALSE,FALSE,TRUE)),'Fold boundaries exact, near-below remains false and extreme multiplication avoids overflow')

# Missing intermediate visits/days remain gaps in the actual plot layer data.
cf<-cfg;cf$followup_visits<-c('Missing visit','Post');pr<-vaccine_prepare(data,cf)
built<-ggplot2::ggplot_build(vaccine_output('titer_plot',pr,cf)$components[[1]]$value)
check(nrow(built$data[[2]])==6&&sum(is.na(built$data[[2]]$y))==2,'Titer line retains missing interior visit gaps')
gap<-data;gap$diary$GRADE[gap$diary$DAY==1]<-NA;pr<-vaccine_prepare(gap,cfg)
built<-ggplot2::ggplot_build(vaccine_output('diary_profile',pr,cfg)$components[[1]]$value)
check(any(is.na(built$data[[1]]$y)),'Daily line retains missing intermediate day gaps')
# Large recipient counts exercise vector grouping, not repeated scans of the full grid.
volume<-list(participants=data.frame(USUBJID=paste0('S',seq_len(10000)),ARM='Large arm',IMMFL='N',SAFEFL='Y'))
volume$doses<-data.frame(USUBJID=volume$participants$USUBJID,DOSE='Dose 1')
volume$diary<-expand.grid(USUBJID=volume$participants$USUBJID,DAY=0:2,stringsAsFactors=FALSE);volume$diary$DOSE<-'Dose 1';volume$diary$SYMPTOM<-'Pain';volume$diary$GRADE<-volume$diary$DAY
cf<-cfg;cf$outputs<-c('reactogenicity','diary_profile');cf$dose_labels<-'Dose 1'
pr<-vaccine_prepare(volume,cf)
check(nrow(pr$diary_maxima)==10000&&all(pr$diary_maxima$observed_max_grade==2)&&all(pr$diary_maxima$complete_window),'Thirty-thousand-assessment volume case groups maxima correctly')

# Capacity safeguards do not silently change the population, window or estimand.
cf<-cfg;cf$outputs<-'immunogenicity';cf$followup_visits<-paste0('Visit',1:50)
large<-list(participants=data.frame(USUBJID=paste0('I',1:20000),ARM='A',IMMFL='Y',SAFEFL='N'),titers=data$titers[FALSE,])
check(throws(vaccine_prepare(large,cf),'full eligible population'),'Oversized immunogenicity grid rejected before allocating 1.02 million rows')
large$participants<-data.frame(USUBJID=paste0('I',1:51),ARM=paste0('Arm',1:51),IMMFL='Y',SAFEFL='N')
check(throws(vaccine_prepare(large,cf),'up to 50 distinct arm labels'),'Arm mapping capacity is explicit')
# Three doses and nine symptoms require nine readable figures, covering all 27 panels.
cf<-cfg;cf$outputs<-'diary_profile';cf$dose_labels<-c('Dose 1','Dose 2','Dose 3');cf$symptoms<-c('Pain',paste0('Symptom',1:8))
pr<-vaccine_prepare(data,cf);out<-vaccine_output('diary_profile',pr,cf)
plots<-lapply(Filter(function(x)inherits(x$value,'ggplot'),out$components),`[[`,'value')
check(length(plots)==9,'Daily figures paginate separately per dose and at most four symptoms')
coverage<-character()
for(plot in plots) {
 check(length(unique(plot$data$DOSE))==1&&length(unique(plot$data$SYMPTOM))<=4,'One dose and at most four symptoms per actual plot')
 built<-ggplot2::ggplot_build(plot);check(nrow(built$layout$layout)<=4,'Rendered plot has at most four panels')
 cells<-unique(plot$data[c('DOSE','SYMPTOM')]);coverage<-c(coverage,paste(match(cells$DOSE,cf$dose_labels),match(cells$SYMPTOM,cf$symptoms),sep=':'))
}
expected<-expand.grid(dose=1:3,symptom=1:9)
check(length(coverage)==27&&setequal(coverage,paste(expected$dose,expected$symptom,sep=':')),'Every requested dose/symptom panel appears exactly once, including empty assessments')
tables<-lapply(Filter(function(x)is.data.frame(x$value)&&'DAY'%in%names(x$value),out$components),`[[`,'value')
check(length(tables)==1&&nrow(tables[[1]])==2*3*9*3,'Pagination preserves the full daily arm/dose/symptom/day table')

# Rich independent synthetic fixture shipped with the module: all six outputs build.
if(file.exists('vaccine/examples/example_settings.json')) {
 settings<-jsonlite::fromJSON('vaccine/examples/example_settings.json')
 for(key in c('followup_visits','dose_labels','symptoms'))settings[[key]]<-strsplit(settings[[key]],'\n',fixed=TRUE)[[1]]
 feeds<-setNames(lapply(c('participants','titers','doses','diary'),function(name)read.csv(file.path('vaccine/examples',paste0(name,'.csv')),check.names=FALSE,stringsAsFactors=FALSE)),c('participants','titers','doses','diary'))
 fixture<-vaccine_prepare(feeds,settings)
 for(id in settings$outputs) {out<-vaccine_output(id,fixture,settings);for(z in out$components)if(inherits(z$value,'ggplot'))ggplot2::ggplot_build(z$value);check(TRUE,paste('Rich fixture',id))}
}
# Structural SAS export check only: no native SAS execution is claimed here.
# Follow macro block nesting so an unrelated earlier guard cannot satisfy this check.
sas_response_guarded <- function(text, marker) {
 text<-gsub('/\\*.*?\\*/','',text,perl=TRUE)
 positions<-gregexpr(marker,text,fixed=TRUE)[[1]]
 if(length(positions)!=1L||positions[[1]]<1L)return(FALSE)
 prefix<-substr(text,1L,positions[[1]]-1L)
 pattern<-'(?is)%if\\s+[^;]*?%then\\s+%do\\s*;|%do\\s*;|%end\\s*;'
 tokens<-regmatches(prefix,gregexpr(pattern,prefix,perl=TRUE))[[1]]
 stack<-logical()
 for(token in tokens) {
  if(grepl('^%end',token,ignore.case=TRUE)) {
   if(!length(stack))return(FALSE)
   stack<-head(stack,-1L)
  } else stack<-c(stack,grepl('^%if\\s+&_vax_response\\s*>\\s*0\\s+%then',token,ignore.case=TRUE,perl=TRUE))
 }
 any(stack)
}
sas<-paste(readLines('vaccine/reference.sas',warn=FALSE,encoding='UTF-8'),collapse='\n')
classification_markers<-c("if response_rule='threshold' then do;","else if response_rule in ('fold_rise','conditional') then do;")
table_markers<-c('data vax_response;','set _vax_pair_counts;','n_denominator=n_response_evaluable;n_event=n_responders;')
check(all(vapply(classification_markers,function(m)sas_response_guarded(sas,m),logical(1))),'SAS response classification is guarded by selected response output')
check(all(vapply(table_markers,function(m)sas_response_guarded(sas,m),logical(1))),'SAS response table and rate calculation are guarded by selected response output')
unguarded_sas<-gsub('%if &_vax_response>0 %then %do;','%if 1=1 %then %do;',sas,fixed=TRUE)
check(!any(vapply(c(classification_markers,table_markers),function(m)sas_response_guarded(unguarded_sas,m),logical(1))),'Structural SAS regression rejects removed selected-output guards')
cat(sprintf('PASS: %d vaccine numerical, boundary, missingness, metamorphic, output and SAS structural checks.\n',count))
