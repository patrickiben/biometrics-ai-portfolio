/*====================================================================================
  monitor_driver.sas  -  the daily unattended monitoring job (Study CP-101).
  Schedule in batch under a SERVICE account (not a personal login):
     Windows : schtasks /create /tn "CP101_monitor" /tr "run_monitor.bat" /sc DAILY /st 06:00 /ru SVC-BIOSTAT
     Linux   : 0 6 * * 1-5  /opt/jobs/run_monitor.sh    # sas -sysin monitor_driver.sas -batch
  run_monitor.bat: sas.exe -sysin monitor_driver.sas -log "logs\cp101_%date%.log" -nosplash -batch -noterminal
  Flow: INGEST -> FRESHNESS GATE -> GUARD -> checks -> roll-up -> DIGEST, + a tier-2
  ALERT on a de-duplicated RED finding, always closed by a HEARTBEAT. Fails LOUD.
====================================================================================*/
%include "/opt/trialmon/tm_macros.sas";
%include "/opt/trialmon/tm_config.sas";     /* per-study constants: paths, recipients, MM, thresholds, feeds */

/* 1. init (values come from tm_config.sas) ---------------------------------------- */
%tm_init(study=&CFG_STUDY, root=&CFG_ROOT, smtp=&CFG_SMTP, statelib=&CFG_STATE, backup=&CFG_BACKUP);

libname sdtm "&CFG_SDTM"; libname adam "&CFG_ADAM"; libname safe "&CFG_SAFE"; libname ixrs "&CFG_IXRS";

/* 2. FRESHNESS GATE first - stale-green is worse than red -------------------------- */
%tm_freshness(feeds=&CFG_FEEDS, tsvar=_loaddttm, maxage=&CFG_MAXAGE);
%tm_status(in=_tm_fresh);

/* 3. GUARD - assert expected columns exist, are numeric, pass range-sanity --------- */
%tm_guard(ds=adam.adlb_edish, numvars=alt_x ast_x tbl_x alp_x, sanity=(0<=alt_x<=400 and 0<=tbl_x<=60));
%tm_guard(ds=adam.adeg, numvars=QTCF DQTCF, sanity=(200<=QTCF<=700));

/* 4. deterministic checks ---------------------------------------------------------- */
%tm_chk_hyslaw(in=adam.adlb_edish, altmult=&CFG_ALTM, bilmult=&CFG_BILM);
%tm_chk_qtcf  (in=adam.adeg);
%tm_chk_ae    (in=adam.adae);
%tm_chk_dlt   (in=adam.adsl_dlt, dosevar=&CFG_DOSEVAR);
%tm_chk_enroll(in=adam.enroll_summary, kri=&CFG_ENROLL_KRI);
%tm_chk_queries(in=safe.queries, age_amb=&CFG_QRY_AGE);
%tm_chk_visits(in=adam.expected_visits);
%tm_chk_ixrs  (clin=adam.adsl, ixrs=ixrs.rand);

/* 5. roll worst severity into the run status --------------------------------------- */
%tm_status(in=_tm_hyslaw); %tm_status(in=_tm_qtcf); %tm_status(in=_tm_ae);
%tm_status(in=_tm_dlt);    %tm_status(in=_tm_enroll); %tm_status(in=_tm_vis); %tm_status(in=_tm_ixrs);

/* 6. tier-1 digest to the cover (ALWAYS sent - silence is never assumed) ------------ */
%tm_digest(title=CP-101 Daily Safety Digest,
           sections=_tm_fresh _tm_enroll _tm_ae _tm_dlt _tm_qtcf _tm_hyslaw _tm_qry _tm_vis,
           to=&CFG_SUPPORT, dest=pdf);

/* 7. tier-2 urgent alert ONLY on a NEW (de-duplicated, PARTICIPANT-keyed) RED finding ---
   sigkey includes the participant/dose so a SECOND participant's RED is never suppressed.     */
data _tm_red;
  set _tm_hyslaw(in=a) _tm_qtcf(in=b) _tm_dlt(in=c);
  length subj $40 sigkey $200;
  if a or b then subj = USUBJID; else if c then subj = strip(vvalue(&CFG_DOSEVAR));
  where sev="RED";
  sigkey = catx('|', "&TM_STUDY", coalescec(subj,''), flag);
run;
%tm_dedup(in=_tm_red, key=sigkey, out=_tm_red_new);

/* build the per-participant evidence packet, then alert (attaches it if it exists) ------ */
%tm_evidence(in=_tm_red_new, lab=adam.adlb_edish, out=&TM_OUT/evidence_&TM_RUNID..pdf);
%tm_alert(in=_tm_red_new, to=&CFG_SUPPORT, backup=&CFG_BACKUP, alias=&CFG_ALIAS, cc=&CFG_PM,
          mm_name=&CFG_MM_NAME, mm_phone=&CFG_MM_PHONE, evidence=&TM_OUT/evidence_&TM_RUNID..pdf);

/* 8. HEARTBEAT - records counted with a single, closed handle (no leak) ------------- */
%let _did=%sysfunc(open(adam.adae)); %let _n=0;
%if &_did %then %let _n=%sysfunc(attrn(&_did,nlobs)); %let _rc=%sysfunc(close(&_did));
%tm_heartbeat(records=&_n, watcher_to=&CFG_BACKUP);

/* Friday: weekly status pack + a numeric manager one-pager ------------------------- */
%if %sysfunc(weekday(%sysfunc(today())))=6 %then %do;
  %tm_digest(title=CP-101 Weekly Status, sections=_tm_enroll _tm_ae _tm_dlt _tm_qry _tm_vis, to=&CFG_SUPPORT &CFG_MGR, dest=pdf);
%end;

%put NOTE: [TRIALMON] run complete - status=&TM_STATUS rc=&TM_RC;
endsas;
