/******************************************************************************
* FIGURE    : f_lab_lft_scatter  (MAD - Multiple Ascending Dose)
* TITLE     : Maximum Post-Baseline ALT vs Maximum Total Bilirubin
*             (multiples of ULN)
* POPULATION: Safety Population (SAFFL='Y'), on-treatment
* INPUT     : ADLB (PARAMCD in ALT, AST, BILI; ratio-to-ULN)
* NOTE      : PSEUDOCODE. Per-participant peak (max) ALT/ULN (x) vs Total
*             Bilirubin/ULN (y), both log scale, colored by DOSE LEVEL.
*             MAD: parallel cohorts, one (dose) treatment per participant ->
*             group/color = TRT01A (= dose level). Repeated dosing -> the peak
*             is the MAXIMUM over the ENTIRE multiple-dose period (all on-
*             treatment visits Day 1..Day N), so a cumulative liver signal that
*             builds with repeated dosing is captured. Reference lines at 3xULN
*             (ALT) and 2xULN (bilirubin) are the standard regulatory
*             thresholds. Neutral liver-safety scatter.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=MAD);          /* -> TRTVAR=TRT01A (= dose level)            */

/* ratio-to-ULN; prefer ADaM-provided R2ULN, else AVAL/A1HI */
data lb;
  set adam.adlb(where=(SAFFL='Y' and ONTRTFL='Y' and PARAMCD in ('ALT','AST','BILI')));
  xuln = coalesce(R2ULN, AVAL/A1HI);
run;

/* peak (max) per participant per analyte over the whole multiple-dose period */
proc means data=lb nway noprint;
  class USUBJID &TRTVAR PARAMCD; var xuln; output out=_peak max=peak;
run;
proc transpose data=_peak out=_e(drop=_name_) prefix=p_;
  by USUBJID &TRTVAR; id PARAMCD; var peak;          /* p_ALT p_AST p_BILI  */
run;
data _e; set _e;
  if p_ALT<=0 then p_ALT=0.01;  if p_BILI<=0 then p_BILI=0.01;  /* log-safe  */
  flag = (p_ALT>=3 and p_BILI>=2);     /* both elevated -> label participant id  */
run;

%tfltitle(num=14.3.4.5, type=Figure,
   text=%str(Maximum Post-Baseline ALT vs Maximum Total Bilirubin (multiples of ULN)),
   pop=Safety Population,
   foot=%str(Reference lines: ALT = 3xULN, Total Bilirubin = 2xULN. Both axes log scale. Each point = one participant's peak on-treatment value over the multiple-dose period, colored by dose level (MAD).));
proc sgplot data=_e noautolegend;
  refline 3 / axis=x lineattrs=(pattern=shortdash);
  refline 2 / axis=y lineattrs=(pattern=shortdash);
  scatter x=p_ALT y=p_BILI / group=&TRTVAR markerattrs=(symbol=circlefilled)
                             datalabel=ifc(flag,scan(USUBJID,-1,'-'),' ');
  xaxis type=log logbase=10 label='Peak ALT (xULN)'  min=0.1 max=100;
  yaxis type=log logbase=10 label='Peak Total Bilirubin (xULN)' min=0.1 max=20;
  keylegend / title='Dose Level' position=bottom;
run;
