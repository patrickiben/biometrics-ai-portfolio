/******************************************************************************
* FIGURE    : f_qtc_change  (Single Ascending Dose)
* TITLE     : Mean (+/-95% CI) Change from Baseline in QTcF by Dose and Timepoint
* POPULATION: Safety Population (SAFFL='Y'), on-treatment
* INPUT     : ADEG  (PARAMCD='QTCF'; CHG, ATPT/ATPTN nominal post-dose time)
* NOTE      : PSEUDOCODE. SAD: one series per dose level (TRT01A), mean change
*             from baseline in QTcF (Fridericia) vs nominal post-dose timepoint
*             (ATPTN). Descriptive mean dQTcF with 95% confidence-interval whiskers
*             by timepoint. Series ordered by ascending dose so a dose-related QTcF
*             trend is visually apparent. Horizontal reference lines at 0 and at the
*             ICH E14 thresholds of 30 ms and 60 ms. Descriptive only (no model
*             embedded); single dose per participant, across-cohort comparison is
*             descriptive.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=SAD);               /* -> TRTVAR=TRT01A, TRTNVAR=TRT01AN  */

/*--- on-treatment post-baseline QTcF change records ------------------------*/
data qtcf;
  set adam.adeg(where=(SAFFL='Y' and ANL01FL='Y' and ATPTN>0
                       and PARAMCD='QTCF'));
run;

/*--- mean + 95% CI of CHG per dose level x nominal post-dose timepoint -------
* &TRTNVAR carried so dose-cohort series sort in ascending dose order.        */
proc means data=qtcf nway noprint;
  class &TRTVAR &TRTNVAR ATPTN ATPT;
  var CHG;
  output out=_stat n=n mean=mean lclm=lo uclm=hi;   /* 95% CI of the mean    */
run;
proc sort data=_stat; by &TRTNVAR ATPTN; run;

%tfltitle(num=14.3.5.3, type=Figure,
   text=%str(Mean (+/-95% CI) Change from Baseline in QTcF by Dose and Timepoint),
   pop=Safety Population,
   foot=%str(QTcF = Fridericia-corrected QT (ADaM). Points = descriptive mean change from baseline (CHG); whiskers = 95% confidence interval. One series per dose level (ascending). Single dose per participant. Horizontal reference lines at 0 ms and at the ICH E14 thresholds of 30 ms and 60 ms. Descriptive only (no model embedded).));
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
