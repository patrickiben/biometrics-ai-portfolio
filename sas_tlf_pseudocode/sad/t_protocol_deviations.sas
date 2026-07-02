/******************************************************************************
* TABLE     : t_protocol_deviations  (Single Ascending Dose)
* TITLE     : Important Protocol Deviations by Category and Dose Cohort
* POPULATION: All Enrolled Participants (ENRLFL='Y')
* INPUT     : ADDV (protocol deviation domain) + ADSL flags
* NOTE      : PSEUDOCODE. Counts = PARTICIPANTS with >=1 deviation (distinct
*             USUBJID), NOT deviation rows. n (%) per column; % denom =
*             enrolled N per column. SAD: parallel ascending-dose cohorts, ONE
*             treatment per participant; columns = TRT01A = assigned dose level
*             (placebo often pooled). Deviation category/term from ADDV
*             (DVDECOD/DVCAT) -- includes dose-escalation/stopping-rule and
*             PK-sampling-window deviations relevant to ascending cohorts.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=SAD);                      /* -> TRTVAR=TRT01A, TRTNVAR=TRT01AN */

%bign(ds=adam.adsl, trtvar=&TRTVAR, trtn=&TRTNVAR, popfl=ENRLFL, out=_bign);

/* important deviations only; treatment carried on ADDV from ADSL merge.
   Keep enrolled participants; use IMPDVFL (important deviation flag).            */
data addv; set adam.addv(where=(IMPDVFL='Y')); run;

/*--- 1) "Any important deviation" overall row (distinct participants) ---------*/
%aecount(ds=addv, trtvar=&TRTVAR, popden=_bign, where=%str(IMPDVFL='Y'),
         byvars=%str(_dummy), out=_any);      /* _dummy=1 -> overall row     */

/*--- 2) by deviation category (DVCAT), distinct participants within category --*/
%aecount(ds=addv, trtvar=&TRTVAR, popden=_bign, where=%str(IMPDVFL='Y'),
         byvars=%str(DVCAT), out=_cat);

/*--- 3) by category*term (DVCAT*DVDECOD), distinct participants ---------------*/
%aecount(ds=addv, trtvar=&TRTVAR, popden=_bign, where=%str(IMPDVFL='Y'),
         byvars=%str(DVCAT DVDECOD), out=_cattm);

/*--- ordering: category by Total-column participant count desc; term within ---*/
proc sql;
  create table _catord as
    select DVCAT, sum(nsubj) as catn from _cat group by DVCAT;
  create table _tmord as
    select DVCAT, DVDECOD, sum(nsubj) as tmn from _cattm
    group by DVCAT, DVDECOD;
quit;

/*--- assemble report shell: Any -> Category -> indented Term --------------*/
data _rep;
  set _any(in=a) _cat(in=c) _cattm(in=t);
  length term $200;
  if a then do; term='Participants with any important deviation'; level=0; end;
  else if c then do; term=DVCAT;            level=1; end;
  else do; term='   '||DVDECOD;             level=2; end;
  /* value = catx(' ', put(nsubj,4.), cats('(',put(100*nsubj/N,5.1),'%)'))   */
run;
proc transpose data=_rep out=_wide; by catn tmn level term; id &TRTNVAR; var value; run;

%tfltitle(num=14.1.5, type=Table,
          text=%str(Important Protocol Deviations by Category and Dose Cohort),
          pop=All Enrolled Participants,
          foot=%str(A participant with multiple deviations is counted once at each level. Important deviations per ADDV (IMPDVFL). Column = assigned dose level (TRT01A); placebo may be pooled. Percentages based on enrolled N per dose level.));
proc report data=_wide nowd split='|';
  columns catn tmn level term ("Dose Level" /* dose cols + Total */);
  define catn / order descending noprint;
  define tmn  / order descending noprint;
  define level/ order noprint;
  define term / order 'Deviation Category|  Description' width=44 flow;
run;
