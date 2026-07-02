/******************************************************************************
* FIGURE    : f_qtc_change  (Crossover - 2x2 or Williams)
* TITLE     : Mean (90% CI) Change from Baseline in QTcF by Timepoint
*             and Treatment
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADEG (PARAMCD='QTCF')
* NOTE      : PSEUDOCODE. Within-participant crossover -> one mean(90% CI) profile
*             per analysis treatment TRTA across nominal post-dose timepoints.
*             90% CI matches the QT/central-tendency convention. CHG = change
*             from within-period baseline. X = timepoint (ATPTN); series = TRTA.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=CROSSOVER);     /* TRTVAR=TRTA ; BYPERIOD=APERIOD APERIODC */

data eg;
  set adam.adeg(where=(SAFFL='Y' and ANL01FL='Y'
                       and PARAMCD='QTCF' and AVISITN>0));
run;

/*--- mean change + 90% CI by treatment x nominal timepoint --------------*
* Crossover: group = &TRTVAR (=TRTA), collapsed across sequence. The 90% CI *
* is the simple normal-approx CI (t-based); a model-based LSmean(CI) variant *
* would fit MIXED with treatment*timepoint and use LSMEANS / cl alpha=0.10. */
proc means data=eg nway noprint alpha=0.10;
  class &TRTVAR &TRTNVAR ATPTN ATPT;
  var CHG;
  output out=_m n=n mean=mean lclm=lo uclm=hi;   /* lclm/uclm = 90% CI at alpha=.10 */
run;
proc sort data=_m; by &TRTNVAR ATPTN; run;

%tfltitle(num=14.3.8.3, type=Figure,
   text=%str(Mean (90% CI) Change from Baseline in QTcF by Timepoint and Treatment),
   pop=Safety Population,
   foot=%str(Points = mean change from within-period baseline in QTcF (Fridericia); bars = 90% CI. One profile per analysis treatment (crossover). Reference lines at 0 and +10 msec (mean-effect threshold of clinical interest).));
proc sgplot data=_m;
  series  x=ATPTN y=mean / group=&TRTVAR markers
                           lineattrs=(thickness=2) markerattrs=(symbol=circlefilled);
  scatter x=ATPTN y=mean / group=&TRTVAR yerrorlower=lo yerrorupper=hi
                           markerattrs=(size=0);
  refline 0  / axis=y lineattrs=(pattern=shortdash);
  refline 10 / axis=y lineattrs=(pattern=dot) label='+10 ms';
  xaxis label='Nominal time post-dose (h)' valuesformat=best.;
  yaxis label='Mean change from baseline in QTcF (msec)';
  keylegend / title='Treatment' position=bottom;
run;
