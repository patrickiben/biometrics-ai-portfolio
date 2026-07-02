/******************************************************************************
* LISTING   : l_pd  (Single-/Fixed-Sequence, e.g. DDI)
* TITLE     : Listing of Pharmacodynamic Biomarker Results
* POPULATION: PD / Pharmacodynamic Analysis Population (PDFL='Y')
* INPUT     : ADPD (all PD biomarker parameters; AVAL, BASE, CHG, PCHG;
*             AVISIT/ATPT; APERIODC, TRTA, ANRIND)
* NOTE      : PSEUDOCODE. Participant-level listing ordered by participant, treatment
*             PERIOD (fixed order), treatment, parameter, visit/timepoint.
*             Shows actual value, within-period baseline and change, and
*             reference-range indicator. Single-/fixed-sequence key: APERIODC /
*             TRTA retained so a reader can see what each participant received in
*             each fixed period (no randomized sequence -> no TRTSEQP column).
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=SINGLESEQ);     /* SEQVAR= (none) ; BYPERIOD=APERIOD APERIODC ; TRTVAR=TRTA */

data pd;
  set adam.adpd(where=(PDFL='Y'));
  length subjid $20;
  subjid = scan(USUBJID, -1, '-');           /* short participant id for display  */
run;

proc sort data=pd;
  by USUBJID APERIOD APERIODC &TRTVAR PARAMCD AVISITN ATPTN;
run;

%tfltitle(num=16.2.9.1, type=Listing,
   text=%str(Listing of Pharmacodynamic Biomarker Results),
   pop=Pharmacodynamic Analysis Population,
   foot=%str(Baseline = within-period baseline; CHG = AVAL - BASE; PCHG = % change vs BASE. ANRIND = reference-range indicator (L/N/H). Single-/fixed-sequence: ordered by participant, fixed treatment period (Period 1 = reference; subsequent period(s) = test). No randomized sequence.));
proc report data=pd nowd split='|';
  columns subjid APERIODC &TRTVAR PARAM AVISIT ATPT
          AVAL BASE CHG PCHG ANRIND;
  define subjid  / order 'Participant'         width=10;
  define APERIODC/ order 'Period'          width=10;
  define &TRTVAR / order 'Treatment'       width=16;
  define PARAM   / order 'PD Parameter'    width=24;
  define AVISIT  / order 'Visit'           width=14;
  define ATPT    / display 'Timepoint'     width=12;
  define AVAL    / display 'Value'         width=9;
  define BASE    / display 'Baseline'      width=9;
  define CHG     / display 'Change'        width=8;
  define PCHG    / display '% Change'      width=8;
  define ANRIND  / display 'Range|Ind'     width=7;
run;
