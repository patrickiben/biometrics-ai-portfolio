/******************************************************************************
* LISTING   : l_vitals  (Crossover - 2x2 or Williams)
* TITLE     : Listing of Vital Signs
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADVS (all vital-sign parameters)
* NOTE      : PSEUDOCODE. Participant-level listing ordered by sequence, participant,
*             treatment PERIOD, treatment, parameter, visit/timepoint. Shows
*             actual value, period baseline and change, and reference-range
*             indicator. Crossover key: TRTSEQP / APERIODC / TRTA all retained
*             so a reader can see what each participant got in each period.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=CROSSOVER);     /* SEQVAR=TRTSEQP ; BYPERIOD=APERIOD APERIODC ; TRTVAR=TRTA */

data vs;
  set adam.advs(where=(SAFFL='Y'));
  length subjid $20;
  subjid = scan(USUBJID, -1, '-');           /* short participant id for display  */
run;

proc sort data=vs;
  by &SEQVAR USUBJID APERIOD APERIODC &TRTVAR PARAMCD AVISITN ATPTN;
run;

%tfltitle(num=16.2.7.3, type=Listing,
   text=%str(Listing of Vital Signs),
   pop=Safety Population,
   foot=%str(Baseline = within-period baseline; CHG = AVAL - BASE. ANRIND = reference-range indicator (L/N/H). Ordered by sequence, participant, treatment period.));
proc report data=vs nowd split='|';
  columns &SEQVAR subjid APERIODC &TRTVAR PARAM AVISIT ATPT
          AVAL BASE CHG ANRIND;
  define &SEQVAR / order 'Sequence'        width=10;
  define subjid  / order 'Participant'         width=10;
  define APERIODC/ order 'Period'          width=10;
  define &TRTVAR / order 'Treatment'       width=16;
  define PARAM   / order 'Parameter'       width=22;
  define AVISIT  / order 'Visit'           width=14;
  define ATPT    / display 'Timepoint'     width=12;
  define AVAL    / display 'Value'         width=8;
  define BASE    / display 'Baseline'      width=9;
  define CHG     / display 'Change'        width=8;
  define ANRIND  / display 'Range|Ind'     width=7;
run;
