/******************************************************************************
* LISTING   : l_sae_death  (Single Ascending Dose)
* TITLE     : Listing of Serious Adverse Events and Deaths by Dose Level
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADAE (AESER='Y' OR death: AESDTH='Y'/AEOUT='FATAL');
*             ADSL (DTHDT merged in for the Death Date column)
* NOTE      : PSEUDOCODE. One row per qualifying AE record (serious and/or
*             fatal), ordered by ascending dose (TRT01AN) then participant then
*             onset. Shows onset day, duration, severity, serious/fatal flags,
*             TEAE, relationship, action, outcome, seriousness criteria, and death
*             date. Listings are participant-level detail (not aggregated counts).
*             SAD design: treatment = TRT01A (= dose level); single dose, so
*             onset study day is relative to the single dosing day. Placebo
*             pooled per ADaM TRT01A bookkeeping. SAEs are the cohort dose-
*             escalation stopping signals (SRC/DSMB review).
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=SAD);                      /* -> TRTVAR=TRT01A             */

/* serious and/or fatal AE records; merge DTHDT (death date) from ADSL --------- */
proc sort data=adam.adae(where=(SAFFL='Y' and (AESER='Y' or AESDTH='Y' or upcase(AEOUT)='FATAL')))
          out=_sae;  by USUBJID;  run;
proc sort data=adam.adsl(keep=USUBJID DTHDT) out=_dth;  by USUBJID;  run;

data ae;
  merge _sae(in=a) _dth;  by USUBJID;  if a;   /* keep SAE rows; bring ADSL DTHDT */
  length subjid $20 trt $40 relday $8 durn 8 sev $12 ser $4 fatal $4 te $4
         rel $20 acn $24 out $24 sercrit $40 dthdt $12;
  subjid  = scan(USUBJID,-1,'-');            /* short site-participant id            */
  trt     = &TRTVAR;                          /* dose level (TRT01A)             */
  sev     = put(AESEVN, aesev.);             /* MILD/MODERATE/SEVERE             */
  rel     = AREL;                            /* analysis relationship            */
  acn     = AEACN;                           /* action taken w/ study drug       */
  out     = AEOUT;                           /* outcome                          */
  ser     = ifc(AESER='Y','Yes','No');       /* serious flag                     */
  fatal   = ifc(AESDTH='Y','Yes','No');      /* fatal flag (AESDTH)              */
  te      = ifc(TRTEMFL='Y','Yes','No');     /* treatment-emergent flag          */
  relday  = ifc(missing(ASTDY),' ',put(ASTDY,4.));   /* study day of onset (vs single dose) */
  durn    = ADURN;                           /* AE duration in days              */
  /* seriousness criteria: concatenate the Y flags into a readable string        */
  length _c $200;  _c=' ';
  if AESDTH='Y'  then _c=catx('; ',_c,'Death');
  if AESLIFE='Y' then _c=catx('; ',_c,'Life-threatening');
  if AESHOSP='Y' then _c=catx('; ',_c,'Hospitalization');
  if AESDISAB='Y'then _c=catx('; ',_c,'Disability');
  if AESCONG='Y' then _c=catx('; ',_c,'Congenital anomaly');
  if AESMIE='Y'  then _c=catx('; ',_c,'Other medically important');
  sercrit = _c;
  dthdt   = ifc(missing(DTHDT),' ',put(DTHDT,yymmdd10.));  /* death date from ADSL DTHDT (NEVER AEENDTC); blank if non-fatal */
keep &TRTNVAR trt subjid AESOC AEDECOD ASTDT relday durn sev ser fatal te
     rel acn out sercrit dthdt;
run;

/* order by ascending dose (numeric TRT01AN), then participant, then onset       */
proc sort data=ae; by &TRTNVAR subjid ASTDT AEDECOD; run;

%tfltitle(num=16.2.7.2, type=Listing,
          text=%str(Listing of Serious Adverse Events and Deaths by Dose Level),
          pop=Safety Population,
          foot=%str(Includes events with AESER='Y' (serious) and/or AESDTH='Y' or a fatal outcome. TEAE = treatment-emergent (TRTEMFL=Y). Rel = analysis relationship to study drug. Death Date from ADSL DTHDT (blank if non-fatal). Treatment = dose level; single dose. MedDRA v27.0.));
proc report data=ae nowd split='*';
  columns &TRTNVAR trt subjid ('Adverse Event' AESOC AEDECOD)
          ('Onset*(Day)' relday) ('Dur*(d)' durn) sev ('Serious' ser) ('Fatal' fatal)
          ('TEAE' te) ('Relationship' rel) ('Action Taken' acn) ('Outcome' out)
          ('Seriousness Criteria' sercrit) ('Death*Date' dthdt);
  define &TRTNVAR / order noprint;             /* ascending-dose sort key (numeric) */
  define trt     / order 'Treatment*(Dose)' width=16;
  define subjid  / order 'Participant'   width=12;
  define AESOC   / display 'System Organ Class' width=22 flow;
  define AEDECOD / display 'Preferred Term'     width=22 flow;
  define relday  / display center width=6;
  define durn    / display center width=6;
  define sev     / display 'Severity'  width=10;
  define ser     / display center width=7;
  define fatal   / display center width=6;
  define te      / display center width=6;
  define rel     / display width=14 flow;
  define acn     / display 'Action*Taken' width=14 flow;
  define out     / display width=14 flow;
  define sercrit / display width=20 flow;
  define dthdt   / display center width=10;
  break after &TRTNVAR / page;                 /* one dose level per page block    */
run;
