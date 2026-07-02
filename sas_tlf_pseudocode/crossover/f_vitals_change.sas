/******************************************************************************
* FIGURE    : f_vitals_change  (Crossover - 2x2 or Williams)
* TITLE     : Mean (SE) Change from Baseline in Vital Signs by Visit
*             and Treatment
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADVS (PARAMCD in SYSBP, DIABP, PULSE)
* NOTE      : PSEUDOCODE. Within-participant crossover -> one mean(SE) profile per
*             analysis treatment TRTA (collapsed across sequence; each participant
*             appears once per treatment received). CHG = change from within-
*             period baseline. Panel per parameter; X = visit, series = TRTA.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=CROSSOVER);     /* TRTVAR=TRTA ; BYPERIOD=APERIOD APERIODC */

data vs;
  set adam.advs(where=(SAFFL='Y' and ANL01FL='Y' and AVISITN>0
                       and PARAMCD in ('SYSBP','DIABP','PULSE')));
run;

/*--- mean (SE) of CHG by treatment x visit x parameter ------------------*
* Crossover: group = &TRTVAR (=TRTA). A by-period variant would add        *
* APERIODC to CLASS and panel/overlay on period.                          */
proc means data=vs nway noprint;
  class PARAMCD &TRTVAR &TRTNVAR AVISITN AVISIT;
  var CHG;
  output out=_m n=n mean=mean stderr=se;
run;
data _m; set _m;
  lo = mean - se;  hi = mean + se;     /* error-bar bounds */
run;
proc sort data=_m; by PARAMCD &TRTNVAR AVISITN; run;

%tfltitle(num=14.3.7.2, type=Figure,
   text=%str(Mean (SE) Change from Baseline in Vital Signs by Visit and Treatment),
   pop=Safety Population,
   foot=%str(Points = mean change from within-period baseline; bars = +/- 1 SE. One profile per analysis treatment (crossover; each participant contributes per treatment received).));

/* one panel per parameter, treatment as the overlaid series */
proc sgpanel data=_m;
  panelby PARAMCD / columns=1 novarname uniscale=column;
  series  x=AVISITN y=mean / group=&TRTVAR markers
                             lineattrs=(thickness=2) markerattrs=(symbol=circlefilled);
  scatter x=AVISITN y=mean / group=&TRTVAR yerrorlower=lo yerrorupper=hi
                             markerattrs=(size=0);
  refline 0 / lineattrs=(pattern=shortdash);
  rowaxis label='Mean change from baseline';
  colaxis label='Visit' integer;
  keylegend / title='Treatment' position=bottom;
run;
