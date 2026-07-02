/******************************************************************************
* FIGURE    : f_pk_param_boxplot  (Parallel-group / per-dose)
* TITLE     : Box Plots of Plasma PK Parameters by Treatment
* POPULATION: PK Parameter Population (PKFL='Y')
* INPUT     : ADPP (PARAMCD = CMAX, AUCLST, AUCIFO, ...)
* NOTE      : PSEUDOCODE. Parallel-group: x-axis = treatment (= dose level,
*             ordered by TRT01AN); one box per dose, one panel per parameter.
*             Box = median/IQR, whiskers per Tukey, overlaid participant points.
*             Exposure parameters on a log axis to read dose-related trend
*             descriptively. No within-participant comparison. Tmax handled as a
*             separate median-based display when included.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=PARALLEL);                 /* x-axis = TRT01A (= dose)    */

/*--- exposure parameters for boxplots (log axis) -------------------------*/
data pp;
  set adam.adpp(where=(PKFL='Y' and AVAL>0
                       and PARAMCD in ('CMAX','AUCLST','AUCIFO')));
  /* order treatments/doses by TRT01AN via a dose format on the class var    */
  trtord = &TRTNVAR;                          /* numeric dose order           */
run;

proc sort data=pp; by PARAM PARAMCD trtord &TRTVAR; run;

%tfltitle(num=14.4.2.3, type=Figure,
   text=%str(Box Plots of Plasma Pharmacokinetic Parameters by Treatment),
   pop=Pharmacokinetic Parameter Population,
   foot=%str(Box = median and interquartile range; whiskers = Tukey; points = individual participants. Exposure parameters on log scale. Treatments ordered by dose level. Comparison is descriptive (parallel groups).));

/*--- one panel per parameter; one box per treatment (dose) ---------------*/
proc sgpanel data=pp noautolegend;
  panelby PARAM / columns=3 novarname uniscale=column;
  vbox AVAL / category=&TRTVAR group=&TRTVAR displaystats=(median q1 q3)
              boxwidth=0.5;
  scatter x=&TRTVAR y=AVAL / jitter markerattrs=(symbol=circlefilled size=4);
  colaxis label='Treatment (Dose)' fitpolicy=rotate;
  rowaxis type=log logbase=10 label='Parameter Value';
run;
