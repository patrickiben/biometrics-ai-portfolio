/*====================================================================================
  tm_macros.sas  -  TRIALMON: a deterministic SAS macro library for unattended
                    early-phase trial-monitoring automation (no AI).
  ------------------------------------------------------------------------------------
  Loop : scheduler -> ingest -> FRESHNESS GATE -> GUARD -> checks -> roll-up -> digest,
         + a tier-2 urgent ALERT on a de-duplicated RED finding, always closed by a
         HEARTBEAT. Built for "covering while on leave"; the standing monitoring backbone.
  Prefix  : %tm_<name>.  Tested concept: Base SAS 9.4. No third-party packages.
  Honest  : these macros DETECT, PACKAGE and EMAIL pre-specified deterministic flags.
            They DO NOT triage, interpret, or adjudicate. A flag is a prompt for a human;
            the medical monitor and the covering biostatistician decide.
  Validate: validate the threshold logic + scheduling wrapper as study programs; keep
            anything REPORTED independently double-programmed.
  v2 - corrected after an independent SAS/clinical review (see README, "Change log").
====================================================================================*/

%global TM_STUDY TM_RUNID TM_RUNDT TM_OUT TM_LOG TM_STATE TM_RC TM_STATUS TM_FRESH_OK TM_BACKUP;

/*==== %tm_init : initialise a run (paths, options, run id, persistent state lib) =====*/
%macro tm_init(study=, root=, smtp=, statelib=, backup=);
  %let TM_STUDY = &study;
  %let TM_RUNDT = %sysfunc(datetime(), e8601dt19.);
  %let TM_RUNID = &study._%sysfunc(datetime(), b8601dn15.);
  %let TM_OUT   = &root/out;
  %let TM_LOG   = &root/logs;
  %let TM_RC    = 0;            /* run return code: 0 ok, >0 problem (fail loud)        */
  %let TM_STATUS= GREEN;        /* GREEN < AMBER < RED < ERROR                          */
  %let TM_FRESH_OK = 1;
  %let TM_BACKUP = &backup;     /* watchdog / fail-loud recipient                      */
  options nodate nonumber noquotelenmax;
  %if %length(&smtp) %then %do; options emailsys=smtp emailhost="&smtp" emailport=25; %end;
  %if %length(&statelib) %then %do; libname tmstate "&statelib"; %let TM_STATE = tmstate; %end;
  %else %let TM_STATE = work;
  %put NOTE: [TRIALMON] init study=&TM_STUDY run=&TM_RUNID out=&TM_OUT;
%mend tm_init;

/*==== %tm_assert : FAIL LOUD. For an unattended job "no news" must never be good news.
       On a false condition: set TM_RC, force status to ERROR, email the backup, write a
       FAILED heartbeat, and (if abort=Y) stop. Wrap every fragile step in this.        */
%macro tm_assert(cond=, msg=, abort=N);
  %if not (&cond) %then %do;
    %let TM_RC = 1; %let TM_STATUS = ERROR;
    %put ERROR: [TRIALMON] ASSERT FAILED: &msg;
    data _null_; file "&TM_OUT/heartbeat.txt";
      put "&TM_STUDY FAILED " "%sysfunc(datetime(),datetime19.)" " &msg"; run;
    %if %length(&TM_BACKUP) %then %do;
      data _null_; file "&TM_OUT/_fail_body.txt"; put "TRIALMON job FAILED: &msg"; put "Run &TM_RUNID - the unattended monitor needs attention. Do not assume GREEN."; run;
      %tm_email(to=&TM_BACKUP, subject=TRIALMON FAILURE - &TM_STUDY - &msg, bodyfile=&TM_OUT/_fail_body.txt, importance=High);
    %end;
    %if &abort=Y %then %abort cancel;
  %end;
%mend tm_assert;

/*==== %tm_guard : before any safety threshold runs, assert the expected columns exist,
       are numeric, and pass a range-sanity check (catches a unit change / renamed var).*/
%macro tm_guard(ds=, numvars=, sanity=);
  %tm_assert(cond=%sysfunc(exist(&ds)), msg=missing dataset &ds, abort=Y);
  %let i=1;
  %do %while(%scan(&numvars,&i,%str( )) ne );
    %let v=%scan(&numvars,&i,%str( ));
    %let dsid=%sysfunc(open(&ds)); %let vn=%sysfunc(varnum(&dsid,&v)); %let vt=;
    %if &vn %then %let vt=%sysfunc(vartype(&dsid,&vn)); %let rc=%sysfunc(close(&dsid));
    %tm_assert(cond=(&vn>0), msg=&ds missing expected column &v);
    %tm_assert(cond=(%superq(vt)=N), msg=&ds column &v is not numeric (unit/type change?));
    %let i=%eval(&i+1);
  %end;
  %if %length(&sanity) %then %do;
    proc sql noprint; select count(*) into :_bad trimmed from &ds where not (&sanity); quit;
    %tm_assert(cond=(&_bad=0), msg=&ds failed range-sanity (&sanity) on &_bad rows - possible unit error);
  %end;
%mend tm_guard;

/*==== %tm_latest : newest dated file in a dir (unambiguous "latest export") ===========*/
%macro tm_latest(dir=, ext=sas7bdat, outvar=tm_latest_path);
  %global &outvar;
  filename _tmdir "&dir";
  data _tm_files;
    length fname $260 fpath $400; format mtime datetime19.;
    did = dopen("_tmdir");
    if did then do i = 1 to dnum(did);
      fname = dread(did, i);
      if lowcase(scan(fname,-1,'.')) = lowcase("&ext") then do;
        fpath = catx('/', "&dir", fname);
        rc = filename("_tmf", fpath); fid = fopen("_tmf");
        if fid then do; mtime = input(finfo(fid,"Last Modified"), anydtdtm40.); rc=fclose(fid); end; /* numeric dttm - sorts chronologically */
        rc = filename("_tmf"); output;
      end;
    end;
    rc = dclose(did);
  run;
  proc sql noprint; select fpath into :&outvar trimmed from _tm_files having mtime = max(mtime); quit;
  %put NOTE: [TRIALMON] latest &ext in &dir -> &&&outvar;
%mend tm_latest;

/*==== %tm_freshness : THE GATE (run FIRST). One coherent per-feed pass -> &out. A
       MISSING / dead feed is the worst case and must flag (never silently pass green). */
%macro tm_freshness(feeds=, tsvar=_loaddttm, maxage=26, out=_tm_fresh);
  data &out; length feed $41 status $7 sev $6; format newest age_h 8.; stop; run;
  %let i=1;
  %do %while(%scan(&feeds,&i,%str( )) ne );
    %let f=%scan(&feeds,&i,%str( ));
    %if %sysfunc(exist(&f)) %then %do;
      proc sql noprint; select max(&tsvar) into :_mx trimmed from &f; quit;
    %end; %else %let _mx=.;
    data _r; length feed $41 status $7 sev $6; format newest age_h 8.;
      feed="&f"; newest=&_mx;
      if missing(newest) then do; status="MISSING"; age_h=.; sev="AMBER"; end;     /* dead feed -> flag loud */
      else do; age_h=(datetime()-newest)/3600;
               if age_h > &maxage then do; status="STALE"; sev="AMBER"; end;
               else do; status="FRESH"; sev="GREEN"; end; end;
    run;
    proc append base=&out data=_r force; run;
    %let i=%eval(&i+1);
  %end;
  proc sql noprint; select sum(sev ne "GREEN")>0 into :_anystale trimmed from &out; quit;
  %if &_anystale %then %do; %let TM_FRESH_OK=0; %if &TM_STATUS=GREEN %then %let TM_STATUS=AMBER; %let TM_RC=1;
    %put WARNING: [TRIALMON] one or more feeds STALE/MISSING - GREEN on stale data is worse than RED; %end;
%mend tm_freshness;

/*==== %tm_status : roll a flagged dataset's worst sev into the run status (exist-guarded)*/
%macro tm_status(in=, sevvar=sev);
  %if %sysfunc(exist(&in))=0 %then %do; %put WARNING: [TRIALMON] &in missing - status skipped; %tm_assert(cond=0, msg=check output &in missing); %return; %end;
  proc sql noprint;
    select case when sum(&sevvar="RED")>0 then "RED"
                when sum(&sevvar="AMBER")>0 then "AMBER" else "GREEN" end
      into :_worst trimmed from &in;
  quit;
  %if &_worst=RED and &TM_STATUS ne ERROR %then %let TM_STATUS=RED;
  %else %if &_worst=AMBER and &TM_STATUS in (GREEN) %then %let TM_STATUS=AMBER;
  %put NOTE: [TRIALMON] %superq(in) worst=&_worst run-status=&TM_STATUS;
%mend tm_status;

/*====================================================================================
  SAFETY CHECKS  ->  each returns a flagged dataset with a SEV column. Deterministic.
====================================================================================*/

/* ---- Hy's-Law / eDISH screening flag (CORRECTED) -----------------------------------
   RED if (ALT or AST > altmult x ULN) AND (TBili > bilmult x ULN).  STRICT '>'.
   NEVER downgraded by ALP: a high ALP does NOT exclude Hy's Law. Report the R-ratio
   (ALT/ULN over ALP/ULN) for CONTEXT only - hepatocellular when R>=5.  in: USUBJID +
   peak alt_x ast_x tbl_x alp_x (x-ULN).  Screening flag, NOT a diagnosis.            */
%macro tm_chk_hyslaw(in=, out=_tm_hyslaw, altmult=3, astmult=3, bilmult=2);
  data &out;
    set &in;
    length flag $60 sev $6;
    hy = ((alt_x > &altmult) or (ast_x > &astmult)) and (tbl_x > &bilmult);   /* strict > */
    if hy then do;
      r_ratio = divide(alt_x, alp_x);                      /* context only - never downgrades */
      length pattern $14; pattern = ifc(r_ratio>=5,"hepatocellular",ifc(r_ratio<=2,"cholestatic","mixed"));
      flag = catx(' ', "Hy's-Law pattern (", strip(pattern), "R=", put(r_ratio,4.1), ")");
      sev = "RED"; output;
    end;
  run;
  %put NOTE: [TRIALMON] Hy's-Law screen (SCREENING flag - ALP never downgrades a RED case);
%mend tm_chk_hyslaw;

/* ---- QTcF prolongation flags (ICH E14): 450 watch / 480 AMBER / 500 RED ------------*/
%macro tm_chk_qtcf(in=, out=_tm_qtcf, abs_red=500, dqt_red=60, abs_amb=480, dqt_amb=30, abs_low=450);
  data &out;
    set &in;
    length flag $40 sev $6;
    if QTCF > &abs_red or DQTCF > &dqt_red then sev="RED";
    else if QTCF > &abs_amb or DQTCF > &dqt_amb then sev="AMBER";
    else if QTCF > &abs_low then sev="GREEN";   /* tracked watch level */
    else delete;
    flag = cats("QTcF ",put(QTCF,4.)," / dQTcF ",put(DQTCF,4.));
    if sev ne "GREEN" then output;              /* alert AMBER/RED; GREEN-watch tracked but not alerted */
  run;
%mend tm_chk_qtcf;

/* ---- AE / SAE running tally by cohort. AETOXGR is CHARACTER in CDISC -> input() -----
   SAE -> AMBER by default (scope RED to SUSAR/related via AEREL if your team prefers). */
%macro tm_chk_ae(in=, out=_tm_ae);
  proc sql;
    create table &out as
    select COHORT,
           count(distinct case when AESER='Y' then USUBJID end)                  as n_sae_subj,
           sum(AESER='Y')                                                         as n_sae_evt,
           count(distinct case when input(AETOXGR,best.)>=3 then USUBJID end)     as n_g3_subj,
           count(distinct USUBJID)                                               as n_ae_subj,
           case when sum(AESER='Y')>0 or count(distinct case when input(AETOXGR,best.)>=3 then USUBJID end)>0
                then 'AMBER' else 'GREEN' end as sev length=6,
           catx(' ','cohort',COHORT,'-',put(calculated n_sae_evt,3.),'SAE,',put(calculated n_g3_subj,3.),'Gr>=3') as flag length=40
    from &in where TRTEMFL='Y' group by COHORT;
  quit;
%mend tm_chk_ae;

/* ---- Candidate-DLT tally vs 3+3. Group by the DOSE-LEVEL key (default COHORT - assert
   COHORT==dose level for this study, else pass dosevar=DOSELVL). Against an ADJUDICATED
   DLTFL and a completed window (DLT_EVAL='Y'). Does NOT make the escalation decision.  */
%macro tm_chk_dlt(in=, out=_tm_dlt, dosevar=COHORT);
  proc sql;
    create table &out as
    select &dosevar,
           sum(DLT_EVAL='Y')               as n_eval,
           sum(DLTFL='Y' and DLT_EVAL='Y') as n_dlt,
           case when calculated n_dlt >= 2 then 'RED'
                when calculated n_dlt = 1  then 'AMBER' else 'GREEN' end as sev length=6,
           catx(' ','dose',&dosevar,'DLT',put(calculated n_dlt,2.),'/',put(calculated n_eval,2.)) as flag length=40
    from &in group by &dosevar;
  quit;
  %put NOTE: [TRIALMON] DLT tally vs 3+3 - flags the count; does NOT make the escalation call;
%mend tm_chk_dlt;

/* ---- Labs / vitals out-of-range & PCS ----------------------------------------------*/
%macro tm_chk_labs(in=, out=_tm_labs);
  data &out; set &in; length flag $40 sev $6;
    if PCSFL='Y' then do; flag=cats(PARAM," PCS"); sev="AMBER"; output; end;
  run;
%mend tm_chk_labs;

/*==== OPERATIONAL CHECKS =============================================================*/
%macro tm_chk_enroll(in=, out=_tm_enroll, kri=0.80);
  data &out; set &in; length flag $60 sev $6;
    pct = divide(N_ENROLLED, N_PLANNED_TO_DATE);
    if pct < &kri then do; sev="AMBER"; flag=cats("Enrollment ",put(pct,percent7.1)," < KRI ",put(&kri,percent7.0)); end;
    else do; sev="GREEN"; flag=cats("Enrollment ",put(pct,percent7.1)," (on track)"); end;
    output;
  run;
%mend tm_chk_enroll;
%macro tm_chk_queries(in=, out=_tm_qry, age_amb=30);
  proc sql; create table &out as
    select sum(OPEN_FL='Y') as n_open, sum(OPEN_FL='Y' and QUERY_AGE_DAYS>&age_amb) as n_aged,
           case when sum(OPEN_FL='Y' and QUERY_AGE_DAYS>&age_amb)>0 then 'AMBER' else 'GREEN' end as sev length=6,
           catx(' ',put(calculated n_open,4.),'open,',put(calculated n_aged,4.),'aged >&age_amb.d') as flag length=40
    from &in; quit;
%mend tm_chk_queries;
%macro tm_chk_visits(in=, out=_tm_vis);
  data &out; set &in; length flag $40 sev $6;
    if missing(ACTDT) and PLANDT < today() then do; flag=cats("Overdue ",strip(VISIT)); sev="AMBER"; output; end;
    else if not missing(ACTDT) and abs(ACTDT-PLANDT) > WINDOW_DAYS then do; flag=cats("Out-of-window ",strip(VISIT)); sev="AMBER"; output; end;
  run;
%mend tm_chk_visits;
%macro tm_chk_ixrs(clin=, ixrs=, out=_tm_ixrs);
  proc sql; create table &out as
    select coalesce(a.USUBJID,b.USUBJID) as USUBJID, a.TRT01P, b.IXRS_TRT,
           case when a.USUBJID is null then 'In IXRS, not in clinical DB'
                when b.USUBJID is null then 'Randomized, missing in IXRS'
                when a.TRT01P ne b.IXRS_TRT then 'Treatment mismatch' else '' end as flag length=40,
           'AMBER' as sev length=6
    from &clin a full join &ixrs b on a.USUBJID=b.USUBJID where calculated flag ne ''; quit;
  %put NOTE: [TRIALMON] IXRS reconciliation - discrepancies escalate to DM/unblinded pharmacist, never auto-resolved;
%mend tm_chk_ixrs;

/*==== %tm_evidence : per-RED-participant one-page PDF (eDISH + lab trajectory) ============
   in: the RED hyslaw dataset (USUBJID, alt_x..); lab: full lab history for the plot.   */
%macro tm_evidence(in=, lab=, out=);
  %let out=%sysfunc(coalescec(&out,&TM_OUT/evidence_&TM_RUNID..pdf));
  ods pdf file="&out" style=journal; options nobyline;
  proc sql noprint; select distinct USUBJID into :_subs separated by ' ' from &in; quit;
  %if %length(&_subs)=0 %then %do; ods pdf close; %return; %end;
  /* eDISH scatter with 3xULN / 2xULN reference lines, RED participant highlighted */
  proc sgplot data=&lab;
    title "Evidence packet - eDISH (peak ALT vs peak total bilirubin, x-ULN) - Run &TM_RUNID";
    scatter x=alt_x y=tbl_x / group=red_fl markerattrs=(symbol=circlefilled);
    refline 3 / axis=x lineattrs=(pattern=shortdash); refline 2 / axis=y lineattrs=(pattern=shortdash);
    xaxis label="peak ALT (x ULN)"; yaxis label="peak total bilirubin (x ULN)";
  run;
  /* per-participant lab trajectory */
  %let j=1;
  %do %while(%scan(&_subs,&j,%str( )) ne );
    %let su=%scan(&_subs,&j,%str( ));
    proc sgplot data=&lab(where=(USUBJID="&su"));
      title "Participant &su - lab trajectory (x ULN by visit)";
      series x=visitnum y=alt_x / markers; series x=visitnum y=ast_x / markers;
      series x=visitnum y=tbl_x / markers; series x=visitnum y=alp_x / markers;
    run; %let j=%eval(&j+1);
  %end;
  title; ods pdf close;
  %put NOTE: [TRIALMON] evidence packet -> &out;
%mend tm_evidence;

/*==== DE-DUPLICATION (key MUST include participant so distinct participants are not collapsed)*/
%macro tm_dedup(in=, key=, out=_tm_new);
  %if %sysfunc(exist(&TM_STATE..tm_seen))=0 %then %do;
    data &TM_STATE..tm_seen; length sigkey $200; format first_dttm datetime19.; first_dttm=.; stop; run; %end;
  proc sql;
    create table &out as select a.* from &in a where a.&key not in (select sigkey from &TM_STATE..tm_seen);
    insert into &TM_STATE..tm_seen (sigkey, first_dttm)
      select distinct &key, datetime() from &in where &key not in (select sigkey from &TM_STATE..tm_seen);
  quit;
%mend tm_dedup;

/*==== NOTIFICATION ===================================================================*/
%macro tm_email(to=, cc=, subject=, bodyfile=, attach=, importance=Normal);
  filename _tmmail email to=(&to) %if %length(&cc) %then cc=(&cc); subject="&subject"
     %if %length(&attach) %then %if %sysfunc(fileexist(&attach)) %then attach=("&attach"); importance="&importance";
  data _null_; file _tmmail;
    %if %length(&bodyfile) %then %do; infile "&bodyfile" length=l; input line $varying2000. l; put line; %end;
    %else %do; put "&TM_STUDY &subject"; %end;
  run;
  filename _tmmail clear;
  %put NOTE: [TRIALMON] emailed "&subject" to &to;
%mend tm_email;

/* tier-1 digest: ODS report + RAG status, always with a heartbeat line. Body created here. */
%macro tm_digest(title=, sections=, to=, dest=pdf);
  %let _f=&TM_OUT/digest_&TM_RUNID..&dest;
  %let _imp=Normal; %if &TM_STATUS=RED or &TM_STATUS=ERROR %then %let _imp=High;
  ods &dest file="&_f" style=journal; ods escapechar='^';
  title "^S={font_size=14pt}&title - %sysfunc(today(),date9.) - [&TM_STATUS]";
  %let i=1; %do %while(%scan(&sections,&i,%str( )) ne ); %let s=%scan(&sections,&i,%str( ));
    %if %sysfunc(exist(&s)) %then %do; proc print data=&s noobs label; run; %end; %let i=%eval(&i+1); %end;
  data _hb; length txt $200;
    txt=cats("HEARTBEAT ran ",put(datetime(),datetime19.)," SYSCC=&TM_RC data-fresh=",ifc(symgetn('TM_FRESH_OK'),'OK','STALE/MISSING')); run;
  proc print data=_hb noobs; run; title; ods &dest close;
  data _null_; file "&TM_OUT/_digest_body.txt";
    put "&TM_STUDY daily digest [&TM_STATUS] - %sysfunc(today(),date9.) - see attached PDF."; run;
  %tm_email(to=&to, subject=&TM_STUDY digest [&TM_STATUS] %sysfunc(today(),date9.),
            bodyfile=&TM_OUT/_digest_body.txt, attach=&_f, importance=&_imp);
%mend tm_digest;

/* tier-2 urgent ALERT (de-identified body; severity routing; contact-the-MM; evidence) */
%macro tm_alert(in=, to=, backup=, alias=, cc=, mm_name=, mm_phone=, evidence=);
  %if %sysfunc(exist(&in))=0 %then %return;
  proc sql noprint; select count(*) into :_n trimmed from &in where sev="RED"; quit;
  %if &_n=0 %then %do; %put NOTE: [TRIALMON] no RED findings to alert; %return; %end;
  data _null_; file "&TM_OUT/_alert_body.txt";
    put "URGENT safety alert - &TM_STUDY - auto-sent " "%sysfunc(datetime(),datetime19.)";
    put "A pre-specified deterministic threshold was met. SCREENING flag, NOT a diagnosis. The medical monitor adjudicates.";
    put " "; put ">> CONTACT THE MEDICAL MONITOR NOW: &mm_name &mm_phone";
    put ">> Acknowledge within 30 minutes (reply to confirm receipt)."; put ">> Evidence packet attached."; put " ";
  run;
  data _null_; set &in(where=(sev="RED")); file "&TM_OUT/_alert_body.txt" mod; put "  - " flag; run;
  %tm_email(to=&to, cc=&backup &alias &cc, subject=RED ALERT - &TM_STUDY - safety threshold met - ACTION REQUIRED,
            bodyfile=&TM_OUT/_alert_body.txt, attach=&evidence, importance=High);
  %if &TM_STATUS ne ERROR %then %let TM_STATUS=RED;
  %put WARNING: [TRIALMON] RED alert dispatched (primary+backup+alias);
%mend tm_alert;

/*==== %tm_heartbeat : the dead-man's switch. An INDEPENDENT watcher (separate host/cron,
       e.g. tm_watchdog.sh) escalates if this ping stops. "No news" is never "good news".*/
%macro tm_heartbeat(records=, watcher_to=);
  %if %sysfunc(exist(&TM_STATE..tm_heartbeat))=0 %then %do;
    data &TM_STATE..tm_heartbeat; length runid $40 status $7; format run_dttm datetime19.; run_dttm=.; stop; run; %end;
  proc sql; insert into &TM_STATE..tm_heartbeat (runid, run_dttm, status)
              values ("&TM_RUNID", %sysfunc(datetime()), "&TM_STATUS"); quit;
  data _null_; file "&TM_OUT/heartbeat.txt";
    put "&TM_STUDY &TM_STATUS " "%sysfunc(datetime(),datetime19.)" " SYSCC=&TM_RC N=&records FRESH=&TM_FRESH_OK"; run;
  %put NOTE: [TRIALMON] heartbeat written - external watcher (&watcher_to) alerts if it stops;
%mend tm_heartbeat;

/*==== End of tm_macros.sas. See monitor_driver.sas, tm_watchdog.sh, tm_config.sas, and
      the README for the catalog, parameters, the config pattern, and validation notes. */
