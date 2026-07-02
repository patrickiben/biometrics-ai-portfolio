/******************************************************************************
* FIGURE    : f_pd_change  (Single-/Fixed-Sequence, e.g. DDI)
* TITLE     : Mean (+/- SE) Change from Baseline in Pharmacodynamic Biomarker
*             over Time by Period
* POPULATION: PD / Pharmacodynamic Analysis Population (PDFL='Y')
* INPUT     : ADPD (PARAMCD = target PD biomarker; CHG, ATPTN nominal timepoint;
*             APERIOD/APERIODC, TRTA/TRTAN from ADaM)
* NOTE      : PSEUDOCODE. Single-/fixed-sequence (no randomized sequence): ONE
*             mean(SE) profile per fixed PERIOD (each participant contributes once
*             per period in the fixed order). CHG = change from within-period
*             baseline (ADPD CHG). Curves overlaid for a direct within-study
*             test-period-vs-reference-period visual comparison (Period 1 =
*             reference; subsequent period(s) = test).
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=SINGLESEQ);     /* group/overlay variable = APERIODC (period) */

%let PDPARM = INHIB;     /* target PD biomarker PARAMCD (same as R twin)      */

data pd;
  set adam.adpd(where=(PDFL='Y' and PARAMCD="&PDPARM" and ATPTN>0
                       and not missing(CHG)));
  /* nominal post-baseline timepoints (ATPTN); ADPD-provided CHG (vs within-
     period BASE); period straight from ADaM                                 */
run;

/*--- mean change + SE per PERIOD x nominal timepoint --------------------*
* Single-sequence: group = APERIODC (fixed period). x-axis = ATPTN (nominal     *
* timepoint), matching the R twin. Each participant contributes once per period.*/
proc means data=pd nway noprint;
  class &BYPERIOD ATPTN ATPT;
  var CHG;
  output out=_m n=n mean=mean std=std stderr=se lclm=lcl uclm=ucl;
run;
proc sort data=_m; by APERIOD ATPTN; run;

%tfltitle(num=14.4.6.2, type=Figure,
   text=%str(Mean (+/- SE) Change from Baseline in Pharmacodynamic Biomarker over Time by Period),
   pop=Pharmacodynamic Analysis Population,
   foot=%str(Points = arithmetic mean change from within-period baseline; whiskers = +/- 1 SE. One profile per fixed period (single-/fixed-sequence; Period 1 = reference, subsequent period(s) = test). Each participant contributes once per period.));
proc sgplot data=_m;
  refline 0 / axis=y lineattrs=(pattern=dot);
  series x=ATPTN y=mean / group=APERIODC markers
                          markerattrs=(symbol=circlefilled)
                          lineattrs=(thickness=2);
  scatter x=ATPTN y=mean / group=APERIODC yerrorlower=eval(mean-se)
                           yerrorupper=eval(mean+se) errorbarattrs=(thickness=1);
  xaxis label='Nominal time post-dose (h)' type=linear;
  yaxis label='Mean Change from Baseline (units)';
  keylegend / title='Period' position=bottom;
run;
