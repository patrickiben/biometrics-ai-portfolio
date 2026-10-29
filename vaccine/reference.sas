/* Native SAS REFERENCE ONLY: not executed, validated or numerically reconciled here.
   Generated inputs/settings are inert data sets, never user text expanded as SAS code.
   Required: WORK.PARTICIPANTS, TITERS, DOSES, DIARY, VAX_CONFIG (one row),
   VAX_VISITS(VISIT,ORDER; baseline first), VAX_DOSES(DOSE),
   VAX_SYMPTOMS(SYMPTOM), VAX_OUTPUTS(ID).
   Each selected assay/visit is prespecified upstream; no raw visit-window derivation.
   Definitions match vaccine/analysis.R: natural-log Student-t GMT/GMC/paired GMFR;
   exact two-sided Clopper-Pearson proportions; complete or observed diary denominators.
   No efficacy, protective-threshold, superiority or immunobridging conclusion is made.
   Assay values and protocol-assigned grades must undergo independent study review.
*/
%macro _vax_assert_empty(ds,message);
data _null_;
  if 0 then set &ds nobs=_vax_count;
  if _vax_count>0 then do; put "ERROR: &message"; abort cancel; end;
  stop;
run;
%mend;
%macro _vax_exact;
/* Input row variables: n_denominator, n_event, confidence. Percent units in output. */
alpha=1-confidence;
if n_denominator>0 then do;
  percent=100*n_event/n_denominator;
  if n_event=0 then lower_percent=0;
  else lower_percent=100*quantile('BETA',alpha/2,n_event,n_denominator-n_event+1);
  if n_event=n_denominator then upper_percent=100;
  else upper_percent=100*quantile('BETA',1-alpha/2,n_event+1,n_denominator-n_event);
  status='Estimated: exact Clopper-Pearson';
end;
else do; call missing(percent,lower_percent,upper_percent); status='Not estimable: zero denominator'; end;
drop alpha;
%mend;
%macro _vax_log_ci;
/* Input row variables: n_evaluable, mean_log, sd_log, confidence. */
call missing(estimate,lower,upper);
status='Not estimable: no evaluable observations';
if n_evaluable>0 then do;
  if not missing(mean_log) and mean_log>=constant('LOGSMALL') and mean_log<=constant('LOGBIG') then estimate=exp(mean_log);
  if missing(estimate) or estimate<=0 then status='Point estimate not estimable within numeric range';
  else do;
    status='Point estimate only: one evaluable observation';
    if n_evaluable>1 then do;
      half=quantile('T',(1+confidence)/2,n_evaluable-1)*sd_log/sqrt(n_evaluable);
      if mean_log-half>=constant('LOGSMALL') and mean_log+half<=constant('LOGBIG') then do;
        lower=exp(mean_log-half); upper=exp(mean_log+half);
        if sd_log=0 then status='Estimated; zero observed log variance'; else status='Estimated';
      end;
      else status='Interval not estimable within numeric range';
    end;
  end;
end;
drop half;
%mend;

%macro _vax_table(id,ds,label);
%local _vax_print;
proc sql noprint;select count(*) into :_vax_print trimmed from work.vax_outputs where ID="&id";quit;
%if &_vax_print>0 %then %do;title "&label";proc print data=&ds noobs;run;%end;
%mend;

%macro vaccine_reference;
%local _vax_immune _vax_react _vax_ncfg _vax_npop _vax_ndosed _vax_expected _vax_nsym _vax_ndays _vax_nlabels _vax_nvisits _vax_response _vax_narms;
proc sql noprint;
  select count(*) into :_vax_ncfg trimmed from work.vax_config;
  select count(distinct ARM) into :_vax_narms trimmed from work.participants;
  select count(*) into :_vax_immune trimmed from work.vax_outputs
    where ID in ('immunogenicity','fold_rise','response','titer_plot');
  select count(*) into :_vax_response trimmed from work.vax_outputs where ID='response';
  select count(*) into :_vax_react trimmed from work.vax_outputs
    where ID in ('reactogenicity','diary_profile');
quit;
%if &_vax_narms>50 %then %do;%put ERROR: This revision supports up to 50 distinct arm labels. Check the ARM mapping.;%abort cancel;%end;
%if &_vax_ncfg ne 1 %then %do; %put ERROR: VAX_CONFIG requires exactly one row.; %abort cancel; %end;
data _null_;set work.vax_outputs;
  if ID not in ('immunogenicity','fold_rise','response','titer_plot','reactogenicity','diary_profile') then do;put 'ERROR: Unknown vaccine output.';abort cancel;end;
run;
data _null_; set work.vax_config;
  if missing(confidence) or confidence<=0 or confidence>=1 then do;
    put 'ERROR: Confidence must lie strictly between zero and one.'; abort cancel;
  end;
run;
data _null_; set work.participants;
  if missing(USUBJID) or missing(ARM) or IMMFL not in ('Y','N') or SAFEFL not in ('Y','N') then do;
    put 'ERROR: Missing participant identifiers/arm or noncanonical population flags.'; abort cancel;
  end;
run;
proc sql;
  create table _vax_bad as select USUBJID from work.participants group by USUBJID having count(*)>1;
  create table _vax_arms as select distinct ARM from work.participants;
  create table vax_input_audit as
    select 'participants' as source length=20, 'All participants' as category length=100,count(*) as n_records from work.participants
    union all select 'participants','Immunogenicity population',count(*) from work.participants where IMMFL='Y'
    union all select 'participants','Safety population',count(*) from work.participants where SAFEFL='Y';
quit;
%_vax_assert_empty(_vax_bad,Duplicate participants);

%if &_vax_immune>0 %then %do;
data _null_; set work.vax_config;
  if missing(assay) or missing(antigen) or missing(unit) or missing(baseline_visit)
    or blq_policy not in ('exclude','half_lloq','lloq') or alq_policy not in ('exclude','uloq') then do;
    put 'ERROR: Invalid assay settings or quantification-limit policy.'; abort cancel;
  end;
run;
%if &_vax_response>0 %then %do;
data _null_;set work.vax_config;
  if response_rule not in ('threshold','fold_rise','conditional')
    or (response_rule in ('threshold','conditional') and (missing(response_threshold) or response_threshold<=0))
    or (response_rule in ('fold_rise','conditional') and (missing(fold_threshold) or fold_threshold<=1))
    or (response_rule='conditional' and (missing(baseline_threshold) or baseline_threshold<=0)) then do;
    put 'ERROR: Invalid prespecified response rule or threshold.';abort cancel;
  end;
run;
%end;
proc sql noprint;
  select count(*) into :_vax_nvisits trimmed from work.vax_visits;
  create table _vax_bad as select VISIT from work.vax_visits group by VISIT having count(*)>1;
quit;
%_vax_assert_empty(_vax_bad,Duplicate configured visit);
%if &_vax_nvisits<2 or &_vax_nvisits>51 %then %do;%put ERROR: Require baseline and 1-50 distinct follow-ups.;%abort cancel;%end;
proc sql noprint;
  select count(*) into :_vax_npop trimmed from work.participants where IMMFL='Y';
  create table _vax_bad as select t.USUBJID from work.titers t left join work.participants p on t.USUBJID=p.USUBJID where missing(p.USUBJID);
quit;
%if %sysevalf(&_vax_npop*&_vax_nvisits>1000000) %then %do;%put ERROR: Expected immunogenicity grid exceeds one million. Select fewer follow-up visits while retaining the full eligible population.;%abort cancel;%end;
%if &_vax_npop=0 %then %do; %put ERROR: No immunogenicity population.; %abort cancel; %end;
%_vax_assert_empty(_vax_bad,Orphan titer participant);
data _null_; set work.titers;
  if missing(USUBJID) or missing(ASSAY) or missing(ANTIGEN) or missing(UNIT) or missing(VISIT)
    or QUALIFIER not in ('EXACT','BLQ','ALQ','MISSING') then do;
    put 'ERROR: Missing titer keys or unsupported qualifier.'; abort cancel;
  end;
  if (not missing(LLOQ) and LLOQ<=0) or (not missing(ULOQ) and ULOQ<=0)
    or (not missing(LLOQ) and not missing(ULOQ) and LLOQ>=ULOQ) then do;
    put 'ERROR: Assay limits must be positive and strictly ordered.'; abort cancel;
  end;
  if QUALIFIER='EXACT' and (missing(AVAL) or AVAL<=0 or (not missing(LLOQ) and AVAL<LLOQ) or (not missing(ULOQ) and AVAL>ULOQ)) then do;
    put 'ERROR: EXACT value must be positive and inside supplied quantification limits.'; abort cancel;
  end;
  if QUALIFIER ne 'EXACT' and not missing(AVAL) then do;
    put 'ERROR: Leave AVAL missing for BLQ, ALQ and MISSING qualifiers.'; abort cancel;
  end;
  if (QUALIFIER='BLQ' and missing(LLOQ)) or (QUALIFIER='ALQ' and missing(ULOQ)) then do;
    put 'ERROR: Censored observations require the corresponding limit even when excluded.'; abort cancel;
  end;
run;
proc sql;
  create table _vax_selected as select t.* from work.titers t,work.vax_config c
    where t.ASSAY=c.assay and t.ANTIGEN=c.antigen and t.VISIT in (select VISIT from work.vax_visits);
  create table _vax_bad as select USUBJID,VISIT from _vax_selected group by USUBJID,VISIT having count(*)>1;
quit;
%_vax_assert_empty(_vax_bad,Duplicate selected participant visit);
proc sql;
  create table _vax_bad as select t.* from _vax_selected t,work.vax_config c where t.UNIT ne c.unit;
quit;
%_vax_assert_empty(_vax_bad,Mixed or unexpected assay units);
data _vax_selected;
  if _n_=1 then set work.vax_config(keep=blq_policy alq_policy);
  set _vax_selected;
  length analysis_status $40;
  value=.; analysis_status=cats('excluded_',lowcase(QUALIFIER));
  if QUALIFIER='EXACT' then do; value=AVAL; analysis_status='observed_exact'; end;
  if QUALIFIER='BLQ' and blq_policy='half_lloq' then do; value=LLOQ/2; analysis_status='substituted_half_lloq'; end;
  if QUALIFIER='BLQ' and blq_policy='lloq' then do; value=LLOQ; analysis_status='substituted_lloq'; end;
  if QUALIFIER='ALQ' and alq_policy='uloq' then do; value=ULOQ; analysis_status='substituted_uloq'; end;
  if value>0 then log_value=log(value); else log_value=.;
run;
proc sql;
  create table _vax_immune as
    select p.USUBJID,p.ARM,v.VISIT,v.ORDER as visit_order,t.value,t.log_value,
      coalescec(t.QUALIFIER,'ABSENT') as QUALIFIER length=10,
      coalescec(t.analysis_status,'absent_record') as analysis_status length=40
    from work.participants p cross join work.vax_visits v
      left join _vax_selected t on p.USUBJID=t.USUBJID and v.VISIT=t.VISIT
    where p.IMMFL='Y';
  create table _vax_immune_cells as select a.ARM,v.VISIT,v.ORDER as visit_order from _vax_arms a cross join work.vax_visits v;
  create table _vax_counts as
    select a.ARM,a.VISIT,a.visit_order,count(t.USUBJID) as n_population,
      sum(not missing(t.value)) as n_evaluable,
      sum(not missing(t.USUBJID) and t.QUALIFIER ne 'ABSENT') as n_records,
      sum(t.QUALIFIER='ABSENT') as n_absent,sum(t.QUALIFIER='MISSING') as n_missing_result,
      sum(t.QUALIFIER='BLQ') as n_blq,sum(t.QUALIFIER='ALQ') as n_alq,
      sum(index(t.analysis_status,'substituted_')=1) as n_substituted
    from _vax_immune_cells a left join _vax_immune t on a.ARM=t.ARM and a.VISIT=t.VISIT
    group by a.ARM,a.VISIT,a.visit_order;
quit;
proc means data=_vax_immune nway noprint;
  class ARM VISIT; var log_value;
  output out=_vax_log_stats(drop=_TYPE_ _FREQ_) mean=mean_log std=sd_log;
run;
proc sql;
  create table _vax_gmt as select a.*,s.mean_log,s.sd_log,c.confidence,c.assay,c.antigen,c.unit,c.blq_policy,c.alq_policy
    from _vax_counts a left join _vax_log_stats s on a.ARM=s.ARM and a.VISIT=s.VISIT cross join work.vax_config c
    order by a.ARM,a.visit_order;
quit;
data vax_gmt;
  length status $80;set _vax_gmt;
  n_not_evaluable=n_population-n_evaluable;
  %_vax_log_ci;
  geometric_mean=estimate;drop estimate mean_log sd_log;
run;
proc sql;
  create table _vax_pairs as select t.USUBJID,t.ARM,t.VISIT,t.visit_order,t.value as post_value,b.value as baseline_value,
    c.baseline_visit,c.confidence,c.response_rule,c.response_threshold,c.fold_threshold,c.baseline_threshold
    from _vax_immune t cross join work.vax_config c left join _vax_immune b
      on t.USUBJID=b.USUBJID and b.VISIT=c.baseline_visit
    where t.VISIT ne c.baseline_visit;
quit;
data _vax_pairs;set _vax_pairs;
  paired=not missing(post_value) and not missing(baseline_value);
  if paired then log_fold_rise=log(post_value)-log(baseline_value); else log_fold_rise=.;
  response_evaluable=0;responder=0;
  %if &_vax_response>0 %then %do;
  if response_rule='threshold' then do;
    response_evaluable=not missing(post_value);
    if response_evaluable then responder=(post_value>=response_threshold);
  end;
  else if response_rule in ('fold_rise','conditional') then do;
    response_evaluable=paired;
    if paired then do;
      if response_rule='conditional' and baseline_value<baseline_threshold then responder=(post_value>=response_threshold);
      else if baseline_value<=constant('BIG')/fold_threshold then responder=(post_value>=baseline_value*fold_threshold);
      else responder=0;
    end;
  end;
  %end;
run;
proc means data=_vax_pairs nway noprint;
  class ARM VISIT;var log_fold_rise;
  output out=_vax_fold_stats(drop=_TYPE_ _FREQ_) mean=mean_log std=sd_log;
run;
proc sql;
  create table _vax_pair_counts as select a.ARM,a.VISIT,a.visit_order,count(p.USUBJID) as n_population,
    sum(p.paired=1) as n_paired,sum(not missing(p.USUBJID) and missing(p.baseline_value)) as n_baseline_unavailable,
    sum(not missing(p.USUBJID) and missing(p.post_value)) as n_post_unavailable,
    sum(not missing(p.USUBJID) and missing(p.baseline_value) and missing(p.post_value)) as n_both_unavailable,
    sum(p.response_evaluable=1) as n_response_evaluable,sum(p.responder=1) as n_responders
    from _vax_immune_cells a cross join work.vax_config c left join _vax_pairs p on a.ARM=p.ARM and a.VISIT=p.VISIT
    where a.VISIT ne c.baseline_visit group by a.ARM,a.VISIT,a.visit_order;
  create table _vax_gmfr as select a.*,s.mean_log,s.sd_log,c.confidence,c.baseline_visit,c.assay,c.antigen
    from _vax_pair_counts a left join _vax_fold_stats s on a.ARM=s.ARM and a.VISIT=s.VISIT cross join work.vax_config c
    order by a.ARM,a.visit_order;
quit;
data vax_gmfr;length status $80;set _vax_gmfr;
  n_unpaired=n_population-n_paired;n_evaluable=n_paired;
  %_vax_log_ci;
  geometric_mean_fold_rise=estimate;
  drop estimate mean_log sd_log n_evaluable n_response_evaluable n_responders;
run;
%if &_vax_response>0 %then %do;
data vax_response;
  length status $80;
  if _n_=1 then set work.vax_config(keep=response_rule response_threshold fold_threshold baseline_threshold unit confidence baseline_visit);
  set _vax_pair_counts;
  n_not_evaluable=n_population-n_response_evaluable;n_unpaired=n_population-n_paired;
  n_denominator=n_response_evaluable;n_event=n_responders;
  %_vax_exact;
  drop n_event n_denominator n_baseline_unavailable n_post_unavailable n_both_unavailable;
run;
%end;
proc sql;
  insert into vax_input_audit select 'titers','Uploaded records',count(*) from work.titers;
  insert into vax_input_audit select 'titers','Other assay or antigen',count(*) from work.titers t,work.vax_config c where t.ASSAY ne c.assay or t.ANTIGEN ne c.antigen;
  insert into vax_input_audit select 'titers','Selected assay/antigen outside selected visits',count(*) from work.titers t,work.vax_config c where t.ASSAY=c.assay and t.ANTIGEN=c.antigen and t.VISIT not in (select VISIT from work.vax_visits);
  insert into vax_input_audit select 'titers','Selected records outside immunogenicity population',count(*) from _vax_selected t inner join work.participants p on t.USUBJID=p.USUBJID where p.IMMFL ne 'Y';
  insert into vax_input_audit select 'titers','Selected BLQ records',count(*) from _vax_immune where QUALIFIER='BLQ';
  insert into vax_input_audit select 'titers','Selected ALQ records',count(*) from _vax_immune where QUALIFIER='ALQ';
  insert into vax_input_audit select 'titers','Selected immunogenicity records',count(*) from _vax_immune where QUALIFIER ne 'ABSENT';
  insert into vax_input_audit select 'titers','Absent expected participant/visit records',count(*) from _vax_immune where QUALIFIER='ABSENT';
  insert into vax_input_audit select 'titers','Substituted selected records',count(*) from _vax_immune where index(analysis_status,'substituted_')=1;
quit;
%end;

%if &_vax_react>0 %then %do;
data _null_;set work.vax_config;
  if missing(day_start) or missing(day_end) or day_start ne int(day_start) or day_end ne int(day_end)
    or day_start < -1 or day_end>60 or day_start>day_end or missing(max_grade)
    or max_grade ne int(max_grade) or max_grade<1 or max_grade>5
    or react_denominator not in ('complete','observed') then do;
    put 'ERROR: Invalid diary window, grade scale or denominator policy.';abort cancel;
  end;
run;
proc sql;
  create table _vax_bad as select USUBJID,DOSE from work.doses group by USUBJID,DOSE having count(*)>1;
quit;
%_vax_assert_empty(_vax_bad,Duplicate actual administered dose);
proc sql;
  create table _vax_bad as select d.USUBJID from work.doses d left join work.participants p on d.USUBJID=p.USUBJID where missing(p.USUBJID);
quit;
%_vax_assert_empty(_vax_bad,Orphan administered dose);
proc sql;
  create table _vax_bad as select USUBJID,DOSE,SYMPTOM,DAY from work.diary group by USUBJID,DOSE,SYMPTOM,DAY having count(*)>1;
quit;
%_vax_assert_empty(_vax_bad,Duplicate daily diary key);
proc sql;
  create table _vax_bad as select r.* from work.diary r left join work.doses d on r.USUBJID=d.USUBJID and r.DOSE=d.DOSE where missing(d.USUBJID);
quit;
%_vax_assert_empty(_vax_bad,Diary without an actual administered dose);
data _null_;
  if _n_=1 then set work.vax_config(keep=max_grade);
  set work.diary;
  if missing(USUBJID) or missing(DOSE) or missing(SYMPTOM) or missing(DAY) or DAY ne int(DAY)
    or (not missing(GRADE) and (GRADE ne int(GRADE) or GRADE<0 or GRADE>max_grade)) then do;
    put 'ERROR: Invalid diary identifier, day or grade.';abort cancel;
  end;
run;
data _vax_days;set work.vax_config(keep=day_start day_end);do DAY=day_start to day_end;output;end;keep DAY;run;
proc sql noprint;
  create table _vax_recipients as select p.USUBJID,p.ARM,d.DOSE from work.participants p inner join work.doses d
    on p.USUBJID=d.USUBJID where p.SAFEFL='Y' and d.DOSE in (select DOSE from work.vax_doses);
  select count(*) into :_vax_ndosed trimmed from _vax_recipients;
  select count(*) into :_vax_nsym trimmed from work.vax_symptoms;
  select count(*) into :_vax_ndays trimmed from _vax_days;
  select count(*) into :_vax_nlabels trimmed from work.vax_doses;
quit;
%let _vax_expected=%sysevalf(&_vax_ndosed*&_vax_nsym*&_vax_ndays);
%if &_vax_nsym<1 or &_vax_nsym>50 or &_vax_nlabels<1 or &_vax_nlabels>50 %then %do;%put ERROR: Dose and symptom lists require 1-50 distinct labels.;%abort cancel;%end;
%if &_vax_ndosed=0 %then %do; %put ERROR: No selected safety-population dose recipients.;%abort cancel;%end;
%if %sysevalf(&_vax_expected>1000000) %then %do; %put ERROR: Expected diary grid exceeds one million. Select fewer doses or symptoms while retaining the prespecified window and population.;%abort cancel;%end;
proc sql;
  create table _vax_diary as select p.USUBJID,p.ARM,p.DOSE,s.SYMPTOM,d.DAY,r.GRADE,
    (not missing(r.USUBJID)) as record_present
    from _vax_recipients p cross join work.vax_symptoms s cross join _vax_days d
      left join work.diary r on p.USUBJID=r.USUBJID and p.DOSE=r.DOSE and s.SYMPTOM=r.SYMPTOM and d.DAY=r.DAY;
  create table vax_subject_max as select USUBJID,ARM,DOSE,SYMPTOM,count(*) as n_expected_days,
    count(GRADE) as n_assessed_days,sum(missing(GRADE)) as n_missing_days,sum(record_present=0) as n_absent_rows,
    (count(GRADE)=count(*)) as complete_window,max(GRADE) as observed_max_grade
    from _vax_diary group by USUBJID,ARM,DOSE,SYMPTOM;
  create table _vax_react_cells as select a.ARM,d.DOSE,s.SYMPTOM from _vax_arms a cross join work.vax_doses d cross join work.vax_symptoms s;
  create table _vax_react as select a.ARM,a.DOSE,a.SYMPTOM,count(m.USUBJID) as n_dosed,
    sum(m.complete_window=1) as n_complete,
    sum(m.n_assessed_days>0 and m.complete_window=0) as n_partial,
    sum(not missing(m.USUBJID) and m.n_assessed_days=0) as n_unassessed,
    sum(m.complete_window=0 and m.observed_max_grade>=1) as n_partial_positive,
    sum(m.n_missing_days) as n_missing_day_assessments,
    sum(m.complete_window=1 and m.observed_max_grade>=1) as complete_events,
    sum(m.n_assessed_days>0 and m.observed_max_grade>=1) as observed_events
    from _vax_react_cells a left join vax_subject_max m on a.ARM=m.ARM and a.DOSE=m.DOSE and a.SYMPTOM=m.SYMPTOM
    group by a.ARM,a.DOSE,a.SYMPTOM;
quit;
data vax_subject_max;
  if _n_=1 then set work.vax_config(keep=day_start day_end);
  set vax_subject_max;
run;
data vax_react;length status $80 interpretation $160;
  if _n_=1 then set work.vax_config(keep=confidence react_denominator day_start day_end);
  set _vax_react;
  if missing(n_missing_day_assessments) then n_missing_day_assessments=0;
  if react_denominator='complete' then do;
    n_denominator=n_complete;n_event=complete_events;
    interpretation='Reaction among participants with every window day assessed for this symptom';
  end;
  else do;
    n_denominator=n_complete+n_partial;n_event=observed_events;
    interpretation='Observed reaction among participants with at least one assessed day; incomplete diaries can miss reactions';
  end;
  %_vax_exact;
  n_reaction=n_event;drop n_event complete_events observed_events;
run;
data _vax_grades;
  set work.vax_config(keep=max_grade);
  length scope $45;
  do grade=0 to max_grade;
    scope='Complete-window maximum';output;
    scope='Observed maximum over available days';output;
  end;
  keep grade scope;
run;
proc sql;
  create table vax_max_dist as select a.ARM,a.DOSE,a.SYMPTOM,g.scope,g.grade,
    sum((g.scope='Complete-window maximum' and m.complete_window=1 and m.observed_max_grade=g.grade)
       or (g.scope='Observed maximum over available days' and m.n_assessed_days>0 and m.observed_max_grade=g.grade)) as n_grade,
    sum((g.scope='Complete-window maximum' and m.complete_window=1)
       or (g.scope='Observed maximum over available days' and m.n_assessed_days>0)) as n_denominator,
    sum(not missing(m.USUBJID) and m.n_assessed_days=0) as n_unassessed
    from _vax_react_cells a cross join _vax_grades g left join vax_subject_max m
      on a.ARM=m.ARM and a.DOSE=m.DOSE and a.SYMPTOM=m.SYMPTOM
    group by a.ARM,a.DOSE,a.SYMPTOM,g.scope,g.grade;
quit;
data vax_max_dist;set vax_max_dist;if n_denominator>0 then percent=100*n_grade/n_denominator;else percent=.;run;
proc sql;
  create table _vax_daily as select a.ARM,a.DOSE,a.SYMPTOM,days.DAY,count(g.USUBJID) as n_dosed,
    count(g.GRADE) as n_assessed,sum(not missing(g.USUBJID) and missing(g.GRADE)) as n_missing,
    sum(not missing(g.USUBJID) and g.record_present=0) as n_absent_rows,sum(g.GRADE>=1) as n_reaction
    from _vax_react_cells a cross join _vax_days days left join _vax_diary g
      on a.ARM=g.ARM and a.DOSE=g.DOSE and a.SYMPTOM=g.SYMPTOM and days.DAY=g.DAY
    group by a.ARM,a.DOSE,a.SYMPTOM,days.DAY;
quit;
data vax_daily;length status $80;
  if _n_=1 then set work.vax_config(keep=confidence);
  set _vax_daily;n_denominator=n_assessed;n_event=n_reaction;
  %_vax_exact;
  drop n_denominator n_event;
run;
proc sql;
  insert into vax_input_audit select 'diary','Uploaded daily records',count(*) from work.diary;
  insert into vax_input_audit select 'diary','Outside selected population/doses/symptoms/window',count(*) from work.diary d where not exists (select * from _vax_diary g where d.USUBJID=g.USUBJID and d.DOSE=g.DOSE and d.SYMPTOM=g.SYMPTOM and d.DAY=g.DAY);
  insert into vax_input_audit select 'diary','Selected daily records',count(*) from _vax_diary where record_present=1;
  insert into vax_input_audit select 'diary','Expected participant/dose/symptom/day assessments',count(*) from _vax_diary;
  insert into vax_input_audit select 'diary','Absent daily rows',count(*) from _vax_diary where record_present=0;
  insert into vax_input_audit select 'diary','Present rows with missing grades',count(*) from _vax_diary where record_present=1 and missing(GRADE);
  insert into vax_input_audit select 'diary','Explicit grade-zero assessments',count(*) from _vax_diary where GRADE=0;
quit;
%end;

/* Emit only requested reports. These macro flags come from fixed IDs, not user code. */
%local _vax_print;

%_vax_table(immunogenicity,vax_gmt,GMT / GMC by prespecified visit);
%_vax_table(fold_rise,vax_gmfr,Paired geometric mean fold rise);
%_vax_table(response,vax_response,Prespecified responder rates with exact confidence intervals);
%_vax_table(reactogenicity,vax_react,Solicited reactions and diary completeness);
%_vax_table(reactogenicity,vax_max_dist,Distinct complete-window and observed-maximum distributions);
%_vax_table(reactogenicity,vax_subject_max,Participant observed maxima and missing days);
%_vax_table(diary_profile,vax_daily,Daily reactions among assessed participants);
proc sql noprint;select count(*) into :_vax_print trimmed from work.vax_outputs where ID='titer_plot';quit;
%if &_vax_print>0 %then %do;
  title 'Immunogenicity visit trends: descriptive log-scale means';
  proc sgplot data=vax_gmt;series x=visit_order y=geometric_mean/group=ARM markers break;
    highlow x=visit_order low=lower high=upper/group=ARM;
    xaxis integer label='Prespecified visit order (see complete table)';yaxis type=log logbase=10 label='GMT / GMC';run;
  proc print data=vax_gmt noobs;run;
%end;
proc sql noprint;select count(*) into :_vax_print trimmed from work.vax_outputs where ID='diary_profile';quit;
%if &_vax_print>0 %then %do;
  title 'Daily observed reactions: missing assessments are not no reaction';
  proc sort data=vax_daily out=_vax_daily_plot;by DOSE SYMPTOM DAY ARM;run;
  proc sgpanel data=_vax_daily_plot;by DOSE;panelby SYMPTOM / columns=2 rows=2;
    series x=DAY y=percent/group=ARM markers break;
    rowaxis min=0 max=100 label='Observed reaction among assessed participants (%)';colaxis integer;run;
%end;
title 'Vaccine input and missingness audit: descriptive analyses only';proc print data=vax_input_audit noobs;run;
title;footnote;
%mend;
%vaccine_reference;
