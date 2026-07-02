/******************************************************************************
* FIGURE    : f_pk_conc_mean  (SAD - Single Ascending Dose)
* TITLE     : Mean (+SD) Plasma Drug Concentration-Time Profiles by Dose Level
*             (Linear and Semi-Logarithmic)
* POPULATION: PK Concentration Population (PKFL='Y')
* INPUT     : ADPC (AVAL = concentration; ATPTN = nominal time)
* NOTE      : PSEUDOCODE. SAD: one curve per dose level (= TRT01A); ascending
*             cohorts overlaid to read the dose-related rise in exposure.
*             Mean +/- SD vs nominal time after the single dose; arithmetic
*             mean on the linear panel, geometric mean on the semilog panel
*             per convention. Two panels: linear (top) + semilog (bottom).
*             Single dose => one profile per participant (no accumulation).
*             BLQ excluded; analysis records = ANL01FL (same rule as R twin).
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=SAD);                       /* group = TRT01A (= dose)     */

/* one identical BLQ / analysis-population rule as the R twin: PK conc pop,
   ANL01FL='Y', BLQ excluded (AVAL>0 and AVALC ne 'BLQ').                       */
data pc;
  set adam.adpc(where=(PKFL='Y' and ANL01FL='Y'
                       and AVAL>0 and upcase(AVALC) ne 'BLQ'));
  atptn = ATPTN;                              /* nominal time after dose (h)  */
  logv = log(AVAL);                           /* log conc for geometric mean  */
run;

/*--- arithmetic mean/SD per dose x analyte x nominal time ----------------*/
proc means data=pc noprint;
  class &TRTVAR &TRTNVAR PARAMCD atptn;
  var AVAL;
  output out=_amean n=n mean=mean std=std;
run;

/*--- geometric mean per dose x analyte x nominal time (AVAL>0) ------------*/
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
   text=%str(Mean (+SD) Plasma Drug Concentration-Time Profiles by Dose Level),
   pop=Pharmacokinetic Concentration Population,
   foot=%str(Top: arithmetic mean +/- 1 SD, linear scale. Bottom: geometric mean (log scale), back-transformed from the mean of log(concentration) over concentrations > 0, semi-logarithmic scale. BLQ excluded; analysis records ANL01FL='Y'. One profile per ascending dose level. Nominal sampling times after the single dose.));

/*--- linear panel: arithmetic mean +/- SD --------------------------------*/
proc sgplot data=_plot noautolegend;
  series  x=atptn y=mean / group=&TRTVAR markers
                           lineattrs=(pattern=solid) name='lin';
  scatter x=atptn y=mean / group=&TRTVAR yerrorlower=lo yerrorupper=hi;
  xaxis label='Nominal Time After Dose (h)';
  yaxis label='Arithmetic Mean Concentration (+/- SD)' min=0;
  keylegend 'lin' / title='Dose Level' position=bottom;
run;

/*--- semilog panel: geometric mean ---------------------------------------*/
proc sgplot data=_plot(where=(geomean>0)) noautolegend;
  series x=atptn y=geomean / group=&TRTVAR markers
                             lineattrs=(pattern=solid) name='log';
  xaxis label='Nominal Time After Dose (h)';
  yaxis type=log logbase=10 label='Geometric Mean Concentration';
  keylegend 'log' / title='Dose Level' position=bottom;
run;
