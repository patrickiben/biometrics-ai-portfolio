/******************************************************************************
* FIGURE    : f_pk_conc_individual  (Parallel-group / per-dose)
* TITLE     : Individual Plasma Drug Concentration-Time Profiles by Treatment
*             (Semi-Logarithmic)
* POPULATION: PK Concentration Population (PKFL='Y')
* INPUT     : ADPC (AVAL = concentration; NRRELTM/ATPTN = relative time)
* NOTE      : PSEUDOCODE. Parallel-group: one panel per treatment (= dose
*             level); within a panel one spaghetti line per participant. Actual
*             relative time on x; concentration on a semi-log y. No within-
*             participant crossover overlay -- participants belong to a single
*             treatment. BLQ (AVAL<=0) excluded from the log axis.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=PARALLEL);                 /* panel = TRT01A (= dose)     */

data pc;
  set adam.adpc(where=(PKFL='Y' and AVAL>0));
  length subjid $20;
  subjid = scan(USUBJID,-1,'-');             /* short id for line labels     */
  atime  = NRRELTM;                          /* actual relative time (h)     */
  conc   = AVAL;                             /* concentration                */
run;

proc sort data=pc; by &TRTNVAR &TRTVAR USUBJID atime; run;

%tfltitle(num=14.4.2.2, type=Figure,
   text=%str(Individual Plasma Drug Concentration-Time Profiles by Treatment),
   pop=Pharmacokinetic Concentration Population,
   foot=%str(One line per participant; one panel per treatment (dose level). Semi-logarithmic scale; BLQ values excluded. Actual sampling times relative to dose.));

/*--- one semilog panel per treatment (dose); spaghetti by participant --------*/
proc sgpanel data=pc noautolegend;
  panelby &TRTVAR / columns=2 novarname;     /* facet by treatment/dose      */
  series x=atime y=conc / group=USUBJID lineattrs=(pattern=solid)
                          markers markerattrs=(size=4);
  colaxis label='Actual Time (h)';
  rowaxis type=log logbase=10 label='Concentration';
run;
