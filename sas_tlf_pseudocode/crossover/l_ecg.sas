/******************************************************************************
* LISTING   : l_ecg  (Crossover - 2x2 or Williams)
* TITLE     : Listing of ECG Parameters
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADEG (all ECG parameters incl. interpretation)
* NOTE      : PSEUDOCODE. Participant-level listing ordered by sequence, participant,
*             treatment PERIOD, treatment, parameter, visit/timepoint. Shows
*             actual value, within-period baseline, change, reference-range
*             indicator and overall ECG interpretation. Crossover key:
*             TRTSEQP / APERIODC / TRTA retained to show each period's treatment.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=CROSSOVER);     /* SEQVAR=TRTSEQP ; BYPERIOD=APERIOD APERIODC ; TRTVAR=TRTA */

data eg;
  set adam.adeg(where=(SAFFL='Y'));
  length subjid $20;
  subjid = scan(USUBJID, -1, '-');           /* short participant id for display  */
run;

proc sort data=eg;
  by &SEQVAR USUBJID APERIOD APERIODC &TRTVAR PARAMCD AVISITN ATPTN;
run;

%tfltitle(num=16.2.8.1, type=Listing,
   text=%str(Listing of ECG Parameters),
   pop=Safety Population,
   foot=%str(Baseline = within-period baseline; CHG = AVAL - BASE. ANRIND = reference-range indicator. Interpretation = overall ECG read (Normal / Abnormal NCS / Abnormal CS). Ordered by sequence, participant, treatment period.));
proc report data=eg nowd split='|';
  columns &SEQVAR subjid APERIODC &TRTVAR PARAM AVISIT ATPT
          AVAL BASE CHG ANRIND AVALC;
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
  define AVALC   / display 'Interpretation' width=18;  /* overall read for interpretation params */
run;
