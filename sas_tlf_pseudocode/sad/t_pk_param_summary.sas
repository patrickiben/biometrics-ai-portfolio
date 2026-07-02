/******************************************************************************
* TABLE     : t_pk_param_summary  (SAD - Single Ascending Dose)
* TITLE     : Summary of Plasma PK Parameters by Dose Level
* POPULATION: PK Parameter Population (PKFL='Y' / APPARMFL)
* INPUT     : ADPP (PARAMCD = CMAX, TMAX, AUCLST, AUCIFO, T12, CL, VZ, LAMZ, ...)
* NOTE      : PSEUDOCODE. SAD: parallel cohorts, one (single) dose per participant;
*             column = TRT01A/TRT01AN (= dose level). Single dose => single-dose
*             NCA parameters only (no Rac / no steady state). Report arithmetic
*             n, Mean, SD, CV%, Geo Mean, Geo CV%, Median, Min, Max.
*             Tmax = Median (Min, Max) ONLY. Geometric stats undefined if
*             AVAL<=0 (exclude / footnote). Dose-normalized exposure trend is
*             assessed formally in t_dose_proportionality (power model).
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=SAD);                       /* column = TRT01A (= dose)    */

%bign(ds=adam.adsl, trtvar=&TRTVAR, trtn=&TRTNVAR, popfl=PKFL, out=_bign);

data pp;
  set adam.adpp(where=(PKFL='Y'));
  /* PARAMCD order/labels via format; flag Tmax for median-only handling    */
  tmaxfl = (PARAMCD='TMAX');
  if AVAL>0 then logv = log(AVAL);  /* log value for geometric stats        */
run;

/*--- arithmetic + geometric summary per dose level x parameter ----------*/
proc means data=pp(where=(tmaxfl=0)) noprint;
  class &TRTVAR &TRTNVAR PARAMCD PARAM;
  var AVAL;
  output out=_arith n=n mean=mean std=std min=min max=max cv=cv;
run;
/* geometric: run PROC MEANS on log(AVAL) (AVAL>0), back-transform:
   GeoMean=exp(mean_log); GeoCV%=100*sqrt(exp(var_log)-1)                   */
proc means data=pp(where=(tmaxfl=0 and AVAL>0)) noprint;
  class &TRTVAR &TRTNVAR PARAMCD; var logv;                /* log(AVAL)      */
  output out=_geo mean=gmean_log std=gsd_log;              /* on logVAL     */
run;

data _cont; merge _arith _geo; by &TRTVAR PARAMCD; length stat $14 value $30;
  /* round to ADaM decimal hints per parameter; build display strings:      */
  /* n / Mean / SD / CV% / Geo Mean / Geo CV% / Median / Min / Max          */
run;

/*--- Tmax: Median (Min, Max) only ---------------------------------------*/
proc means data=pp(where=(tmaxfl=1)) noprint;
  class &TRTVAR &TRTNVAR PARAMCD; var AVAL;
  output out=_tmax n=n median=med min=min max=max;
run;
data _tmaxd; set _tmax; length stat $14 value $30;
  stat='Median (Min, Max)';
  value=catx(' ', put(med,8.2), cats('(',put(min,8.2),', ',put(max,8.2),')'));
run;

/*--- stack params (rows) x dose level (cols) ----------------------------*/
data _all; set _cont _tmaxd; run;
proc transpose data=_all out=_wide; by PARAM PARAMCD stat; id &TRTNVAR; var value; run;

%tfltitle(num=14.4.1.1, type=Table, text=Summary of Plasma Pharmacokinetic Parameters by Dose Level,
          pop=Pharmacokinetic Parameter Population,
          foot=%str(Single-dose NCA parameters. CV% arithmetic; Geo CV% = 100*sqrt(exp(s^2_log)-1). Tmax: Median (Min, Max). N excludes BLQ-driven non-estimable parameters.));
proc report data=_wide nowd split='|';
  columns PARAM PARAMCD stat ("Dose Level" /* dose cols */);
  define PARAM  / order 'Parameter (units)' width=26;
  define PARAMCD/ order noprint;
  define stat   / display 'Statistic' width=16;
run;
