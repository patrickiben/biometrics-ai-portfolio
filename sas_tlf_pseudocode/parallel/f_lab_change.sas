/******************************************************************************
* FIGURE    : f_lab_change  (Parallel-group)
* TITLE     : Mean (+/- SD) Change from Baseline in Laboratory Parameter
*             Over Time by Treatment
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADLB (PARAM/PARAMCD, CHG, AVISIT/AVISITN)
* NOTE      : PSEUDOCODE. Mean change from baseline (CHG) with SD whiskers by
*             scheduled visit, one series per treatment arm. One figure per
*             parameter (loop over PARAMCD). Parallel design: series = TRT01A
*             (between-group comparison; descriptive only).
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=PARALLEL);          /* -> TRTVAR=TRT01A, TRTNVAR=TRT01AN  */

/* analysis records: Safety pop, scheduled visits, non-missing change         */
data lb;
  set adam.adlb(where=(SAFFL='Y' and ANL01FL='Y'
                       and not missing(CHG) and not missing(AVISITN)));
run;

/*--- mean +/- SD of change from baseline by visit x treatment x parameter --*/
proc means data=lb nway noprint;
  class PARAMCD PARAM &TRTVAR &TRTNVAR AVISITN AVISIT;
  var CHG;
  output out=_plot n=n mean=mean std=std;
run;
data _plot; set _plot;
  hi = mean + std;  lo = mean - std;          /* SD whiskers                  */
run;
proc sort data=_plot; by PARAMCD AVISITN; run;

/*--- one figure per laboratory parameter ----------------------------------*/
%macro labfig(pcd=, plabel=, unit=);
  %tfltitle(num=14.3.4.4, type=Figure,
     text=%str(Mean (+/- SD) Change from Baseline in &plabel Over Time by Treatment),
     pop=Safety Population,
     foot=%str(Points = arm mean change from baseline; whiskers = +/- 1 SD. Descriptive only; between-group comparison is not inferential. Scheduled visits only.));
  proc sgplot data=_plot(where=(PARAMCD="&pcd"));
    refline 0 / axis=y lineattrs=(pattern=dot);
    series  x=AVISITN y=mean / group=&TRTVAR markers
                               markerattrs=(symbol=circlefilled);
    scatter x=AVISITN y=mean / group=&TRTVAR yerrorlower=lo yerrorupper=hi
                               markerattrs=(size=0);
    xaxis type=discrete label='Scheduled Visit'
          valueattrs=(size=7) fitpolicy=rotate;
    yaxis label="Change from Baseline (&unit)";
    keylegend / title='Treatment' position=bottom;
  run;
%mend labfig;

/* call once per parameter of interest (drive from a parameter metadata set) */
%labfig(pcd=ALT,  plabel=Alanine Aminotransferase, unit=U/L);
%labfig(pcd=AST,  plabel=Aspartate Aminotransferase, unit=U/L);
%labfig(pcd=CREAT,plabel=Creatinine, unit=umol/L);
%labfig(pcd=K,    plabel=Potassium, unit=mmol/L);
