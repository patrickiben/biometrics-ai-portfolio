/******************************************************************************
* FIGURE    : f_pk_conc_individual  (SAD - Single Ascending Dose)
* TITLE     : Individual Plasma Drug Concentration-Time Profiles by Dose Level
*             (Semi-Logarithmic)
* POPULATION: PK Concentration Population (PKFL='Y')
* INPUT     : ADPC (AVAL = concentration; NRRELTM/ATPTN = relative time)
* NOTE      : PSEUDOCODE. SAD: one panel per dose level (= TRT01A); within a
*             panel one spaghetti line per participant. Actual relative time after
*             the single dose on x; concentration on a semi-log y. Single dose
*             => one profile per participant (no within-participant overlay, no
*             accumulation). BLQ (AVAL<=0) excluded from the log axis.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=SAD);                       /* panel = TRT01A (= dose)     */

data pc;
  set adam.adpc(where=(PKFL='Y' and AVAL>0));
  length subjid $20;
  subjid = scan(USUBJID,-1,'-');             /* short id for line labels     */
  atime  = NRRELTM;                          /* actual relative time (h)     */
  conc   = AVAL;                             /* concentration                */
run;

proc sort data=pc; by &TRTNVAR &TRTVAR USUBJID atime; run;

%tfltitle(num=14.4.2.2, type=Figure,
   text=%str(Individual Plasma Drug Concentration-Time Profiles by Dose Level),
   pop=Pharmacokinetic Concentration Population,
   foot=%str(One line per participant; one panel per ascending dose level. Semi-logarithmic scale; BLQ values excluded. Actual sampling times relative to the single dose.));

/*--- one semilog panel per dose level; spaghetti by participant --------------*/
proc sgpanel data=pc noautolegend;
  panelby &TRTVAR / columns=2 novarname;     /* facet by dose level          */
  series x=atime y=conc / group=USUBJID lineattrs=(pattern=solid)
                          markers markerattrs=(size=4);
  colaxis label='Actual Time After Dose (h)';
  rowaxis type=log logbase=10 label='Concentration';
run;
