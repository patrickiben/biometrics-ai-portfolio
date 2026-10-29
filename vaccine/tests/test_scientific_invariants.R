source('vaccine/analysis.R')
cfg <- jsonlite::fromJSON('vaccine/examples/example_settings.json')
for (field in c('followup_visits','dose_labels','symptoms')) cfg[[field]]<-strsplit(cfg[[field]],'\n',fixed=TRUE)[[1]]
feeds<-setNames(lapply(c('participants','titers','doses','diary'),function(x)read.csv(paste0('vaccine/examples/',x,'.csv'),stringsAsFactors=FALSE,na.strings=c('','NA'))),c('participants','titers','doses','diary'))
reference<-vaccine_prepare(feeds,cfg)
checks<-0L
check<-function(x,msg){checks<<-checks+1L;if(!isTRUE(x))stop(msg,call.=FALSE);cat('PASS ',msg,'\n',sep='')}
near<-function(x,y) isTRUE(all.equal(x,y,check.attributes=FALSE,tolerance=1e-10))
# Compare summaries after independent row permutation in every feed.
set.seed(901)
permuted<-lapply(feeds,function(x)x[sample(nrow(x)),,drop=FALSE]);p<-vaccine_prepare(permuted,cfg)
check(near(reference$titer_summary,p$titer_summary),'All immunogenicity cells invariant to upload order')
check(near(vaccine_fold_rise(reference),vaccine_fold_rise(p)),'Pair construction invariant to independent feed ordering')
check(near(vaccine_reactogenicity(reference),vaccine_reactogenicity(p)),'Symptom incidence and maximum grades invariant to upload order')
check(near(vaccine_daily(reference),vaccine_daily(p)),'Daily denominator results invariant to upload order')
# Convert every assay value/limit and threshold together; dimensionless outcomes cannot change.
scaled<-feeds;for(field in c('AVAL','LLOQ','ULOQ')) scaled$titers[[field]]<-scaled$titers[[field]]*1000
scaled$titers$UNIT<-'scaled-AU/mL';cf<-cfg;cf$unit<-'scaled-AU/mL';cf$response_threshold<-cf$response_threshold*1000;cf$baseline_threshold<-cf$baseline_threshold*1000
p<-vaccine_prepare(scaled,cf)
check(near(reference$titer_summary$geometric_mean*1000,p$titer_summary$geometric_mean),'GMT respects a full unit conversion including limits')
check(near(vaccine_fold_rise(reference)$geometric_mean_fold_rise,vaccine_fold_rise(p)$geometric_mean_fold_rise),'GMFR remains dimensionless after rescaling')
a<-vaccine_response(reference,cfg);b<-vaccine_response(p,cf)
check(near(a$n_responders,b$n_responders)&&near(a$n_evaluable,b$n_evaluable),'Conditional response classification invariant to coherent unit conversion')
# Add one roster participant with no assay observations: known cases stay fixed and missingness grows.
extra<-feeds;new<-extra$participants[1,,drop=FALSE];new$USUBJID<-'NEW-MISSING';new$IMMFL<-'Y';new$SAFEFL<-'N';extra$participants<-rbind(extra$participants,new)
p<-vaccine_prepare(extra,cfg);target<-reference$titer_summary$ARM==new$ARM
check(near(reference$titer_summary$geometric_mean,p$titer_summary$geometric_mean),'Unmeasured roster participant does not dilute GMT')
check(all(p$titer_summary$n_population[target]==reference$titer_summary$n_population[target]+1)&&all(p$titer_summary$n_absent[target]==reference$titer_summary$n_absent[target]+1),'Absent observations increase population and absent counts explicitly')
a<-vaccine_response(reference,cfg);b<-vaccine_response(p,cfg);check(near(a$n_evaluable,b$n_evaluable)&&near(a$n_responders,b$n_responders),'Absent follow-up is not silently a nonresponse')
# Other-arm renaming cannot influence any numeric summaries or assumed control selection.
renamed<-feeds;renamed$participants$ARM<-paste0('Label: ',renamed$participants$ARM)
p<-vaccine_prepare(renamed,cfg)
check(near(reference$titer_summary$geometric_mean,p$titer_summary$geometric_mean),'No fixed placebo or vaccine arm label changes summary')
# Narrower CIs at lower confidence; estimates and denominators remain the same.
cf<-cfg;cf$confidence<-.9;p<-vaccine_prepare(feeds,cf)
check(near(reference$titer_summary$geometric_mean,p$titer_summary$geometric_mean)&&all(p$titer_summary$lower>=reference$titer_summary$lower,na.rm=TRUE)&&all(p$titer_summary$upper<=reference$titer_summary$upper,na.rm=TRUE),'Confidence setting changes interval width only')
cat('INDEPENDENT SCIENTIFIC REVIEW: ',checks,' metamorphic checks passed.\n',sep='')
