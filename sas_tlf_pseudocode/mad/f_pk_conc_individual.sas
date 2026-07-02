/******************************************************************************
* FIGURE    : f_pk_conc_individual  (MAD - Multiple Ascending Dose)
* TITLE     : Individual Plasma Drug Concentration-Time Profiles by Dose Level
*             and Study Day (Semi-Logarithmic)
* POPULATION: PK Concentration Population (PKFL='Y')
* INPUT     : ADPC (AVAL = concentration; NRRELTM/ATPTN = relative time;
*             AVISIT/AVISITN = study day)
* NOTE      : PSEUDOCODE. MAD: one panel per dose level (= TRT01A) crossed with
*             study day (Day 1 first dose vs Day N steady state); within a panel
*             one spaghetti line per participant. Actual relative time within the
*             dosing interval on x; concentration on a semi-log y. Showing Day 1
*             and Day N side by side exposes between-participant variability and the
*             individual rise in trough/exposure on repeated dosing. BLQ
*             (AVAL<=0) excluded from the log axis.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=MAD);                       /* panel = TRT01A (= dose)     */

data pc;
  set adam.adpc(where=(PKFL='Y' and AVAL>0));
  length subjid $20;
  subjid = scan(USUBJID,-1,'-');             /* short id for line labels     */
  atime  = NRRELTM;                          /* actual time within interval  */
  conc   = AVAL;                             /* concentration                */
run;

proc sort data=pc; by &TRTNVAR &TRTVAR AVISITN AVISIT USUBJID atime; run;

%tfltitle(num=14.4.2.2, type=Figure,
   text=%str(Individual Plasma Drug Concentration-Time Profiles by Dose Level and Study Day),
   pop=Pharmacokinetic Concentration Population,
   foot=%str(One line per participant; panels = dose level by study day (Day 1 = first dose, Day N = steady state). Semi-logarithmic scale; BLQ values excluded. Actual sampling times relative to that day's dose within the interval.));

/*--- panel grid: dose level (rows) x study day (cols); spaghetti by subj --*/
proc sgpanel data=pc noautolegend;
  panelby &TRTVAR AVISIT / layout=lattice novarname;   /* dose x Day 1/Day N  */
  series x=atime y=conc / group=USUBJID lineattrs=(pattern=solid)
                          markers markerattrs=(size=4);
  colaxis label='Actual Time Within Dosing Interval (h)';
  rowaxis type=log logbase=10 label='Concentration';
run;
