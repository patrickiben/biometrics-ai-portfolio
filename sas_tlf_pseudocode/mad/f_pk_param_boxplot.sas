/******************************************************************************
* FIGURE    : f_pk_param_boxplot  (MAD - Multiple Ascending Dose)
* TITLE     : Box Plots of Plasma PK Parameters by Dose Level and Study Day
* POPULATION: PK Parameter Population (PKFL='Y')
* INPUT     : ADPP (PARAMCD = CMAX AUCLST (Day 1) ; CMAXSS AUCTAU (Day N) ;
*             AVISIT/AVISITN = study day)
* NOTE      : PSEUDOCODE. MAD: x-axis = dose level (= TRT01A, ordered by TRT01AN);
*             one box per dose, panels = exposure parameter crossed with study day
*             (Day 1 single-dose Cmax/AUClast vs Day N steady-state Cmax,ss/AUCtau)
*             so the dose-related rise AND the day-1-to-steady-state rise are read
*             from one figure. Box = median/IQR, whiskers per Tukey, overlaid
*             participant points. Exposure parameters on a log axis. No within-participant
*             comparison (parallel cohorts). Tmax handled as a separate
*             median-based display when included.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=MAD);                       /* x-axis = TRT01A (= dose)    */

/*--- exposure parameters for boxplots (log axis) -------------------------*/
data pp;
  set adam.adpp(where=(PKFL='Y' and AVAL>0
                       and PARAMCD in ('CMAX','AUCLST','CMAXSS','AUCTAU')));
  /* order treatments/doses by TRT01AN via a dose format on the class var    */
  trtord = &TRTNVAR;                          /* numeric dose order           */
run;

proc sort data=pp; by PARAM PARAMCD AVISITN AVISIT trtord &TRTVAR; run;

%tfltitle(num=14.4.2.3, type=Figure,
   text=%str(Box Plots of Plasma Pharmacokinetic Parameters by Dose Level and Study Day),
   pop=Pharmacokinetic Parameter Population,
   foot=%str(Box = median and interquartile range; whiskers = Tukey; points = individual participants. Exposure parameters on log scale. Treatments ordered by dose level. Panels contrast Day 1 (single dose) with Day N (steady state). Comparison is descriptive (parallel cohorts).));

/*--- panels = parameter x study day; one box per dose level --------------*/
proc sgpanel data=pp noautolegend;
  panelby PARAM AVISIT / layout=lattice novarname uniscale=column;
  vbox AVAL / category=&TRTVAR group=&TRTVAR displaystats=(median q1 q3)
              boxwidth=0.5;
  scatter x=&TRTVAR y=AVAL / jitter markerattrs=(symbol=circlefilled size=4);
  colaxis label='Dose Level' fitpolicy=rotate;
  rowaxis type=log logbase=10 label='Parameter Value';
run;
