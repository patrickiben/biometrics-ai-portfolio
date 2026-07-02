/******************************************************************************
* LISTING   : l_lab_abnormal  (Single Ascending Dose)
* TITLE     : Listing of Abnormal Laboratory Values
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADLB (PARAM/PARAMCD, AVAL, BASE, CHG, ANRIND, ATOXGR, A1LO/A1HI)
* NOTE      : PSEUDOCODE. One row per abnormal ON-TREATMENT laboratory record
*             (ANRIND in LOW/HIGH or CTCAE grade >=1), ordered by dose level,
*             participant, parameter, then visit/date. Shows value, reference
*             range, normal-range flag, CTCAE grade, and change from baseline.
*             On-treatment scope = ONTRTFL='Y' (same as R twin).
*             SAD design: ordered/blocked by TRT01A (ascending dose level);
*             placebo pooled. One single dose per participant.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=SAD);               /* -> TRTVAR=TRT01A, TRTNVAR=TRT01AN  */

data lb;
  set adam.adlb(where=(SAFFL='Y' and ONTRTFL='Y' and not missing(AVAL)
                       and (upcase(ANRIND) in ('LOW','HIGH') or ATOXGRN >= 1)));
  length subjid $20 trt $40 flag $8 grade $6 range $24 reldy $8;
  subjid = scan(USUBJID,-1,'-');                 /* short site-participant id     */
  trt    = &TRTVAR;                              /* dose level (TRT01A)       */
  flag   = ANRIND;                               /* LOW / HIGH (abnormal dir) */
  grade  = ifc(missing(ATOXGRN),' ',cats('Gr ',put(ATOXGRN,1.)));
  range  = catx(' - ', put(A1LO, best8.), put(A1HI, best8.));   /* ref range  */
  reldy  = ifc(missing(ADY),' ',put(ADY,4.));    /* analysis study day        */
  keep trt subjid PARAM AVISIT reldy ADTC AVAL range flag grade BASE CHG;
run;

proc sort data=lb; by trt subjid PARAM AVISITN ADTC; run;

%tfltitle(num=16.2.8.1, type=Listing, text=Listing of Abnormal Laboratory Values,
          pop=Safety Population,
          foot=%str(Abnormal = reference-range flag Low/High (ANRIND) or CTCAE Grade >=1 (ATOXGRN). On-treatment records only (ONTRTFL='Y'). Range = lab reference range (A1LO - A1HI). Blocked by dose level (TRT01A); placebo pooled.));
proc report data=lb nowd split='*';
  columns trt subjid PARAM AVISIT ('Study*Day' reldy) ('Result' AVAL)
          ('Reference*Range' range) ('Flag' flag) ('CTCAE*Grade' grade)
          ('Baseline' BASE) ('Change*from BL' CHG);
  define trt    / order 'Dose Level' width=18;
  define subjid / order 'Participant'   width=12;
  define PARAM  / order 'Laboratory Parameter' width=22 flow;
  define AVISIT / display 'Visit'    width=12;
  define reldy  / display center width=6;
  define AVAL   / display center width=9;
  define range  / display center width=14;
  define flag   / display center width=6;       /* LOW / HIGH                 */
  define grade  / display center width=6;
  define BASE   / display center width=9;
  define CHG    / display center width=9;
  break after trt / page;                        /* one dose level per page    */
run;
