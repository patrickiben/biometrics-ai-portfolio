/******************************************************************************
* FIGURE    : f_pk_conc_individual  (Crossover - 2x2 or Williams)
* TITLE     : Individual Plasma Concentration-Time Profiles by Participant
*             (Semi-Logarithmic)
* POPULATION: PK Concentration Population (PKFL='Y')
* INPUT     : ADPC (AVAL = concentration; ATPTN = nominal time)
* NOTE      : PSEUDOCODE. Crossover -> one panel per PARTICIPANT, with that
*             participant's Test and Reference period profiles OVERLAID on the same
*             axes (grouped by treatment received, TRTA). This is the natural
*             within-participant crossover view: each participant is their own control.
*             Semi-log y. Paneled via SGPANEL across participants.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=CROSSOVER);     /* overlay = TRTA; panel = USUBJID          */

data pc;
  set adam.adpc(where=(PKFL='Y'));
  length subjid $20;
  subjid = scan(USUBJID,-1,'-');
  trt    = &TRTVAR;                          /* treatment received this period  */
  if upcase(AVALC)='BLQ' then AVAL=.;        /* drop BLQ from individual log    */
  ylog   = ifn(AVAL>0, AVAL, .);
run;
proc sort data=pc; by subjid &TRTVAR ATPTN; run;

%tfltitle(num=14.4.2.3, type=Figure,
   text=%str(Individual Plasma Concentration-Time Profiles by Participant (Semi-Logarithmic)),
   pop=Pharmacokinetic Concentration Population,
   foot=%str(One panel per participant; Test and Reference period profiles overlaid (treatment received, TRTA) so each participant serves as own control. Semi-log y; BLQ omitted. Nominal sampling times.));
/*--- one panel per participant, Test vs Reference overlaid -------------------*/
proc sgpanel data=pc;
  panelby subjid / columns=4 rows=3 novarname;
  series  x=ATPTN y=ylog / group=&TRTVAR markers
                           lineattrs=(thickness=1.5) markerattrs=(symbol=circlefilled);
  colaxis label='Nominal Time (h)' values=(0 to 24 by 4);
  rowaxis type=log logbase=10 label='Concentration (unit), log scale';
  keylegend / title='Treatment' position=bottom;
run;
