/******************************************************************************
* FIGURE    : f_pd_change  (MAD - Multiple Ascending Dose)
* TITLE     : Mean (+/- SE) Change from Baseline in Pharmacodynamic Biomarker
*             over the Repeated-Dosing Period by Dose Level
* POPULATION: PD / Pharmacodynamic Analysis Population (PDFL='Y')
* INPUT     : ADPD (PARAMCD = target PD biomarker; CHG, AVISITN study day,
*             ATPTN time post-dose)
* NOTE      : PSEUDOCODE. MAD: one line per dose level (= TRT01A); column/group
*             variable = TRT01A/TRT01AN (placebo pooled). Repeated dosing => the
*             x-axis spans the multi-day treatment period (continuous study-day
*             time, ADY/AVISITN), so the onset and the MAINTAINED PD effect at
*             STEADY STATE are visible across ascending doses. Mean change from
*             baseline with SE error bars. Descriptive across-dose comparison
*             (no within-participant contrast).
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=MAD);                       /* group = TRT01A (= dose)      */

%let PDPARM = PDMARK1;   /* target PD biomarker PARAMCD (one figure = one)     */

data pd;
  set adam.adpd(where=(PDFL='Y' and PARAMCD="&PDPARM" and AVISITN>0
                       and not missing(CHG)));
  /* MAD time grid = continuous study-day time over the repeated-dosing period;
     prefer ADaM ADY (study day), fall back to AVISITN. ADPD-provided CHG.     */
  reltm = coalesce(ADY, AVISITN);              /* study-day time axis          */
run;

/*--- mean change + SE per dose level x study-day time --------------------*/
proc means data=pd nway noprint;
  class &TRTVAR &TRTNVAR reltm;
  var CHG;
  output out=_m n=n mean=mean std=std stderr=se lclm=lcl uclm=ucl;
run;

%tfltitle(num=14.4.6.2, type=Figure,
   text=%str(Mean (+/- SE) Change from Baseline in Pharmacodynamic Biomarker over the Repeated-Dosing Period by Dose Level),
   pop=Pharmacodynamic Analysis Population,
   foot=%str(Points = arithmetic mean change from baseline by dose level at each study-day time over the repeated-dosing period; whiskers = +/- 1 SE. Plateau across days indicates a maintained PD effect at steady state. MAD: across-dose comparison is descriptive (placebo pooled).));
proc sgplot data=_m;
  refline 0 / axis=y lineattrs=(pattern=dot);
  series x=reltm y=mean / group=&TRTVAR markers
                          markerattrs=(symbol=circlefilled)
                          lineattrs=(thickness=2);
  scatter x=reltm y=mean / group=&TRTVAR yerrorlower=eval(mean-se)
                           yerrorupper=eval(mean+se) errorbarattrs=(thickness=1);
  xaxis label='Study Day (repeated-dosing period)' type=linear
        /* tick at dosing days; mark planned steady-state day if applicable */;
  yaxis label='Mean Change from Baseline (units)';
  keylegend / title='Dose Level' position=bottom;
run;
