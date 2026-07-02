/******************************************************************************
* FIGURE    : f_vitals_change  (Multiple Ascending Dose)
* TITLE     : Mean (+/-SE) Change from Baseline in Vital Signs by Study Day
* POPULATION: Safety Population (SAFFL='Y'), on-treatment
* INPUT     : ADVS  (PARAMCD: SYSBP, DIABP, PULSE; CHG, AVISIT/AVISITN, ADY)
* NOTE      : PSEUDOCODE. MAD design: one series per dose level (TRT01A;
*             placebo pooled in ADaM), mean change from baseline (CHG) vs
*             STUDY DAY across the multiple-dose period, error bars = +/-1 SE.
*             Panel per vital parameter. With repeated dosing the x-axis spans
*             Day 1 -> last dosing day so any cumulative day-to-day drift in
*             vitals across the dosing period is visible. One treatment per
*             participant => comparison across dose levels is descriptive.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=MAD);               /* -> TRTVAR=TRT01A, TRTNVAR=TRT01AN */

/*--- on-treatment post-baseline change records across the MAD period --------
* Pre-dose (trough) record per study day is the primary steady-state row.     */
data advs;
  set adam.advs(where=(SAFFL='Y' and ANL01FL='Y' and AVISITN>0
                       and PARAMCD in ('SYSBP','DIABP','PULSE','TEMP','RESP')));
run;

/*--- mean + SE of CHG per dose level x study day x parameter ----------------*/
proc means data=advs nway noprint;
  class &TRTVAR PARAMCD AVISITN AVISIT;
  var CHG;
  output out=_stat n=n mean=mean stderr=se;
run;
data _stat; set _stat;
  lo = mean - se;  hi = mean + se;          /* +/-1 SE error-bar limits      */
run;

%tfltitle(num=14.3.7.2, type=Figure,
   text=%str(Mean (+/-SE) Change from Baseline in Vital Signs by Study Day),
   pop=Safety Population,
   foot=%str(Points = mean change from baseline (ADaM CHG); whiskers = +/-1 standard error. One series per dose level (placebo pooled). X-axis spans study days across the multiple-dose period (MAD). Reference line at zero = no change.));
proc sgpanel data=_stat;
  panelby PARAMCD / columns=1 novarname;
  refline 0 / lineattrs=(pattern=shortdash);
  series  x=AVISITN y=mean  / group=&TRTVAR markers
                              markerattrs=(symbol=circlefilled);
  scatter x=AVISITN y=mean  / group=&TRTVAR yerrorlower=lo yerrorupper=hi
                              markerattrs=(size=0);
  colaxis label='Study Day (multiple-dose period)' valueattrs=(size=7)
          /* AVISITN tick values mapped to AVISIT text via format */;
  rowaxis label='Mean Change from Baseline (+/-SE)';
  keylegend / title='Dose Level' position=bottom;
run;
