/******************************************************************************
* FIGURE    : f_pk_param_boxplot  (Single-/fixed-sequence - e.g. DDI)
* TITLE     : Box Plots of Key PK Parameters by Treatment Period
* POPULATION: PK Parameter Population (PKFL='Y')
* INPUT     : ADPP (PARAMCD = CMAX, AUCLST, AUCIFO)
* NOTE      : PSEUDOCODE. Single-/fixed-sequence design -> box plots grouped by
*             dosing PERIOD (Reference = victim alone; Test = victim+
*             perpetrator), one panel per parameter. Exposure parameters
*             (Cmax/AUC) typically log-skewed -> log y-axis. Spaghetti overlay
*             connects each participant's Reference and Test points (within-participant
*             pairing, the signature of the fixed-sequence DDI design). Tmax, if
*             shown, stays on a linear axis.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=SINGLESEQ);     /* category/group variable = APERIODC        */

data pp;
  set adam.adpp(where=(PKFL='Y' and PARAMCD in ('CMAX','AUCLST','AUCIFO')));
  length subjid $20;
  subjid = scan(USUBJID,-1,'-');
  trt    = &TRTVAR;                          /* treatment given this period    */
  ylog   = ifn(AVAL>0, AVAL, .);             /* log-axis safe                   */
run;
proc sort data=pp; by PARAMCD subjid APERIOD; run;

%tfltitle(num=14.4.4.2, type=Figure,
   text=%str(Box Plots of Key Pharmacokinetic Parameters by Treatment Period),
   pop=Pharmacokinetic Parameter Population,
   foot=%str(One panel per parameter; boxes grouped by dosing period (Reference vs Test). Box = median/IQR, whiskers = 1.5*IQR, diamond = mean, points = participants. Within-participant Reference/Test points connected per participant. Log y-axis for exposure parameters.));
/*--- one panel per parameter; box by period; within-participant overlay -----*/
proc sgpanel data=pp;
  panelby PARAMCD / columns=3 novarname uniscale=column;
  vbox ylog / category=APERIODC group=APERIODC meanattrs=(symbol=diamondfilled)
              boxwidth=0.5;
  series x=APERIODC y=ylog / group=subjid lineattrs=(thickness=0.5 pattern=dot)
              nomissinggroup;               /* spaghetti: pair each participant    */
  rowaxis type=log logbase=10 label='Parameter value (unit), log scale' grid;
  colaxis label='Treatment Period';
  keylegend / title='Treatment Period';
run;
