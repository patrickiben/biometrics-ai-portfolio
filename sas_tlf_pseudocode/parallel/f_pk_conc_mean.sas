/******************************************************************************
* FIGURE    : f_pk_conc_mean  (Parallel-group / per-dose)
* TITLE     : Mean (+SD) Plasma Drug Concentration-Time Profiles by Treatment
*             (Linear and Semi-Logarithmic)
* POPULATION: PK Concentration Population (PKFL='Y')
* INPUT     : ADPC (AVAL = concentration; ATPTN = nominal time)
* NOTE      : PSEUDOCODE. Parallel-group: one curve per treatment (= dose
*             level), grouped by TRT01A. Mean +/- SD vs nominal time; arithmetic
*             mean on linear panel, geometric mean on semilog panel per
*             convention. Two panels: linear (top) + semilog (bottom).
*             BLQ excluded from geometric mean; descriptive by treatment only.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=PARALLEL);                 /* group = TRT01A (= dose)     */

data pc;
  set adam.adpc(where=(PKFL='Y'));
  atptn = ATPTN;                              /* nominal relative time (h)    */
  if AVAL>0 then logv = log(AVAL);            /* log conc for geometric mean  */
run;

/*--- arithmetic mean/SD per treatment x analyte x nominal time -----------*/
proc means data=pc noprint;
  class &TRTVAR &TRTNVAR PARAMCD atptn;
  var AVAL;
  output out=_amean n=n mean=mean std=std;
run;

/*--- geometric mean per treatment x analyte x nominal time (AVAL>0) -------*/
proc means data=pc(where=(AVAL>0)) noprint;
  class &TRTVAR &TRTNVAR PARAMCD atptn; var logv;     /* log(AVAL)           */
  output out=_gmean mean=gmean_log;                   /* mean on log scale   */
run;

data _plot;
  merge _amean _gmean;
  by &TRTVAR PARAMCD atptn;
  where n>0;
  geomean = exp(gmean_log);                  /* back-transformed geo mean    */
  lo = mean - std;  hi = mean + std;         /* SD whiskers (linear panel)   */
  if lo<0 then lo=0;
run;

%tfltitle(num=14.4.2.1, type=Figure,
   text=%str(Mean (+SD) Plasma Drug Concentration-Time Profiles by Treatment),
   pop=Pharmacokinetic Concentration Population,
   foot=%str(Top: arithmetic mean +/- SD, linear scale. Bottom: geometric mean, semi-logarithmic scale (concentrations > 0). Grouped by treatment (dose level). Nominal sampling times.));

/*--- linear panel: arithmetic mean +/- SD --------------------------------*/
proc sgplot data=_plot noautolegend;
  series  x=atptn y=mean / group=&TRTVAR markers
                           lineattrs=(pattern=solid) name='lin';
  scatter x=atptn y=mean / group=&TRTVAR yerrorlower=lo yerrorupper=hi;
  xaxis label='Nominal Time (h)';
  yaxis label='Arithmetic Mean Concentration (+/- SD)' min=0;
  keylegend 'lin' / title='Treatment (Dose)' position=bottom;
run;

/*--- semilog panel: geometric mean ---------------------------------------*/
proc sgplot data=_plot(where=(geomean>0)) noautolegend;
  series x=atptn y=geomean / group=&TRTVAR markers
                             lineattrs=(pattern=solid) name='log';
  xaxis label='Nominal Time (h)';
  yaxis type=log logbase=10 label='Geometric Mean Concentration';
  keylegend 'log' / title='Treatment (Dose)' position=bottom;
run;
