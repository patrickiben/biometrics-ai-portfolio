/******************************************************************************
* LISTING   : l_lab_abnormal  (Single-/Fixed-Sequence, e.g. DDI)
* TITLE     : Listing of Abnormal Laboratory Values by Period
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADLB (PARAM/PARAMCD, AVAL, BASE, CHG, ANRIND, ATOXGRN, A1LO/A1HI,
*             ONTRTFL, APERIOD/APERIODC)
* NOTE      : PSEUDOCODE. One row per on-treatment abnormal laboratory record
*             (ANRIND in (LOW,HIGH) or CTCAE grade >=1), ordered by participant,
*             period, parameter, then visit/date. Shows value, reference range,
*             normal-range flag, CTCAE grade, and change from baseline.
*             On-treatment scope = ONTRTFL='Y'. Single-/fixed-sequence design:
*             blocked by participant then PERIOD (Period 1 = reference, victim
*             alone; Period 2 = test, victim + perpetrator) so within-participant
*             behavior across periods is readable. Listings show all participants
*             regardless of treatment-emergent flag.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=SINGLESEQ);     /* TRTVAR=TRTA BYPERIOD=APERIOD APERIODC SEQVAR=(none) */

data lb;
  set adam.adlb(where=(SAFFL='Y' and ONTRTFL='Y' and not missing(AVAL)
                       and (upcase(ANRIND) in ('LOW','HIGH') or ATOXGRN >= 1)));
  length subjid $20 period $20 flag $8 grade $6 range $24 reldy $8;
  subjid = scan(USUBJID,-1,'-');                 /* short site-participant id     */
  period = APERIODC;                             /* Period 1 (Ref) / 2 (Test) */
  flag   = ANRIND;                               /* LOW / HIGH (abnormal dir) */
  grade  = ifc(missing(ATOXGRN),' ',cats('Gr ',put(ATOXGRN,1.)));
  range  = catx(' - ', put(A1LO, best8.), put(A1HI, best8.));   /* ref range  */
  reldy  = ifc(missing(ADY),' ',put(ADY,4.));    /* analysis study day        */
  keep subjid period APERIOD PARAM AVISIT AVISITN reldy ADTC AVAL range flag grade BASE CHG;
run;

proc sort data=lb; by subjid APERIOD PARAM AVISITN ADTC; run;

%tfltitle(num=16.2.8.2, type=Listing, text=Listing of Abnormal Laboratory Values by Period,
          pop=Safety Population,
          foot=%str(Abnormal = normal-range indicator Low or High (ANRIND) or CTCAE Grade >=1 (ATOXGRN). On-treatment records only (ONTRTFL=Y). Range = lab reference range (A1LO - A1HI). Period 1 = reference (victim alone); Period 2 = test (victim + perpetrator). Listing includes all participants, not only treatment-emergent.));
proc report data=lb nowd split='*';
  columns subjid period PARAM AVISIT ('Study*Day' reldy) ('Result' AVAL)
          ('Reference*Range' range) ('Flag' flag) ('CTCAE*Grade' grade)
          ('Baseline' BASE) ('Change*from BL' CHG);
  define subjid / order 'Participant'   width=12;
  define period / order 'Study*Period' width=14;
  define PARAM  / order 'Laboratory Parameter' width=22 flow;
  define AVISIT / display 'Visit'    width=12;
  define reldy  / display center width=6;
  define AVAL   / display center width=9;
  define range  / display center width=14;
  define flag   / display center width=6;       /* LOW / HIGH                 */
  define grade  / display center width=6;
  define BASE   / display center width=9;
  define CHG    / display center width=9;
  break after subjid / page;                     /* one participant per page       */
run;
