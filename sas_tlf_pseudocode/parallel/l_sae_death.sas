/******************************************************************************
* LISTING   : l_sae_death  (Parallel-group)
* TITLE     : Listing of Serious Adverse Events and Deaths
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADAE (AESER='Y' OR death: AESDTH='Y'/AEOUT='FATAL')
* NOTE      : PSEUDOCODE. One row per qualifying AE record (serious and/or
*             fatal), ordered by treatment then participant then onset. Shows
*             seriousness criteria, relationship, action, outcome, and death
*             date. Listings are participant-level detail (not aggregated counts).
*             Parallel design: treatment = TRT01A (= dose level).
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=PARALLEL);                 /* -> TRTVAR=TRT01A             */

/* death date comes from ADSL (DTHDT); merge it onto the SAE records by USUBJID */
proc sort data=adam.adsl(keep=USUBJID DTHDT) out=_dth; by USUBJID; run;
proc sort data=adam.adae out=_adae; by USUBJID; run;

data ae;
  merge _adae(where=(SAFFL='Y' and (AESER='Y' or AESDTH='Y' or upcase(AEOUT)='FATAL')) in=a)
        _dth;
  by USUBJID;
  if a;
  length subjid $20 trt $40 relday $8 sev $12 rel $20 acn $24 out $24 te $4 sercrit $40 dthdt $12;
  subjid  = scan(USUBJID,-1,'-');            /* short site-participant id            */
  trt     = &TRTVAR;                          /* dose level (TRT01A)             */
  sev     = put(AESEVN, aesev.);             /* MILD/MODERATE/SEVERE             */
  rel     = AREL;                            /* analysis relationship            */
  acn     = AEACN;                           /* action taken w/ study drug       */
  out     = AEOUT;                           /* outcome                          */
  te      = ifc(TRTEMFL='Y','Yes','No');     /* treatment-emergent flag          */
  relday  = ifc(missing(ASTDY),' ',put(ASTDY,4.));   /* study day of onset       */
  /* seriousness criteria: concatenate the Y flags into a readable string        */
  length _c $200;  _c=' ';
  if AESDTH='Y'  then _c=catx('; ',_c,'Death');
  if AESLIFE='Y' then _c=catx('; ',_c,'Life-threatening');
  if AESHOSP='Y' then _c=catx('; ',_c,'Hospitalization');
  if AESDISAB='Y'then _c=catx('; ',_c,'Disability');
  if AESCONG='Y' then _c=catx('; ',_c,'Congenital anomaly');
  if AESMIE='Y'  then _c=catx('; ',_c,'Other medically important');
  sercrit = _c;
  dthdt   = ifc(missing(DTHDT),' ',put(DTHDT,yymmdd10.));  /* death date (ADSL/ADAE) */
keep trt subjid AESOC AEDECOD ASTDT relday sev te rel sercrit acn out dthdt;
run;

proc sort data=ae; by trt subjid ASTDT AEDECOD; run;

%tfltitle(num=16.2.7.2, type=Listing,
          text=%str(Listing of Serious Adverse Events and Deaths),
          pop=Safety Population,
          foot=%str(Includes events with AESER='Y' and/or a fatal outcome. Rel = analysis relationship to study drug. MedDRA v27.0.));
proc report data=ae nowd split='*';
  columns trt subjid ('Adverse Event' AESOC AEDECOD)
          ('Onset*(Day)' relday) sev ('TEAE' te)
          ('Seriousness Criteria' sercrit) ('Relationship' rel)
          ('Action Taken' acn) ('Outcome' out) ('Death*Date' dthdt);
  define trt     / order 'Treatment*(Dose)' width=16;
  define subjid  / order 'Participant'   width=12;
  define AESOC   / display 'System Organ Class' width=22 flow;
  define AEDECOD / display 'Preferred Term'     width=22 flow;
  define relday  / display center width=6;
  define sev     / display 'Severity'  width=10;
  define te      / display center width=6;
  define sercrit / display width=20 flow;
  define rel     / display width=14 flow;
  define acn     / display 'Action*Taken' width=14 flow;
  define out     / display width=14 flow;
  define dthdt   / display center width=10;
  break after trt / page;                      /* one treatment per page block     */
run;
