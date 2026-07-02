/******************************************************************************
* FIGURE    : f_lab_change  (Crossover - 2x2 or Williams)
* TITLE     : Mean (SE) Change from Baseline in Laboratory Values by Visit
*             and Treatment
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADLB (PARAM/PARAMCD, CHG, AVISIT/AVISITN, TRTA/TRTAN, APERIODC,
*             TRTSEQP)
* NOTE      : PSEUDOCODE. Within-participant crossover -> one mean(SE) profile per
*             analysis treatment TRTA (collapsed across sequence; each participant
*             appears once per treatment received). CHG = change from the
*             within-period baseline. One panel per laboratory parameter;
*             X = visit, series = TRTA. APERIODC retained for an optional
*             by-period overlay.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=CROSSOVER);     /* TRTVAR=TRTA TRTNVAR=TRTAN BYPERIOD=APERIOD APERIODC SEQVAR=TRTSEQP */

data lb;
  set adam.adlb(where=(SAFFL='Y' and ANL01FL='Y' and AVISITN>0
                       and PARAMCD in ('ALT','AST','BILI','CREAT','ALP','GGT')));
  /* CHG, treatment, period, sequence all from ADaM - no re-derivation        */
run;

/*--- mean (SE) of CHG by treatment x visit x parameter ------------------*
* Crossover: group = &TRTVAR (=TRTA). A by-period variant would add          *
* APERIODC to CLASS and panel/overlay on period.                           */
proc means data=lb nway noprint;
  class PARAMCD PARAM &TRTVAR &TRTNVAR AVISITN AVISIT;
  var CHG;
  output out=_m n=n mean=mean stderr=se;
run;
data _m; set _m;
  lo = mean - se;  hi = mean + se;     /* error-bar bounds */
run;
proc sort data=_m; by PARAMCD &TRTNVAR AVISITN; run;

%tfltitle(num=14.3.4.5, type=Figure,
   text=%str(Mean (SE) Change from Baseline in Laboratory Values by Visit and Treatment),
   pop=Safety Population,
   foot=%str(Points = mean change from within-period baseline; bars = +/- 1 SE. One profile per analysis treatment (crossover; each participant contributes per treatment received). SI units.));

/* one panel per parameter, treatment as the overlaid series */
proc sgpanel data=_m;
  panelby PARAM / columns=2 novarname uniscale=column;
  series  x=AVISITN y=mean / group=&TRTVAR markers
                             lineattrs=(thickness=2) markerattrs=(symbol=circlefilled);
  scatter x=AVISITN y=mean / group=&TRTVAR yerrorlower=lo yerrorupper=hi
                             markerattrs=(size=0);
  refline 0 / lineattrs=(pattern=shortdash);
  rowaxis label='Mean change from baseline';
  colaxis label='Visit' integer;
  keylegend / title='Treatment' position=bottom;
run;
