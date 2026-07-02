/******************************************************************************
* FIGURE    : f_lab_lft_scatter  (Crossover - 2x2 or Williams)
* TITLE     : Maximum Post-Baseline ALT vs Maximum Total Bilirubin
*             (multiples of ULN)
* POPULATION: Safety Population (SAFFL='Y'), on-treatment
* INPUT     : ADLB (PARAMCD in ALT, AST, BILI; ratio-to-ULN R2ULN or AVAL/A1HI;
*             TRTA/TRTAN, APERIODC, TRTSEQP)
* NOTE      : PSEUDOCODE. Per-participant peak (max) ALT/ULN (x) vs Total
*             Bilirubin/ULN (y), both log scale. Within-participant crossover ->
*             the per-participant peak is taken WITHIN each analysis treatment TRTA
*             and colored by treatment (a participant can appear once per treatment
*             received). Reference lines at 3xULN (ALT) and 2xULN (bilirubin)
*             are the standard regulatory thresholds. Neutral liver-safety
*             scatter. APERIODC retained for an optional by-period panel.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=CROSSOVER);     /* TRTVAR=TRTA TRTNVAR=TRTAN BYPERIOD=APERIOD APERIODC SEQVAR=TRTSEQP */

/* ratio-to-ULN; prefer ADaM-provided R2ULN, else AVAL/A1HI */
data lb;
  set adam.adlb(where=(SAFFL='Y' and ONTRTFL='Y' and PARAMCD in ('ALT','AST','BILI')));
  xuln = coalesce(R2ULN, AVAL/A1HI);
  /* Treatment/period/sequence taken straight from ADaM - no re-derivation    */
run;

/*--- peak (max) per participant x treatment x analyte -----------------------*
* Crossover: CLASS carries &TRTVAR (=TRTA) so the peak is within-treatment.  *
* Add APERIODC to CLASS + a PANELBY for a by-period version of the figure.   */
proc means data=lb nway noprint;
  class USUBJID &TRTVAR &TRTNVAR PARAMCD; var xuln; output out=_peak max=peak;
run;
proc transpose data=_peak out=_e(drop=_name_) prefix=p_;
  by USUBJID &TRTVAR &TRTNVAR; id PARAMCD; var peak;   /* p_ALT p_AST p_BILI  */
run;
data _e; set _e;
  if p_ALT<=0 then p_ALT=0.01;  if p_BILI<=0 then p_BILI=0.01;  /* log-safe  */
  flag = (p_ALT>=3 and p_BILI>=2);     /* both elevated -> label participant id  */
run;

%tfltitle(num=14.3.4.4, type=Figure,
   text=%str(Maximum Post-Baseline ALT vs Maximum Total Bilirubin (multiples of ULN)),
   pop=Safety Population,
   foot=%str(Reference lines: ALT = 3xULN, Total Bilirubin = 2xULN. Both axes log scale. Each point = one participant's peak on-treatment value for a given treatment (crossover; a participant may appear once per treatment received).));
proc sgplot data=_e noautolegend;
  refline 3 / axis=x lineattrs=(pattern=shortdash);
  refline 2 / axis=y lineattrs=(pattern=shortdash);
  scatter x=p_ALT y=p_BILI / group=&TRTVAR markerattrs=(symbol=circlefilled)
                             datalabel=ifc(flag,scan(USUBJID,-1,'-'),' ');
  xaxis type=log logbase=10 label='Peak ALT (xULN)'  min=0.1 max=100;
  yaxis type=log logbase=10 label='Peak Total Bilirubin (xULN)' min=0.1 max=20;
  keylegend / title='Treatment' position=bottom;
run;
