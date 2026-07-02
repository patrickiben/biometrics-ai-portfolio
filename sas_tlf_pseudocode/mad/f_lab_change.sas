/******************************************************************************
* FIGURE    : f_lab_change  (MAD - Multiple Ascending Dose)
* TITLE     : Mean (SE) Change from Baseline in Laboratory Values by Visit
*             and Dose Level
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADLB (PARAM/PARAMCD, CHG, AVISIT/AVISITN, TRT01A/TRT01AN)
* NOTE      : PSEUDOCODE. MAD: parallel cohorts, one (dose) treatment per
*             participant -> one mean(SE) profile per dose level (TRT01A). CHG =
*             change from the Day 1 pre-first-dose baseline. Repeated dosing ->
*             X = visit spans the multiple-dose schedule (Day 1, Day 7, Day 14
*             ...), so the profiles reveal any DOSE- and TIME-dependent
*             (cumulative) trend across the dosing period. One panel per
*             laboratory parameter; X = visit, series = dose level.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=MAD);          /* -> TRTVAR=TRT01A (= dose level)            */

data lb;
  set adam.adlb(where=(SAFFL='Y' and ANL01FL='Y' and AVISITN>0
                       and PARAMCD in ('ALT','AST','BILI','CREAT','ALP','GGT')));
  /* CHG, treatment (= dose level) all from ADaM - no re-derivation            */
run;

/*--- mean (SE) of CHG by dose level x visit x parameter -----------------*
* MAD: group = &TRTVAR (=TRT01A = dose level). Visit axis spans the repeated-  *
* dosing schedule so each dose cohort's trajectory is visible over time.       */
proc means data=lb nway noprint;
  class PARAMCD PARAM &TRTVAR &TRTNVAR AVISITN AVISIT;
  var CHG;
  output out=_m n=n mean=mean stderr=se;
run;
data _m; set _m;
  lo = mean - se;  hi = mean + se;     /* error-bar bounds */
run;
proc sort data=_m; by PARAMCD &TRTNVAR AVISITN; run;

%tfltitle(num=14.3.4.4, type=Figure,
   text=%str(Mean (SE) Change from Baseline in Laboratory Values by Visit and Dose Level),
   pop=Safety Population,
   foot=%str(Points = mean change from the Day 1 pre-dose baseline; bars = +/- 1 SE. One profile per dose-level cohort (MAD; one dose per participant). Visits span the multiple-dose period. SI units.));

/* one panel per parameter, dose level as the overlaid series */
proc sgpanel data=_m;
  panelby PARAM / columns=2 novarname uniscale=column;
  series  x=AVISITN y=mean / group=&TRTVAR markers
                             lineattrs=(thickness=2) markerattrs=(symbol=circlefilled);
  scatter x=AVISITN y=mean / group=&TRTVAR yerrorlower=lo yerrorupper=hi
                             markerattrs=(size=0);
  refline 0 / lineattrs=(pattern=shortdash);
  rowaxis label='Mean change from baseline';
  colaxis label='Visit' integer;
  keylegend / title='Dose Level' position=bottom;
run;
