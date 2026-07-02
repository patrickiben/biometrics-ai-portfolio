/******************************************************************************
* TABLE     : t_pk_conc_summary  (MAD - Multiple Ascending Dose)
* TITLE     : Summary of Plasma Drug Concentrations by Study Day, Nominal Time
*             and Dose Level
* POPULATION: PK Concentration Population (PKFL='Y')
* INPUT     : ADPC (AVAL = concentration; ATPTN/NRRELTM = nominal time within a
*             dosing interval; AVISIT/AVISITN = study day; PARAM/PARAMCD = analyte)
* NOTE      : PSEUDOCODE. MAD: parallel cohorts, REPEATED daily dosing; column =
*             TRT01A/TRT01AN (= dose level, placebo typically pooled). Because the
*             drug is given on multiple days, the row structure carries BOTH a
*             study-day dimension (AVISIT/AVISITN, e.g. Day 1 first dose vs the
*             last steady-state day Day N) and the nominal sampling time within
*             that day's dosing interval (ATPTN, 0..tau). This lets reviewers read
*             the Day-1 single-dose profile and the Day-N steady-state profile from
*             one table; the accumulation read-out (t_accumulation) and the
*             pre-dose trough comparison (steady-state attainment) draw on the same
*             ADPC records. Report arithmetic n, Mean, SD, CV%, Geo Mean, Geo CV%,
*             Median, Min, Max per day x time x dose. BLQ handled per analysis
*             convention (0 pre-first-dose, missing/half-LLOQ thereafter);
*             geometric stats require AVAL>0. Descriptive only.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=MAD);                       /* column = TRT01A (= dose)    */

%bign(ds=adam.adsl, trtvar=&TRTVAR, trtn=&TRTNVAR, popfl=PKFL, out=_bign);

/*--- pull scheduled (nominal-time) concentration records -----------------*/
data pc;
  set adam.adpc(where=(PKFL='Y'));
  /* study-day + within-interval nominal time (ADaM-provided, no re-derivation) */
  avisitn = AVISITN;              /* study day / PK profiling day (e.g. 1, N)  */
  atptn   = ATPTN;                /* nominal time within the dosing interval(h) */
  /* BLQ handling per SAP: AVAL already imputed in ADPC; flag for n counts      */
  blqfl = (ABLFL='Y');           /* below-LLOQ analysis flag                   */
  if AVAL>0 then logv = log(AVAL); /* log conc for geometric stats             */
run;

/*--- arithmetic summary per dose x analyte x study-day x nominal time -----*/
proc means data=pc noprint;
  class &TRTVAR &TRTNVAR PARAMCD PARAM avisitn AVISIT atptn;
  var AVAL;
  output out=_arith n=n mean=mean std=std min=min max=max median=med cv=cv;
run;

/*--- geometric summary on log scale (AVAL>0 only); back-transform ---------
   GeoMean = exp(mean_log); Geo CV% = 100*sqrt(exp(var_log)-1)              */
proc means data=pc(where=(AVAL>0)) noprint;
  class &TRTVAR &TRTNVAR PARAMCD avisitn atptn; var logv;  /* log(AVAL)      */
  output out=_geo mean=gmean_log std=gsd_log;              /* on logVAL     */
run;

/*--- build display strings, round to ADaM/assay decimal hints ------------*/
data _cont;
  merge _arith _geo;
  by &TRTVAR PARAMCD avisitn atptn;
  length stat $14 value $30;
  /* geomean = exp(gmean_log);  geocv = 100*sqrt(exp(gsd_log**2)-1)         */
  /* emit one row per statistic: n / Mean / SD / CV% / Geo Mean /           */
  /*   Geo CV% / Median / Min / Max  (loop or array, formatted per analyte) */
run;

/*--- stack day x time (rows) x dose level (cols) -------------------------*/
proc sort data=_cont; by PARAM PARAMCD avisitn AVISIT atptn stat; run;
proc transpose data=_cont out=_wide;
  by PARAM PARAMCD avisitn AVISIT atptn stat;
  id &TRTNVAR;                          /* one column per dose level         */
  var value;
run;

%tfltitle(num=14.4.1.2, type=Table,
   text=%str(Summary of Plasma Drug Concentrations by Study Day, Nominal Time and Dose Level),
   pop=Pharmacokinetic Concentration Population,
   foot=%str(CV% arithmetic; Geo CV% = 100*sqrt(exp(s^2_log)-1). Geometric statistics computed on concentrations > 0 (BLQ excluded). N = participants with a quantifiable sample at the nominal time per study day and dose level. Multiple ascending dose - Day 1 = first dose, Day N = last (steady-state) dosing day; times are relative to that day's dose within the dosing interval (0..tau).));
proc report data=_wide nowd split='|';
  columns PARAM PARAMCD avisitn AVISIT atptn stat ("Dose Level" /* dose cols + headers from &_bign */);
  define PARAM   / order 'Analyte (units)' width=22;
  define PARAMCD / order noprint;
  define avisitn / order noprint;
  define AVISIT  / order 'Study|Day' width=10;
  define atptn   / order 'Nominal|Time (h)' width=10;
  define stat    / display 'Statistic' width=14;
  break after AVISIT / skip;
run;
