/******************************************************************************
* TABLE     : t_pk_conc_summary  (Parallel-group / per-dose)
* TITLE     : Summary of Plasma Drug Concentrations by Nominal Time and
*             Treatment
* POPULATION: PK Concentration Population (PKFL='Y')
* INPUT     : ADPC (AVAL = concentration; ATPTN/NRRELTM = nominal time;
*             PARAM/PARAMCD = analyte; ABLFL/AVISIT = scheduled sampling)
* NOTE      : PSEUDOCODE. Parallel-group: one treatment per participant, column =
*             TRT01A/TRT01AN (= dose level). Rows = nominal sampling time;
*             columns = treatment (dose). Report arithmetic n, Mean, SD, CV%,
*             Geo Mean, Geo CV%, Median, Min, Max per time x treatment.
*             BLQ handled per analysis convention (0 pre-first-dose, treated as
*             missing/half-LLOQ thereafter); geometric stats require AVAL>0.
*             No within-participant comparison; descriptive by treatment only.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=PARALLEL);                 /* column = TRT01A (= dose)    */

%bign(ds=adam.adsl, trtvar=&TRTVAR, trtn=&TRTNVAR, popfl=PKFL, out=_bign);

/*--- pull scheduled (nominal-time) concentration records -----------------*/
data pc;
  set adam.adpc(where=(PKFL='Y'));
  /* nominal time for the row structure (ADaM-provided, no re-derivation)    */
  atptn = ATPTN;                  /* nominal time point (numeric, hr)        */
  /* BLQ handling per SAP: AVAL already imputed in ADPC; flag for n counts   */
  blqfl = (ABLFL='Y');            /* below-LLOQ analysis flag                */
  if AVAL>0 then logv = log(AVAL);  /* log conc for geometric stats          */
run;

/*--- arithmetic summary per treatment x analyte x nominal time -----------*/
proc means data=pc noprint;
  class &TRTVAR &TRTNVAR PARAMCD PARAM atptn;
  var AVAL;
  output out=_arith n=n mean=mean std=std min=min max=max median=med cv=cv;
run;

/*--- geometric summary on log scale (AVAL>0 only); back-transform ---------
   GeoMean = exp(mean_log); Geo CV% = 100*sqrt(exp(var_log)-1)              */
proc means data=pc(where=(AVAL>0)) noprint;
  class &TRTVAR &TRTNVAR PARAMCD atptn; var logv;          /* log(AVAL)      */
  output out=_geo mean=gmean_log std=gsd_log;              /* on logVAL     */
run;

/*--- build display strings, round to ADaM/assay decimal hints ------------*/
data _cont;
  merge _arith _geo;
  by &TRTVAR PARAMCD atptn;
  length stat $14 value $30;
  /* geomean = exp(gmean_log);  geocv = 100*sqrt(exp(gsd_log**2)-1)         */
  /* emit one row per statistic: n / Mean / SD / CV% / Geo Mean /           */
  /*   Geo CV% / Median / Min / Max  (loop or array, formatted per analyte) */
run;

/*--- stack times (rows) x treatment/dose (cols) --------------------------*/
proc sort data=_cont; by PARAM PARAMCD atptn stat; run;
proc transpose data=_cont out=_wide;
  by PARAM PARAMCD atptn stat;
  id &TRTNVAR;                          /* one column per dose level         */
  var value;
run;

%tfltitle(num=14.4.1.2, type=Table,
   text=%str(Summary of Plasma Drug Concentrations by Nominal Time and Treatment),
   pop=Pharmacokinetic Concentration Population,
   foot=%str(CV% arithmetic; Geo CV% = 100*sqrt(exp(s^2_log)-1). Geometric statistics computed on concentrations > 0 (BLQ excluded). N = participants with a quantifiable sample at the time point per treatment.));
proc report data=_wide nowd split='|';
  columns PARAM PARAMCD atptn stat ("Treatment (Dose)" /* dose cols + headers from &_bign */);
  define PARAM  / order 'Analyte (units)' width=22;
  define PARAMCD/ order noprint;
  define atptn  / order 'Nominal|Time (h)' width=10;
  define stat   / display 'Statistic' width=14;
run;
