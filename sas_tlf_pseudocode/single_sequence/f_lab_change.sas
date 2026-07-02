/******************************************************************************
* FIGURE    : f_lab_change  (Single-/Fixed-Sequence, e.g. DDI)
* TITLE     : Mean (+/- SE) Change from Baseline in Laboratory Parameter
*             Over Time by Period
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADLB (PARAM/PARAMCD, CHG, AVISIT/AVISITN, APERIOD/APERIODC)
* NOTE      : PSEUDOCODE. Mean change from baseline (CHG) with SD whiskers by
*             scheduled visit, one series per PERIOD. Single-/fixed-sequence
*             design: series = study period (Period 1 = reference, victim alone;
*             Period 2 = test, victim + perpetrator); CHG is relative to the
*             within-period baseline so the two series are directly comparable.
*             Descriptive only (within-participant change when perpetrator is added).
*             One figure per parameter (loop over PARAMCD).
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=SINGLESEQ);     /* TRTVAR=TRTA BYPERIOD=APERIOD APERIODC SEQVAR=(none) */

/* analysis records: Safety pop, post-baseline scheduled visits, non-missing change */
data lb;
  set adam.adlb(where=(SAFFL='Y' and ANL01FL='Y' and not missing(APERIOD)
                       and not missing(CHG) and AVISITN>0));
run;

/*--- mean +/- SE of change from baseline by visit x period x parameter -----*/
proc means data=lb nway noprint;
  class PARAMCD PARAM &BYPERIOD AVISITN AVISIT;
  var CHG;
  output out=_plot n=n mean=mean std=std stderr=se;   /* SE = std error of mean */
run;
data _plot; set _plot;
  hi = mean + se;  lo = mean - se;            /* SE whiskers (one dispersion stat) */
run;
proc sort data=_plot; by PARAMCD AVISITN APERIOD; run;

/*--- one figure per laboratory parameter ----------------------------------*/
%macro labfig(pcd=, plabel=, unit=);
  %tfltitle(num=14.3.4.4, type=Figure,
     text=%str(Mean (+/- SE) Change from Baseline in &plabel Over Time by Period),
     pop=Safety Population,
     foot=%str(Points = period mean change from within-period baseline; whiskers = +/- 1 SE. Series = study period: Period 1 (reference, victim alone) vs Period 2 (test, victim + perpetrator). Descriptive only. Post-baseline scheduled visits only.));
  proc sgplot data=_plot(where=(PARAMCD="&pcd"));
    refline 0 / axis=y lineattrs=(pattern=dot);
    series  x=AVISITN y=mean / group=APERIODC markers
                               markerattrs=(symbol=circlefilled);
    scatter x=AVISITN y=mean / group=APERIODC yerrorlower=lo yerrorupper=hi
                               markerattrs=(size=0);
    xaxis type=discrete label='Scheduled Visit'
          valueattrs=(size=7) fitpolicy=rotate;
    yaxis label="Change from Baseline (&unit)";
    keylegend / title='Study Period' position=bottom;
  run;
%mend labfig;

/* call once per parameter of interest (drive from a parameter metadata set) */
%labfig(pcd=ALT,  plabel=Alanine Aminotransferase, unit=U/L);
%labfig(pcd=AST,  plabel=Aspartate Aminotransferase, unit=U/L);
%labfig(pcd=CREAT,plabel=Creatinine, unit=umol/L);
%labfig(pcd=K,    plabel=Potassium, unit=mmol/L);
