/******************************************************************************
* LISTING   : l_lab_abnormal  (Parallel-group)
* TITLE     : Listing of Abnormal Laboratory Values
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADLB (PARAM/PARAMCD, AVAL, BASE, CHG, ANRIND, ATOXGR, A1LO/A1HI)
* NOTE      : PSEUDOCODE. One row per abnormal post-baseline laboratory record
*             (ANRIND ne NORMAL or toxicity grade >=1), ordered by participant,
*             parameter, then visit/date. Shows value, reference range, normal-
*             range flag, CTCAE grade, and change from baseline.
*             Listings show all participants regardless of treatment-emergent flag.
*             Parallel design: ordered/blocked by TRT01A.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=PARALLEL);          /* -> TRTVAR=TRT01A, TRTNVAR=TRT01AN  */

data lb;
  set adam.adlb(where=(SAFFL='Y' and not missing(AVAL)
                       and (upcase(ANRIND) ne 'NORMAL' or ATOXGRN >= 1)));
  length subjid $20 trt $40 flag $8 grade $6 range $24 reldy $8;
  subjid = scan(USUBJID,-1,'-');                 /* short site-participant id     */
  trt    = &TRTVAR;
  flag   = ANRIND;                               /* LOW / HIGH (abnormal dir) */
  grade  = ifc(missing(ATOXGRN),' ',cats('Gr ',put(ATOXGRN,1.)));
  range  = catx(' - ', put(A1LO, best8.), put(A1HI, best8.));   /* ref range  */
  reldy  = ifc(missing(ADY),' ',put(ADY,4.));    /* analysis study day        */
  keep trt subjid PARAM AVISIT reldy ADTC AVAL range flag grade BASE CHG;
run;

proc sort data=lb; by trt subjid PARAM AVISITN ADTC; run;

%tfltitle(num=16.2.9.1, type=Listing, text=Listing of Abnormal Laboratory Values,
          pop=Safety Population,
          foot=%str(Abnormal = outside reference range (Low/High) or CTCAE Grade >=1. Range = lab reference range (A1LO - A1HI). Listing includes all participants, not only treatment-emergent.));
proc report data=lb nowd split='*';
  columns trt subjid PARAM AVISIT ('Study*Day' reldy) ('Result' AVAL)
          ('Reference*Range' range) ('Flag' flag) ('CTCAE*Grade' grade)
          ('Baseline' BASE) ('Change*from BL' CHG);
  define trt    / order 'Treatment' width=18;
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
  break after trt / page;                        /* one treatment per page    */
run;
