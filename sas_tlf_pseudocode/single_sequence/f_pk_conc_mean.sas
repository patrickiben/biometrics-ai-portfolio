/******************************************************************************
* FIGURE    : f_pk_conc_mean  (Single-/fixed-sequence - e.g. DDI)
* TITLE     : Mean (+/- SD) Plasma Concentration-Time Profiles by Treatment
*             Period (Linear and Semi-Logarithmic)
* POPULATION: PK Concentration Population (PKFL='Y')
* INPUT     : ADPC (AVAL = concentration; ATPTN = nominal time)
* NOTE      : PSEUDOCODE. Single-/fixed-sequence -> ONE profile per dosing
*             PERIOD (Reference = victim alone; Test = victim+perpetrator),
*             grouped by APERIODC. Curves overlaid for a direct visual read of
*             the drug-interaction effect (Test vs Reference) within participants.
*             Two panels: LINEAR = arithmetic mean +/- SD; SEMI-LOG = GEOMETRIC
*             mean (no SD whiskers) per PK convention. ONE BLQ rule (BLQ
*             excluded) and the ANL01FL='Y' analysis-record flag in both panels.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=SINGLESEQ);     /* overlay variable = APERIODC (period)     */

data pc;
  set adam.adpc(where=(PKFL='Y' and ANL01FL='Y'));   /* same analysis flag as R */
  trt  = &TRTVAR;                                     /* treatment this period  */
  /* ONE BLQ rule: BLQ / non-positive concentrations excluded from the profile */
  if upcase(AVALC)='BLQ' or AVAL<=0 then delete;
  logaval = log(AVAL);                                /* for geometric mean      */
run;

/*--- linear panel: arithmetic mean +/- SD per period x nominal time -----*/
proc means data=pc nway noprint;
  class &BYPERIOD ATPTN PARAMCD; var AVAL;
  output out=_mn n=n mean=mean std=std median=med;
run;

/*--- semilog panel: geometric mean = exp(mean(log AVAL)) over AVAL>0 -----*/
proc means data=pc nway noprint;
  class &BYPERIOD ATPTN PARAMCD; var logaval;
  output out=_gm mean=meanlogv;
run;
data _gm; set _gm; geomean = exp(meanlogv); run;     /* geometric mean          */

data _mn;
  merge _mn(in=a) _gm(keep=&BYPERIOD ATPTN PARAMCD geomean);
  by &BYPERIOD ATPTN PARAMCD;
  lo = mean-std;  hi = mean+std;
  if lo<=0 then lo=.;                         /* log-axis safe lower whisker    */
run;
proc sort data=_mn; by PARAMCD APERIOD ATPTN; run;

%tfltitle(num=14.4.2.1, type=Figure,
   text=%str(Mean (+/- SD) Plasma Concentration-Time Profiles by Treatment Period (Linear)),
   pop=Pharmacokinetic Concentration Population,
   foot=%str(Single-/fixed-sequence: one profile per dosing period (Reference vs Test). Points = arithmetic mean; bars = +/- 1 SD. BLQ excluded. Nominal sampling times.));
/*--- panel 1: linear scale ----------------------------------------------*/
proc sgplot data=_mn;
  series  x=ATPTN y=mean / group=APERIODC markers
                           lineattrs=(thickness=2) markerattrs=(symbol=circlefilled);
  scatter x=ATPTN y=mean / group=APERIODC yerrorlower=lo yerrorupper=hi;
  xaxis label='Nominal Time (h)' values=(0 to 24 by 2);
  yaxis label='Mean Concentration (unit)' grid;
  keylegend / title='Treatment Period' position=bottom;
run;

%tfltitle(num=14.4.2.2, type=Figure,
   text=%str(Geometric Mean Plasma Concentration-Time Profiles by Treatment Period (Semi-Logarithmic)),
   pop=Pharmacokinetic Concentration Population,
   foot=%str(Single-/fixed-sequence: one profile per dosing period (Reference vs Test). Geometric mean on the semi-log panel (no SD whiskers). BLQ excluded. Nominal sampling times.));
/*--- panel 2: semi-log scale (log y) -- GEOMETRIC mean, no SD whiskers ---*/
proc sgplot data=_mn;
  series  x=ATPTN y=geomean / group=APERIODC markers
                              lineattrs=(thickness=2) markerattrs=(symbol=circlefilled);
  xaxis label='Nominal Time (h)' values=(0 to 24 by 2);
  yaxis type=log logbase=10 label='Geometric Mean Concentration (unit), log scale' grid;
  keylegend / title='Treatment Period' position=bottom;
run;
