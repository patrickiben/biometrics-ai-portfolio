/******************************************************************************
* FIGURE    : f_vitals_change  (Single-/Fixed-Sequence, e.g. DDI)
* TITLE     : Mean (SE) Change from Baseline in Vital Signs by Visit
*             and Treatment Period
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADVS (PARAMCD in SYSBP, DIABP, PULSE)
* NOTE      : PSEUDOCODE. Single-/fixed-sequence design (fixed treatment order;
*             NO randomized sequence) -> one mean(SE) profile per treatment
*             PERIOD (APERIODC); each participant appears once per period received.
*             CHG = change from within-period baseline (ADVS CHG). Panel per
*             parameter; X = visit, series = treatment period.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=SINGLESEQ);     /* TRTVAR=TRTA ; BYPERIOD=APERIOD APERIODC ; no SEQVAR */

data vs;
  set adam.advs(where=(SAFFL='Y' and ANL01FL='Y' and AVISITN>0
                       and PARAMCD in ('SYSBP','DIABP','PULSE','TEMP','RESP')));
run;

/*--- mean (SE) of CHG by period x visit x parameter ---------------------*
* Single-seq: group/series = the treatment PERIOD (APERIODC). No sequence; the *
* fixed order makes period the natural comparison axis (e.g. victim alone vs   *
* victim + perpetrator).                                                       */
proc means data=vs nway noprint;
  class PARAMCD APERIOD APERIODC AVISITN AVISIT;
  var CHG;
  output out=_m n=n mean=mean stderr=se;
run;
data _m; set _m;
  lo = mean - se;  hi = mean + se;     /* error-bar bounds */
run;
proc sort data=_m; by PARAMCD APERIOD AVISITN; run;

%tfltitle(num=14.3.7.2, type=Figure,
   text=%str(Mean (SE) Change from Baseline in Vital Signs by Visit and Treatment Period),
   pop=Safety Population,
   foot=%str(Points = mean change from within-period baseline; bars = +/- 1 SE. One profile per treatment period (single-/fixed-sequence; each participant contributes once per period). Reference line at 0.));

/* one panel per parameter, treatment period as the overlaid series */
proc sgpanel data=_m;
  panelby PARAMCD / columns=1 novarname uniscale=column;
  series  x=AVISITN y=mean / group=APERIODC markers
                             lineattrs=(thickness=2) markerattrs=(symbol=circlefilled);
  scatter x=AVISITN y=mean / group=APERIODC yerrorlower=lo yerrorupper=hi
                             markerattrs=(size=0);
  refline 0 / lineattrs=(pattern=shortdash);
  rowaxis label='Mean change from baseline';
  colaxis label='Visit' integer;
  keylegend / title='Treatment Period' position=bottom;
run;
