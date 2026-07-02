/******************************************************************************
* FIGURE    : f_pd_change  (Crossover - 2x2 or Williams)
* TITLE     : Mean (+/- SE) Change from Baseline in Pharmacodynamic Biomarker
*             over Time by Treatment
* POPULATION: PD / Pharmacodynamic Analysis Population (PDFL='Y')
* INPUT     : ADPD (PARAMCD = target PD biomarker; CHG, AVISITN/ATPTN;
*             TRTA/TRTAN, APERIODC, TRTSEQP from ADaM)
* NOTE      : PSEUDOCODE. Within-participant crossover: ONE mean(SE) profile per
*             analysis treatment TRTA (collapsed across sequence; each participant
*             appears once per treatment received). CHG = change from within-
*             period baseline (ADPD CHG). Curves overlaid for a direct within-
*             study Test-vs-Reference visual comparison. A by-period variant
*             adds APERIODC to CLASS and panels/overlays on period.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=CROSSOVER);     /* group/overlay variable = TRTA           */

%let PDPARM = PDMARK1;   /* target PD biomarker PARAMCD (one figure = one)   */

data pd;
  set adam.adpd(where=(PDFL='Y' and PARAMCD="&PDPARM" and AVISITN>0
                       and not missing(CHG)));
  /* nominal post-baseline visits/timepoints; ADPD-provided CHG (vs within-
     period BASE); treatment/period/sequence straight from ADaM             */
run;

/*--- mean change + SE per treatment x time (pooled across period) -------*
* Crossover: group = &TRTVAR (=TRTA). A by-period variant would add        *
* APERIODC to CLASS and panel/overlay on period.                          */
proc means data=pd nway noprint;
  class &TRTVAR &TRTNVAR AVISITN AVISIT;
  var CHG;
  output out=_m n=n mean=mean std=std stderr=se lclm=lcl uclm=ucl;
run;
proc sort data=_m; by &TRTNVAR AVISITN; run;

%tfltitle(num=14.2.6.2, type=Figure,
   text=%str(Mean (+/- SE) Change from Baseline in Pharmacodynamic Biomarker over Time by Treatment),
   pop=Pharmacodynamic Analysis Population,
   foot=%str(Points = arithmetic mean change from within-period baseline; whiskers = +/- 1 SE. One profile per analysis treatment (crossover; each participant contributes per treatment received, pooled across period).));
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
  keylegend / title='Treatment' position=bottom;
run;
