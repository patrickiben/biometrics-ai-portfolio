/******************************************************************************
* FIGURE    : f_vitals_change  (Parallel-group)
* TITLE     : Mean (+/-SE) Change from Baseline in Vital Signs by Visit
* POPULATION: Safety Population (SAFFL='Y'), on-treatment
* INPUT     : ADVS  (PARAMCD: SYSBP, DIABP, PULSE; CHG, AVISIT/AVISITN)
* NOTE      : PSEUDOCODE. Parallel-group: one series per treatment arm
*             (TRT01A), mean change from baseline (CHG) vs scheduled visit,
*             error bars = +/-1 SE. Panel per vital parameter. Comparison
*             across arms is descriptive (between-group, not within-participant).
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=PARALLEL);          /* -> TRTVAR=TRT01A, TRTNVAR=TRT01AN */

/*--- on-treatment post-baseline change records -----------------------------*/
data advs;
  set adam.advs(where=(SAFFL='Y' and ANL01FL='Y' and AVISITN>0
                       and PARAMCD in ('SYSBP','DIABP','PULSE','TEMP','RESP')));
run;

/*--- mean + SE of CHG per treatment arm x visit x parameter ----------------*/
proc means data=advs nway noprint;
  class &TRTVAR PARAMCD AVISITN AVISIT;
  var CHG;
  output out=_stat n=n mean=mean stderr=se;
run;
data _stat; set _stat;
  lo = mean - se;  hi = mean + se;          /* +/-1 SE error-bar limits      */
run;

%tfltitle(num=14.3.7.2, type=Figure,
   text=%str(Mean (+/-SE) Change from Baseline in Vital Signs by Visit),
   pop=Safety Population,
   foot=%str(Points = mean change from baseline (ADaM CHG); whiskers = +/-1 standard error. One series per treatment arm (parallel-group). Reference line at zero = no change.));
proc sgpanel data=_stat;
  panelby PARAMCD / columns=1 novarname;
  refline 0 / lineattrs=(pattern=shortdash);
  series  x=AVISITN y=mean  / group=&TRTVAR markers
                              markerattrs=(symbol=circlefilled);
  scatter x=AVISITN y=mean  / group=&TRTVAR yerrorlower=lo yerrorupper=hi
                              markerattrs=(size=0);
  colaxis label='Scheduled Visit' valueattrs=(size=7)
          /* values mapped to AVISIT text via discretized AVISITN format */;
  rowaxis label='Mean Change from Baseline (+/-SE)';
  keylegend / title='Treatment Arm' position=bottom;
run;
