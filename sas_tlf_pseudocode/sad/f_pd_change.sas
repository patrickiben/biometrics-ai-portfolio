/******************************************************************************
* FIGURE    : f_pd_change  (SAD - Single Ascending Dose)
* TITLE     : Mean (+/- SE) Change from Baseline in Pharmacodynamic Biomarker
*             over Time by Dose Level
* POPULATION: PD / Pharmacodynamic Analysis Population (PDFL='Y')
* INPUT     : ADPD (PARAMCD = target PD biomarker; CHG, AVISITN/ATPTN)
* NOTE      : PSEUDOCODE. SAD: one curve per ascending dose level (= TRT01A,
*             placebo pooled); group variable = TRT01A/TRT01AN. Single dose =>
*             one dosing event, no accumulation; nominal time is relative to
*             the single administered dose. Mean change from baseline with SE
*             error bars across nominal time, overlaid to read the dose-related
*             PD response. Descriptive across-dose comparison (no within-participant
*             contrast).
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=SAD);                       /* group = TRT01A (= dose)      */

%let PDPARM = PDMARK1;   /* target PD biomarker PARAMCD (one figure = one)   */

data pd;
  set adam.adpd(where=(PDFL='Y' and PARAMCD="&PDPARM" and AVISITN>0
                       and not missing(CHG)));
  reltm = coalesce(ATPTN, AVISITN);           /* nominal time after dose (h)  */
  /* ADPD-provided CHG (vs BASE); nominal post-dose timepoints from ADaM     */
run;

/*--- mean + SD of change per dose x time --------------------------------*/
proc means data=pd nway noprint;
  class &TRTVAR &TRTNVAR reltm;
  var CHG;
  output out=_m mean=mean std=std;
run;

/*--- distinct-PARTICIPANT n per dose x time (SE denominator = participants) ---*/
proc sql;
  create table _np as
    select &TRTVAR, &TRTNVAR, reltm, count(distinct USUBJID) as n
    from pd group by &TRTVAR, &TRTNVAR, reltm;
quit;

/*--- SE on the participant-level n (matches the R twin) -----------------*/
data _m;
  merge _m(drop=_type_ _freq_) _np;
  by &TRTVAR &TRTNVAR reltm;
  if n>0 then se = std / sqrt(n);             /* SE = SD / sqrt(participants) */
run;

%tfltitle(num=14.4.6.2, type=Figure,
   text=%str(Mean (+/- SE) Change from Baseline in Pharmacodynamic Biomarker over Time by Dose Level),
   pop=Pharmacodynamic Analysis Population,
   foot=%str(Points = arithmetic mean change from baseline by dose level at each nominal time after the single dose; whiskers = +/- 1 SE (SE = SD / sqrt of distinct participants at the timepoint). SAD: one curve per ascending dose (placebo pooled); across-dose comparison is descriptive.));
proc sgplot data=_m;
  refline 0 / axis=y lineattrs=(pattern=dot);
  series x=reltm y=mean / group=&TRTVAR markers
                          markerattrs=(symbol=circlefilled)
                          lineattrs=(thickness=2);
  scatter x=reltm y=mean / group=&TRTVAR yerrorlower=eval(mean-se)
                           yerrorupper=eval(mean+se) errorbarattrs=(thickness=1);
  xaxis label='Nominal Time After Dose (h)' type=linear;
  yaxis label='Mean Change from Baseline (units)';
  keylegend / title='Dose Level' position=bottom;
run;
