/******************************************************************************
* LISTING   : l_sae_death  (Multiple Ascending Dose)
* TITLE     : Listing of Serious Adverse Events and Deaths by Dose Level
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADAE (AESER='Y' or death: AESDTH='Y' / AEOUT=FATAL)
* NOTE      : PSEUDOCODE. One row per serious/fatal AE record, ordered by dose
*             level then participant then onset. Includes seriousness criteria,
*             relationship, action taken, outcome, and onset/resolution study
*             days. All serious and fatal events are listed regardless of
*             treatment-emergence (emergence flag shown for reference).
*             MAD design: page/section by dose level (TRT01A); onset study day
*             is relative to first dose so the event can be placed within the
*             multiple-dose period. Treatment/period vars come from ADaM.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=MAD);                       /* TRTVAR=TRT01A             */

/* death date from ADSL (DTHDT), merged on participant (never AEENDTC)          */
proc sort data=adam.adae out=_ae(where=(SAFFL='Y' and (AESER='Y' or AESDTH='Y' or upcase(AEOUT)='FATAL'))); by USUBJID; run;
proc sort data=adam.adsl(keep=USUBJID DTHDT) out=_dth; by USUBJID; run;

data sae;
  merge _ae(in=a) _dth;
  by USUBJID;
  if a;
  length subjid $20 trt $40 onsd $8 resd $8 sev $12 rel $20 acn $24 out $24
         te $4 dth $4 sercrit $60;
  subjid = scan(USUBJID,-1,'-');            /* short site-participant id        */
  trt    = &TRTVAR;                         /* dose level (= treatment)     */
  sev    = put(AESEVN, aesev.);             /* MILD/MODERATE/SEVERE         */
  rel    = AREL;                            /* analysis relationship        */
  acn    = AEACN;                           /* action taken w/ study drug   */
  out    = AEOUT;                           /* outcome                      */
  te     = ifc(TRTEMFL='Y','Yes','No');
  dth    = ifc(AESDTH='Y' or upcase(AEOUT)='FATAL','Yes','No');
  onsd   = ifc(missing(ASTDY),' ',put(ASTDY,4.));   /* onset day (rel first dose)   */
  resd   = ifc(missing(AENDY),' ',put(AENDY,4.));   /* resolution day               */
  /* concatenate seriousness criteria flags into one descriptive field      */
  length _c $200;  _c='';
  if AESDTH='Y' then _c=catx('; ',_c,'Death');
  if AESLIFE='Y' then _c=catx('; ',_c,'Life-threatening');
  if AESHOSP='Y' then _c=catx('; ',_c,'Hospitalization');
  if AESDISAB='Y' then _c=catx('; ',_c,'Disability');
  if AESCONG='Y' then _c=catx('; ',_c,'Congenital anomaly');
  if AESMIE='Y' then _c=catx('; ',_c,'Medically important');
  sercrit=_c;
keep &TRTNVAR trt subjid AESOC AEDECOD ASTDY onsd resd sev rel acn out te dth sercrit DTHDT;
run;

/* order by ascending dose level, then participant, then onset                   */
proc sort data=sae; by &TRTNVAR subjid ASTDY AEDECOD; run;

%tfltitle(num=16.2.7.2, type=Listing,
          text=Listing of Serious Adverse Events and Deaths by Dose Level,
          pop=Safety Population,
          foot=%str(All serious and fatal events listed regardless of treatment-emergence. Onset/resolution days relative to first dose. Rel = relationship to study drug per investigator/analysis. MedDRA v27.0.));
proc report data=sae nowd split='*';
  columns &TRTNVAR trt subjid ('Adverse Event' AESOC AEDECOD)
          ('Onset*(Day)' onsd) ('Resln*(Day)' resd) sev
          ('Seriousness Criteria' sercrit) ('Fatal' dth) ('Death*Date' DTHDT) ('TEAE' te)
          ('Relationship' rel) ('Action Taken' acn) ('Outcome' out);
  define &TRTNVAR / order noprint;          /* ascending-dose sort key      */
  define trt     / order 'Dose Level' width=18;
  define subjid  / order 'Participant'   width=12;
  define AESOC   / display 'System Organ Class' width=22 flow;
  define AEDECOD / display 'Preferred Term'     width=22 flow;
  define onsd    / display center width=6;
  define resd    / display center width=6;
  define sev     / display 'Severity' width=10;
  define sercrit / display width=22 flow;
  define dth     / display center width=6;
  define DTHDT   / display 'Death*Date' format=date9. width=10;
  define te      / display center width=6;
  define rel     / display width=14 flow;
  define acn     / display width=16 flow;
  define out     / display width=16 flow;
  break after &TRTNVAR / page;              /* one dose level per page block */
run;
