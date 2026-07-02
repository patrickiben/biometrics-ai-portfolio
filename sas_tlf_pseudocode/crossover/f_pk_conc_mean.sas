/******************************************************************************
* FIGURE    : f_pk_conc_mean  (Crossover - 2x2 or Williams)
* TITLE     : Mean (+/- SD) Plasma Concentration-Time Profiles by Treatment
*             (Linear and Semi-Logarithmic)
* POPULATION: PK Concentration Population (PKFL='Y')
* INPUT     : ADPC (AVAL = concentration; ATPTN = nominal time)
* NOTE      : PSEUDOCODE. Crossover -> ONE profile per treatment received
*             (TRTA = Test / Reference), pooled across period within treatment;
*             curves overlaid for direct within-study Test-vs-Reference visual
*             comparison. Two panels: LINEAR = arithmetic mean +/- SD;
*             SEMILOG = geometric mean (exp(mean(log AVAL)) over AVAL>0, no SD
*             whiskers) on the log10 axis, per PK convention.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=CROSSOVER);     /* group/overlay variable = TRTA           */

data pc;
  set adam.adpc(where=(PKFL='Y' and ATPTN ne .));  /* drop missing nominal time */
  trt  = &TRTVAR;                            /* treatment received this period */
  if upcase(AVALC)='BLQ' then AVAL=0;        /* BLQ -> 0 for mean profile      */
run;

/*--- LINEAR panel: arithmetic mean +/- SD per treatment x nominal time --*/
proc means data=pc nway noprint;
  class &TRTVAR &TRTNVAR ATPTN PARAMCD; var AVAL;
  output out=_mn n=n mean=mean std=std median=med;
run;
data _mn; set _mn;
  lo = mean-std;  hi = mean+std;
  if lo<=0 then lo=.;                         /* log-axis safe lower whisker    */
run;
proc sort data=_mn; by PARAMCD &TRTNVAR ATPTN; run;

/*--- SEMILOG panel: GEOMETRIC mean per treatment x nominal time ---------*
* Geometric mean = exp(mean(log AVAL)) over AVAL>0 only (BLQ-as-0 rows are  *
* excluded from the log panel, matching the R twin's >0 filter).           */
data _pclog; set pc;
  if AVAL>0 then logaval = log(AVAL);
run;
proc means data=_pclog nway noprint;
  class &TRTVAR &TRTNVAR ATPTN PARAMCD; var logaval;
  output out=_geo mean=meanlog_g;
run;
data _geo; set _geo;
  geomean = exp(meanlog_g);                   /* geometric mean for log scale   */
run;
proc sort data=_geo; by PARAMCD &TRTNVAR ATPTN; run;

%tfltitle(num=14.4.2.1, type=Figure,
   text=%str(Mean (+/- SD) Plasma Concentration-Time Profiles by Treatment (Linear)),
   pop=Pharmacokinetic Concentration Population,
   foot=%str(Within-participant crossover: one profile per treatment received (TRTA), pooled across period. Points = arithmetic mean; bars = +/- 1 SD. BLQ set to 0. Nominal sampling times.));
/*--- panel 1: linear scale ----------------------------------------------*/
proc sgplot data=_mn;
  series  x=ATPTN y=mean / group=&TRTVAR markers
                           lineattrs=(thickness=2) markerattrs=(symbol=circlefilled);
  scatter x=ATPTN y=mean / group=&TRTVAR yerrorlower=lo yerrorupper=hi;
  xaxis label='Nominal Time (h)' values=(0 to 24 by 2);
  yaxis label='Mean Concentration (unit)' grid;
  keylegend / title='Treatment' position=bottom;
run;

%tfltitle(num=14.4.2.2, type=Figure,
   text=%str(Geometric Mean Plasma Concentration-Time Profiles by Treatment (Semi-Logarithmic)),
   pop=Pharmacokinetic Concentration Population,
   foot=%str(Within-participant crossover: one profile per treatment received (TRTA), pooled across period. Geometric mean on the semi-log panel (concentrations > 0). Nominal sampling times.));
/*--- panel 2: semi-log scale (log y), geometric mean --------------------*/
proc sgplot data=_geo;
  series  x=ATPTN y=geomean / group=&TRTVAR markers
                              lineattrs=(thickness=2) markerattrs=(symbol=circlefilled);
  xaxis label='Nominal Time (h)' values=(0 to 24 by 2);
  yaxis type=log logbase=10 label='Geometric Mean Concentration (unit), log scale' grid;
  keylegend / title='Treatment' position=bottom;
run;
