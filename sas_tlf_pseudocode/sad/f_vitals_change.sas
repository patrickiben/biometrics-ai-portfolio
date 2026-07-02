/******************************************************************************
* FIGURE    : f_vitals_change  (Single Ascending Dose)
* TITLE     : Mean (+/-SE) Change from Baseline in Vital Signs by Dose and Visit
* POPULATION: Safety Population (SAFFL='Y'), on-treatment
* INPUT     : ADVS  (PARAMCD: SYSBP, DIABP, PULSE; CHG, AVISIT/AVISITN)
* NOTE      : PSEUDOCODE. SAD: one series per dose level (TRT01A), mean change
*             from baseline (CHG) vs scheduled visit, error bars = +/-1 SE.
*             Panel per vital parameter. Series ordered by ascending dose so a
*             dose-related trend in vital-sign change is visually apparent.
*             Single dose per participant; comparison across cohorts is descriptive.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=SAD);               /* -> TRTVAR=TRT01A, TRTNVAR=TRT01AN  */

/*--- on-treatment post-baseline change records -----------------------------*/
data advs;
  set adam.advs(where=(SAFFL='Y' and ANL01FL='Y' and AVISITN>0
                       and PARAMCD in ('SYSBP','DIABP','PULSE')));
run;

/*--- mean + SE of CHG per dose level x visit x parameter -------------------
* &TRTNVAR carried so dose-cohort series sort in ascending dose order.        */
proc means data=advs nway noprint;
  class &TRTVAR &TRTNVAR PARAMCD AVISITN AVISIT;
  var CHG;
  output out=_stat n=n mean=mean stderr=se;
run;
data _stat; set _stat;
  lo = mean - se;  hi = mean + se;          /* +/-1 SE error-bar limits      */
run;
proc sort data=_stat; by PARAMCD &TRTNVAR AVISITN; run;

%tfltitle(num=14.3.7.2, type=Figure,
   text=%str(Mean (+/-SE) Change from Baseline in Vital Signs by Dose and Visit),
   pop=Safety Population,
   foot=%str(Points = mean change from baseline (ADaM CHG); whiskers = +/-1 standard error. One series per dose level (ascending). Single dose per participant. Reference line at zero = no change.));
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
  keylegend / title='Dose Level' position=bottom;
run;
