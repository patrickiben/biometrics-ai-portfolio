/******************************************************************************
* FIGURE    : f_pd_change  (Parallel-group / per-dose)
* TITLE     : Mean (+/- SE) Change from Baseline in Pharmacodynamic Biomarker
*             over Time by Treatment
* POPULATION: PD / Pharmacodynamic Analysis Population (PDFL='Y')
* INPUT     : ADPD (PARAMCD = target PD biomarker; CHG, AVISITN/ATPTN)
* NOTE      : PSEUDOCODE. Parallel-group: one line per treatment (dose);
*             column/group variable = TRT01A/TRT01AN. Mean change from
*             baseline with SE error bars across nominal time. Descriptive
*             across-treatment comparison (no within-participant contrast).
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=PARALLEL);                 /* group = TRT01A (= dose)      */

%let PDPARM = PDMARK1;   /* target PD biomarker PARAMCD (one figure = one)   */

data pd;
  set adam.adpd(where=(PDFL='Y' and PARAMCD="&PDPARM" and AVISITN>0
                       and not missing(CHG)));
  /* nominal post-baseline visits/timepoints; ADPD-provided CHG (vs BASE)    */
run;

/*--- mean change + SE per treatment x time ------------------------------*/
proc means data=pd nway noprint;
  class &TRTVAR &TRTNVAR AVISITN AVISIT;
  var CHG;
  output out=_m n=n mean=mean std=std stderr=se lclm=lcl uclm=ucl;
run;

%tfltitle(num=14.4.6.2, type=Figure,
   text=%str(Mean (+/- SE) Change from Baseline in Pharmacodynamic Biomarker over Time by Treatment),
   pop=Pharmacodynamic Analysis Population,
   foot=%str(Points = arithmetic mean change from baseline by treatment (dose) at each nominal visit; whiskers = +/- 1 SE. Parallel-group: across-treatment comparison is descriptive.));
proc sgplot data=_m;
  refline 0 / axis=y lineattrs=(pattern=dot);
  series x=AVISITN y=mean / group=&TRTVAR markers
                            markerattrs=(symbol=circlefilled)
                            lineattrs=(thickness=2);
  scatter x=AVISITN y=mean / group=&TRTVAR yerrorlower=eval(mean-se)
                             yerrorupper=eval(mean+se) errorbarattrs=(thickness=1);
  xaxis label='Nominal Visit' type=linear
        values=(1 to 10 by 1) /* map to AVISITN; format AVISIT labels */;
  yaxis label='Mean Change from Baseline (units)';
  keylegend / title='Treatment (Dose)' position=bottom;
run;
