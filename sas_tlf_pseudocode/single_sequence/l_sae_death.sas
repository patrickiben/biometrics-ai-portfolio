/******************************************************************************
* LISTING   : l_sae_death  (Single-/Fixed-Sequence, e.g. DDI)
* TITLE     : Listing of Serious Adverse Events and Deaths by Period
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADAE (AESER='Y' or AESDTH='Y')
* NOTE      : PSEUDOCODE. One row per qualifying SAE / death record, ordered by
*             participant then period then onset. Shows the fixed PERIOD (APERIODC)
*             and the analysis treatment in effect (TRTA, e.g. victim alone vs
*             victim + perpetrator); NO randomized sequence. Includes seriousness
*             criteria, onset/resolution study days, relationship, action, and
*             outcome (incl. death).
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=SINGLESEQ);     /* TRTVAR=TRTA; BYPERIOD=APERIOD APERIODC */

/* death date lives on ADSL -> merge DTHDT by USUBJID (never use AE end date) */
proc sql;
  create table sae0 as
    select a.*, s.DTHDT
    from adam.adae(where=(SAFFL='Y' and (AESER='Y' or AESDTH='Y'))) a
    left join adam.adsl s on a.USUBJID=s.USUBJID;
quit;

data sae;
  set sae0;
  length subjid $20 perc $24 trt $40 stdy endy $8 sev $12 rel $20
         acn $24 out $24 crit $60 dthdtc $12;
  subjid = scan(USUBJID,-1,'-');
  perc   = APERIODC;                         /* fixed period (col by-var)    */
  trt    = TRTA;                             /* treatment in effect in period*/
  sev    = put(AESEVN, aesev.);
  rel    = AREL;
  acn    = AEACN;
  out    = AEOUT;
  dthdtc = ifc(missing(DTHDT),' ',put(DTHDT, yymmdd10.));   /* death date (ADSL) */
  stdy   = ifc(missing(ASTDY),' ',put(ASTDY,4.));   /* onset study day      */
  endy   = ifc(missing(AENDY),' ',put(AENDY,4.));   /* resolution study day */
  /* seriousness criteria flags collapsed to one descriptive cell           */
  crit = catx('; ',
           ifc(AESDTH='Y','Death',''),       ifc(AESLIFE='Y','Life-threatening',''),
           ifc(AESHOSP='Y','Hospitalization',''), ifc(AESDISAB='Y','Disability',''),
           ifc(AESCONG='Y','Congenital anomaly',''), ifc(AESMIE='Y','Medically important',''));
keep subjid APERIOD perc trt AESOC AEDECOD stdy endy sev crit rel acn out dthdtc;
run;

proc sort data=sae; by subjid APERIOD ASTDT AEDECOD; run;

%tfltitle(num=16.2.7.3, type=Listing,
          text=Listing of Serious Adverse Events and Deaths by Period,
          pop=Safety Population,
          foot=%str(Includes events with AESER=Y or AESDTH=Y. Period 1 = reference; later period(s) = test condition. Seriousness Criteria = AESDTH/AESLIFE/AESHOSP/AESDISAB/AESCONG/AESMIE. Death Date from DTHDT (ADSL); blank for non-fatal SAEs. Rel = relationship to study drug per investigator/analysis. MedDRA v27.0.));
proc report data=sae nowd split='*';
  columns subjid perc trt ('Adverse Event' AESOC AEDECOD)
          ('Study Day' stdy endy) sev ('Seriousness Criteria' crit)
          ('Relationship' rel) ('Action Taken' acn) ('Outcome' out) ('Death*Date' dthdtc);
  define subjid / order 'Participant' width=12;
  define perc   / order 'Period'  width=16 flow;
  define trt    / display 'Treatment' width=18 flow;
  define AESOC  / display 'System Organ Class' width=22 flow;
  define AEDECOD/ display 'Preferred Term'     width=22 flow;
  define stdy   / display 'Onset*Day' center width=6;
  define endy   / display 'Resol.*Day' center width=6;
  define sev    / display 'Severity' width=10;
  define crit   / display width=20 flow;
  define rel    / display width=14 flow;
  define acn    / display width=16 flow;
  define out    / display width=16 flow;
  define dthdtc / display center width=12;
  break after subjid / skip;
run;
