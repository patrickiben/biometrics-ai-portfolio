/******************************************************************************
* FIGURE    : f_pk_param_boxplot  (Crossover - 2x2 or Williams)
* TITLE     : Box Plots of Key PK Parameters by Treatment
* POPULATION: PK Parameter Population (PKFL='Y')
* INPUT     : ADPP (PARAMCD = CMAX, AUCLST, AUCIFO)
* NOTE      : PSEUDOCODE. Crossover within-participant design -> box plots grouped
*             by treatment received (TRTA = Test / Reference), one panel per
*             parameter. Exposure parameters (Cmax/AUC) typically log-skewed ->
*             log y-axis. Optional spaghetti overlay connects each participant's
*             Test and Reference points (within-participant pairing, the crossover
*             signature). Tmax, if shown, stays on a linear axis.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=CROSSOVER);     /* group/category variable = TRTA           */

data pp;
  set adam.adpp(where=(PKFL='Y' and PARAMCD in ('CMAX','AUCLST','AUCIFO')));
  length subjid $20;
  subjid = scan(USUBJID,-1,'-');
  trt    = &TRTVAR;                          /* treatment received this period  */
  ylog   = ifn(AVAL>0, AVAL, .);             /* log-axis safe                   */
run;
proc sort data=pp; by PARAMCD subjid trt; run;

%tfltitle(num=14.4.4.2, type=Figure,
   text=%str(Box Plots of Key Pharmacokinetic Parameters by Treatment),
   pop=Pharmacokinetic Parameter Population,
   foot=%str(One panel per parameter; boxes grouped by treatment received (TRTA). Box = median/IQR, whiskers = 1.5*IQR, diamond = mean, points = participants. Within-participant Test/Reference points connected per participant. Log y-axis for exposure parameters.));
/*--- one panel per parameter; box by treatment; within-participant overlay --*/
proc sgpanel data=pp;
  panelby PARAMCD / columns=3 novarname uniscale=column;
  vbox ylog / category=&TRTVAR group=&TRTVAR meanattrs=(symbol=diamondfilled)
              boxwidth=0.5;
  series x=&TRTVAR y=ylog / group=subjid lineattrs=(thickness=0.5 pattern=dot)
              nomissinggroup;               /* spaghetti: pair each participant    */
  rowaxis type=log logbase=10 label='Parameter value (unit), log scale' grid;
  colaxis label='Treatment';
  keylegend / title='Treatment';
run;
