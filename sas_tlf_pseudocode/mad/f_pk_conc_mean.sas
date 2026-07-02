/******************************************************************************
* FIGURE    : f_pk_conc_mean  (MAD - Multiple Ascending Dose)
* TITLE     : Mean (+SD) Plasma Drug Concentration-Time Profiles by Dose Level
*             and Study Day (Linear and Semi-Logarithmic)
* POPULATION: PK Concentration Population (PKFL='Y')
* INPUT     : ADPC (AVAL = concentration; ATPTN = nominal time within interval;
*             AVISIT/AVISITN = study day)
* NOTE      : PSEUDOCODE. MAD: one curve per dose level (= TRT01A) within each
*             study-day panel; the figure contrasts the Day-1 (first-dose) profile
*             with the Day-N (steady-state) profile so the accumulation /
*             steady-state attainment is visible. Mean +/- SD vs nominal time
*             within the dosing interval; arithmetic mean on the linear panel,
*             geometric mean on the semilog panel per convention. Panels: study
*             day (Day 1 vs Day N) crossed with linear/semilog scale; ascending
*             dose cohorts overlaid within each panel. BLQ excluded from the
*             geometric mean; descriptive by dose and day only.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=MAD);                       /* group = TRT01A (= dose)     */

/* Single BLQ rule (state in footnote): drop AVAL<=0 and AVALC='BLQ' from the
   profile; same analysis-population flag (ANL01FL) applied as in the R twin.   */
data pc;
  set adam.adpc(where=(PKFL='Y' and ANL01FL='Y'
                       and not (AVAL<=0 or upcase(AVALC)='BLQ')));
  atptn   = ATPTN;                            /* nominal time within interval */
  avisitn = AVISITN;                          /* study day (1 ... N)          */
  if AVAL>0 then logv = log(AVAL);            /* log conc for geometric mean  */
run;

/*--- arithmetic mean/SD per dose x analyte x study-day x nominal time -----*/
proc means data=pc noprint;
  class &TRTVAR &TRTNVAR PARAMCD avisitn AVISIT atptn;
  var AVAL;
  output out=_amean n=n mean=mean std=std;
run;

/*--- geometric mean per dose x analyte x study-day x nominal time (AVAL>0) -*/
proc means data=pc(where=(AVAL>0)) noprint;
  class &TRTVAR &TRTNVAR PARAMCD avisitn atptn; var logv; /* log(AVAL)        */
  output out=_gmean mean=gmean_log;                   /* mean on log scale   */
run;

data _plot;
  merge _amean _gmean;
  by &TRTVAR PARAMCD avisitn atptn;
  where n>0;
  geomean = exp(gmean_log);                  /* back-transformed geo mean    */
  lo = mean - std;  hi = mean + std;         /* SD whiskers (linear panel)   */
  if lo<0 then lo=0;
run;

%tfltitle(num=14.4.2.1, type=Figure,
   text=%str(Mean (+SD) Plasma Drug Concentration-Time Profiles by Dose Level and Study Day),
   pop=Pharmacokinetic Concentration Population,
   foot=%str(Left/top: arithmetic mean +/- SD, linear scale. Right/bottom: geometric mean on the semi-log panel (concentrations > 0), no SD whiskers. BLQ (AVAL<=0 or AVALC='BLQ') excluded from the profile. One profile per ascending dose level; panels contrast Day 1 (first dose) with Day N (steady state). Nominal sampling times within the dosing interval.));

/*--- linear panel by study day: arithmetic mean +/- SD -------------------*/
proc sgpanel data=_plot noautolegend;
  panelby AVISIT / columns=2 novarname uniscale=row;   /* Day 1 vs Day N      */
  series  x=atptn y=mean / group=&TRTVAR markers
                           lineattrs=(pattern=solid) name='lin';
  scatter x=atptn y=mean / group=&TRTVAR yerrorlower=lo yerrorupper=hi;
  colaxis label='Nominal Time Within Dosing Interval (h)';
  rowaxis label='Arithmetic Mean Concentration (+/- SD)' min=0;
  keylegend 'lin' / title='Dose Level' position=bottom;
run;

/*--- semilog panel by study day: geometric mean --------------------------*/
proc sgpanel data=_plot(where=(geomean>0)) noautolegend;
  panelby AVISIT / columns=2 novarname uniscale=row;   /* Day 1 vs Day N      */
  series x=atptn y=geomean / group=&TRTVAR markers
                             lineattrs=(pattern=solid) name='log';
  colaxis label='Nominal Time Within Dosing Interval (h)';
  rowaxis type=log logbase=10 label='Geometric Mean Concentration';
  keylegend 'log' / title='Dose Level' position=bottom;
run;
