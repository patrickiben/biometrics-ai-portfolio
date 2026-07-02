/******************************************************************************
* FIGURE    : f_qtc_change  (Multiple Ascending Dose)
* TITLE     : Mean (+/-95% CI) Change from Baseline in QTcF by Timepoint
* POPULATION: Safety Population (SAFFL='Y'), on-treatment
* INPUT     : ADEG  (PARAMCD='QTCF'; CHG, ATPT/ATPTN)
* NOTE      : PSEUDOCODE. MAD design: one series per dose level (TRT01A;
*             placebo pooled in ADaM), DESCRIPTIVE mean change from baseline in
*             QTcF (Fridericia) vs NOMINAL POST-DOSE TIMEPOINT (ATPTN) across
*             the multiple-dose period, error bars = +/-95% CI. Horizontal
*             reference lines at the ICH E14 thresholds of 30 ms and 60 ms
*             (plus a 0 line). No model is fitted in this figure; it is purely
*             descriptive. One treatment per participant => between-dose
*             comparison is descriptive.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=MAD);               /* -> TRTVAR=TRT01A, TRTNVAR=TRT01AN */

/*--- on-treatment post-baseline QTcF change records over the MAD period -----*/
data qtcf;
  set adam.adeg(where=(SAFFL='Y' and ANL01FL='Y' and ATPTN>0
                       and PARAMCD='QTCF'));
run;

/*--- DESCRIPTIVE mean + 95% CI of CHG per dose level x nominal timepoint ----*/
proc means data=qtcf nway noprint;
  class &TRTVAR ATPTN ATPT;
  var CHG;
  output out=_stat n=n mean=mean lclm=lo uclm=hi;   /* 95% CI of the mean    */
run;

%tfltitle(num=14.3.6.3, type=Figure,
   text=%str(Mean (+/-95% CI) Change from Baseline in QTcF by Timepoint),
   pop=Safety Population,
   foot=%str(QTcF = Fridericia-corrected QT (ADaM). Points = descriptive mean change from baseline (CHG); whiskers = 95%% CI of the mean. One series per dose level (placebo pooled). X-axis = nominal post-dose timepoints (ATPTN) across the multiple-dose period (MAD). Horizontal reference lines at 0, 30 and 60 ms (ICH E14 thresholds). No model is fitted; the figure is descriptive.));
proc sgplot data=_stat;
  refline 0  / lineattrs=(pattern=solid);
  refline 30 / lineattrs=(pattern=shortdash) label='30 ms';
  refline 60 / lineattrs=(pattern=shortdash) label='60 ms';
  series  x=ATPTN y=mean / group=&TRTVAR markers
                           markerattrs=(symbol=circlefilled);
  scatter x=ATPTN y=mean / group=&TRTVAR yerrorlower=lo yerrorupper=hi
                           markerattrs=(size=0);
  xaxis label='Nominal Post-dose Timepoint'
        /* ATPTN tick values mapped to ATPT text via format */;
  yaxis label='Mean Change from Baseline in QTcF (ms, +/-95% CI)';
  keylegend / title='Dose Level' position=bottom;
run;
