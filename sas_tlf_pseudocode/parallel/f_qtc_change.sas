/******************************************************************************
* FIGURE    : f_qtc_change  (Parallel-group)
* TITLE     : Mean (+/-SE) Change from Baseline in QTcF by Visit
* POPULATION: Safety Population (SAFFL='Y'), on-treatment
* INPUT     : ADEG  (PARAMCD='QTCF'; CHG, AVISIT/AVISITN)
* NOTE      : PSEUDOCODE. Parallel-group: one series per treatment arm
*             (TRT01A), mean change from baseline in QTcF (Fridericia) vs
*             scheduled visit, error bars = +/-1 SE. Reference line at +10 ms
*             is the regulatory threshold of clinical interest. Between-group
*             comparison is descriptive (one treatment per participant).
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=PARALLEL);          /* -> TRTVAR=TRT01A, TRTNVAR=TRT01AN */

/*--- on-treatment post-baseline QTcF change records ------------------------*/
data qtcf;
  set adam.adeg(where=(SAFFL='Y' and ANL01FL='Y' and AVISITN>0
                       and PARAMCD='QTCF'));
run;

/*--- mean + SE of CHG per treatment arm x visit ----------------------------*/
proc means data=qtcf nway noprint;
  class &TRTVAR AVISITN AVISIT;
  var CHG;
  output out=_stat n=n mean=mean stderr=se;
run;
data _stat; set _stat;
  lo = mean - se;  hi = mean + se;          /* +/-1 SE error-bar limits      */
run;

%tfltitle(num=14.3.5.3, type=Figure,
   text=%str(Mean (+/-SE) Change from Baseline in QTcF by Visit),
   pop=Safety Population,
   foot=%str(QTcF = Fridericia-corrected QT (ADaM). Points = mean change from baseline (CHG); whiskers = +/-1 standard error. One series per treatment arm (parallel-group). Reference lines at 0 and +10 ms.));
proc sgplot data=_stat;
  refline 0  / lineattrs=(pattern=solid);
  refline 10 / lineattrs=(pattern=shortdash) label='+10 ms';
  series  x=AVISITN y=mean / group=&TRTVAR markers
                             markerattrs=(symbol=circlefilled);
  scatter x=AVISITN y=mean / group=&TRTVAR yerrorlower=lo yerrorupper=hi
                             markerattrs=(size=0);
  xaxis label='Scheduled Visit'
        /* AVISITN tick values mapped to AVISIT text via format */;
  yaxis label='Mean Change from Baseline in QTcF (ms, +/-SE)';
  keylegend / title='Treatment Arm' position=bottom;
run;
