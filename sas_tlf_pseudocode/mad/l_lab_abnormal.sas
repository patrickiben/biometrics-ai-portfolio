/******************************************************************************
* LISTING   : l_lab_abnormal  (MAD - Multiple Ascending Dose)
* TITLE     : Listing of Abnormal Laboratory Values
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADLB (PARAM/PARAMCD, AVAL, BASE, CHG, ANRIND, A1LO/A1HI, ATOXGRN,
*             AVISIT/AVISITN, ADT/ADY, ONTRTFL, TRT01A/TRT01AN)
* NOTE      : PSEUDOCODE. One row per abnormal on-treatment laboratory record,
*             ordered by dose level, participant and collection day. MAD: parallel
*             cohorts, one (dose) treatment per participant -> show TRT01A (= dose
*             level) so each record is anchored to the participant's dose cohort.
*             Repeated dosing -> ADY (study day) and AVISIT span the multiple-dose
*             period, so the time course of each abnormality across Day 1..Day N
*             is visible. Abnormal = ANRIND in (LOW,HIGH) OR CTCAE toxicity grade
*             ATOXGRN >= 1; on-treatment scope ONTRTFL='Y'. Reference range, flag
*             and grade shown.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=MAD);          /* -> TRTVAR=TRT01A (= dose level)            */

data lb;
  set adam.adlb(where=(SAFFL='Y' and ONTRTFL='Y'
                       and (upcase(ANRIND) in ('LOW','HIGH') or ATOXGRN >= 1)));
  length subjid $20 trt $40 flag $6 rng $24 grade $6;
  subjid = scan(USUBJID,-1,'-');            /* short site-participant id          */
  trt    = &TRTVAR;                          /* dose level (TRT01A)            */
  flag   = ifc(upcase(ANRIND)='HIGH','High',ifc(upcase(ANRIND)='LOW','Low',' '));
  grade  = ifc(missing(ATOXGRN),' ',put(ATOXGRN,1.)); /* CTCAE toxicity grade   */
  rng    = catx(' - ', put(A1LO,best8.), put(A1HI,best8.));  /* reference range */
  colday = ifc(missing(ADY),' ',put(ADY,4.));               /* study day      */
  keep trt subjid PARAM AVISIT colday AVAL BASE CHG rng flag grade;
run;

/* sort by dose level, participant, parameter, day - dose cohort anchors the row  */
proc sort data=lb; by trt subjid PARAM colday; run;

%tfltitle(num=16.2.8.1, type=Listing, text=Listing of Abnormal Laboratory Values,
          pop=Safety Population,
          foot=%str(Abnormal = normal-range indicator Low/High (ANRIND) or CTCAE toxicity grade ATOXGRN >= 1; on-treatment records only (ONTRTFL=Y). Trt = dose level (TRT01A; MAD - one dose per participant). Day = study day relative to first dose, spanning the multiple-dose period. Reference range = A1LO - A1HI. SI units.));
proc report data=lb nowd split='*';
  columns trt subjid ('Laboratory*Parameter' PARAM) AVISIT colday
          ('Value' AVAL) ('Baseline' BASE) ('Change' CHG)
          ('Reference*Range' rng) ('Flag' flag) ('Grade' grade);
  define trt    / order 'Dose Level' width=16 flow;
  define subjid / order 'Participant'  width=12;
  define PARAM  / display 'Parameter' width=20 flow;
  define AVISIT / display 'Visit'   width=12;
  define colday / display 'Day'     center width=5;
  define AVAL   / display center width=8;
  define BASE   / display center width=8;
  define CHG    / display center width=8;
  define rng    / display center width=14;
  define flag   / display center width=6;
  define grade  / display center width=6;
  break after subjid / skip;                 /* one block per participant         */
run;
