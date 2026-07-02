/******************************************************************************
* FIGURE    : f_qtc_change  (Single-/Fixed-Sequence, e.g. DDI)
* TITLE     : Mean (90% CI) Change from Baseline in QTcF by Timepoint
*             and Treatment Period
* POPULATION: Safety Population (SAFFL='Y'), post-baseline
* INPUT     : ADEG (PARAMCD='QTCF'; CHG from period baseline)
* NOTE      : PSEUDOCODE. DESCRIPTIVE figure (no inferential model embedded).
*             Single-/fixed-sequence design (fixed treatment order; NO randomized
*             sequence) -> one mean(90% CI) profile per treatment PERIOD (APERIODC)
*             across nominal post-dose timepoints. 90% CI matches the QT/central-
*             tendency convention. CHG = change from within-period baseline.
*             X = timepoint (ATPTN); series = period. Horizontal reference lines
*             at 0, 30, and 60 msec (ICH E14 central-tendency thresholds).
*             A by-period contrast (e.g. victim+perpetrator vs victim alone) is
*             the natural read for a DDI QT assessment.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=SINGLESEQ);     /* TRTVAR=TRTA ; BYPERIOD=APERIOD APERIODC ; no SEQVAR */

data eg;
  set adam.adeg(where=(SAFFL='Y' and ANL01FL='Y'
                       and PARAMCD='QTCF' and AVISITN>0
                       and not missing(CHG)));
run;

/*--- mean change + 90% CI by PERIOD x nominal timepoint -----------------*
* Single-seq: group/series = treatment PERIOD (APERIODC); no sequence. The 90% *
* CI is the simple normal-approx (t-based) CI. A model-based LSmean(CI) variant *
* would fit MIXED with period*timepoint (random participant) and LSMEANS / cl       *
* alpha=0.10 -> consistent with the by-period PK comparison in t_be_anova.sas.  */
proc means data=eg nway noprint alpha=0.10;
  class APERIOD APERIODC ATPTN ATPT;
  var CHG;
  output out=_m n=n mean=mean lclm=lo uclm=hi;   /* lclm/uclm = 90% CI at alpha=.10 */
run;
proc sort data=_m; by APERIOD ATPTN; run;

%tfltitle(num=14.3.8.3, type=Figure,
   text=%str(Mean (90% CI) Change from Baseline in QTcF by Timepoint and Treatment Period),
   pop=Safety Population,
   foot=%str(Points = mean change from within-period baseline in QTcF (Fridericia); bars = 90% CI. One profile per treatment period (single-/fixed-sequence). Horizontal reference lines at 0, 30, and 60 msec (ICH E14 central-tendency thresholds). Descriptive.));
proc sgplot data=_m;
  series  x=ATPTN y=mean / group=APERIODC markers
                           lineattrs=(thickness=2) markerattrs=(symbol=circlefilled);
  scatter x=ATPTN y=mean / group=APERIODC yerrorlower=lo yerrorupper=hi
                           markerattrs=(size=0);
  refline 0  / axis=y lineattrs=(pattern=shortdash);
  refline 30 / axis=y lineattrs=(pattern=dot);          /* ICH E14 threshold */
  refline 60 / axis=y lineattrs=(pattern=dot);          /* ICH E14 threshold */
  xaxis label='Nominal time post-dose (h)' valuesformat=best.;
  yaxis label='Mean change from baseline in QTcF (msec)';
  keylegend / title='Treatment Period' position=bottom;
run;
