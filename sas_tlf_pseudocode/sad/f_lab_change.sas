/******************************************************************************
* FIGURE    : f_lab_change  (Single Ascending Dose)
* TITLE     : Mean (+/- SE) Change from Baseline in Laboratory Parameter
*             Over Time by Dose Level
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADLB (PARAM/PARAMCD, CHG, AVISIT/AVISITN)
* NOTE      : PSEUDOCODE. Mean change from baseline (CHG) with SE whiskers by
*             scheduled visit, one series per dose level. One figure per
*             parameter (loop over PARAMCD). Dispersion = +/- 1 standard error
*             (identical to the R twin). SAD design: series = TRT01A
*             (ascending dose level), placebo pooled across cohorts;
*             single-dose follow-up over scheduled post-dose visits
*             (descriptive only, between-cohort).
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=SAD);               /* -> TRTVAR=TRT01A, TRTNVAR=TRT01AN  */

/* analysis records: Safety pop, post-baseline scheduled visits, non-missing chg */
data lb;
  set adam.adlb(where=(SAFFL='Y' and ANL01FL='Y'
                       and not missing(CHG) and AVISITN>0));
run;

/*--- mean +/- SE of change from baseline by visit x dose x parameter --------*/
proc means data=lb nway noprint;
  class PARAMCD PARAM &TRTVAR &TRTNVAR AVISITN AVISIT;
  var CHG;
  output out=_plot n=n mean=mean stderr=se;
run;
data _plot; set _plot;
  hi = mean + se;  lo = mean - se;            /* +/- 1 SE whiskers            */
run;
proc sort data=_plot; by PARAMCD AVISITN; run;

/*--- one figure per laboratory parameter ----------------------------------*/
%macro labfig(pcd=, plabel=, unit=);
  %tfltitle(num=14.3.4.4, type=Figure,
     text=%str(Mean (+/- SE) Change from Baseline in &plabel Over Time by Dose Level),
     pop=Safety Population,
     foot=%str(Points = dose-level mean change from baseline; whiskers = +/- 1 standard error. Series = ascending dose level (TRT01A); placebo pooled. Descriptive only; between-cohort comparison is not inferential. Single-dose study; post-baseline scheduled visits only.));
  proc sgplot data=_plot(where=(PARAMCD="&pcd"));
    refline 0 / axis=y lineattrs=(pattern=dot);
    series  x=AVISITN y=mean / group=&TRTVAR markers
                               markerattrs=(symbol=circlefilled);
    scatter x=AVISITN y=mean / group=&TRTVAR yerrorlower=lo yerrorupper=hi
                               markerattrs=(size=0);
    xaxis type=discrete label='Scheduled Visit'
          valueattrs=(size=7) fitpolicy=rotate;
    yaxis label="Change from Baseline (&unit)";
    keylegend / title='Dose Level' position=bottom;
  run;
%mend labfig;

/* call once per parameter of interest (drive from a parameter metadata set) */
%labfig(pcd=ALT,  plabel=Alanine Aminotransferase, unit=U/L);
%labfig(pcd=AST,  plabel=Aspartate Aminotransferase, unit=U/L);
%labfig(pcd=CREAT,plabel=Creatinine, unit=umol/L);
%labfig(pcd=K,    plabel=Potassium, unit=mmol/L);
