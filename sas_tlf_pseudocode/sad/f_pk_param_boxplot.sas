/******************************************************************************
* FIGURE    : f_pk_param_boxplot  (SAD - Single Ascending Dose)
* TITLE     : Box Plots of Plasma PK Parameters by Dose Level
* POPULATION: PK Parameter Population (PKFL='Y')
* INPUT     : ADPP (PARAMCD = CMAX, AUCLST, AUCIFO, ...)
* NOTE      : PSEUDOCODE. SAD: x-axis = dose level (ordered by TRT01AN, ascending
*             cohorts); one box per dose, one panel per parameter. Box =
*             median/IQR, whiskers per Tukey, overlaid participant points.
*             Exposure parameters on a log axis to read the dose-related rise
*             descriptively (formal proportionality test in
*             t_dose_proportionality). Single dose => single-dose parameters.
*             Tmax handled as a separate median-based display when included.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=SAD);                       /* x-axis = TRT01A (= dose)    */

/*--- exposure parameters for boxplots (log axis) -------------------------*/
data pp;
  set adam.adpp(where=(PKFL='Y' and AVAL>0
                       and PARAMCD in ('CMAX','AUCLST','AUCIFO')));
  /* order dose levels by TRT01AN via a dose format on the class var         */
  trtord = &TRTNVAR;                          /* numeric dose order           */
run;

proc sort data=pp; by PARAM PARAMCD trtord &TRTVAR; run;

%tfltitle(num=14.4.2.3, type=Figure,
   text=%str(Box Plots of Plasma Pharmacokinetic Parameters by Dose Level),
   pop=Pharmacokinetic Parameter Population,
   foot=%str(Box = median and interquartile range; whiskers = Tukey; points = individual participants. Exposure parameters on log scale. Dose levels ordered ascending. Comparison is descriptive (parallel cohorts); formal dose-proportionality assessed by the power model.));

/*--- one panel per parameter; one box per dose level ---------------------*/
proc sgpanel data=pp noautolegend;
  panelby PARAM / columns=3 novarname uniscale=column;
  vbox AVAL / category=&TRTVAR group=&TRTVAR displaystats=(median q1 q3)
              boxwidth=0.5;
  scatter x=&TRTVAR y=AVAL / jitter markerattrs=(symbol=circlefilled size=4);
  colaxis label='Dose Level' fitpolicy=rotate;
  rowaxis type=log logbase=10 label='Parameter Value';
run;
