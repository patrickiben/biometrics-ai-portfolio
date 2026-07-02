/******************************************************************************
* LISTING   : l_pd  (MAD - Multiple Ascending Dose)
* TITLE     : Listing of Pharmacodynamic Biomarker Results
* POPULATION: PD / Pharmacodynamic Analysis Population (PDFL='Y')
* INPUT     : ADPD (PARAM/PARAMCD; AVAL, BASE, CHG, PCHG; AVISIT/ATPT study
*             day + time post-dose; ADT analysis date)
* NOTE      : PSEUDOCODE. One row per PD analysis record, ordered by dose level,
*             participant, parameter, then study day / timepoint. MAD: repeated
*             dosing => records span the multi-day treatment period (Day 1 ...
*             steady-state day); treatment column = TRT01A (= dose level).
*             Shows observed value, baseline, change and % change from ADaM
*             (no re-derivation).
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=MAD);

data pd;
  set adam.adpd(where=(PDFL='Y'));
  length subjid $20 trt $40 cval cbase cchg cpchg $12;
  subjid = scan(USUBJID,-1,'-');              /* short site-participant id        */
  trt    = &TRTVAR;                           /* treatment (dose) column      */
  cval   = put(AVAL,  8.2);
  cbase  = put(BASE,  8.2);
  cchg   = ifc(missing(CHG), ' ', put(CHG, 8.2));
  cpchg  = ifc(missing(PCHG),' ', put(PCHG,8.1));
  reltm  = coalesce(ADY, AVISITN);            /* study day sort key            */
  reltp  = coalesce(ATPTN, 0);                /* time post-dose within day      */
  keep trt subjid PARAM PARAMCD AVISIT AVISITN ATPT ATPTN reltm reltp ADT
       cval cbase cchg cpchg;
run;

proc sort data=pd; by trt subjid PARAM reltm AVISITN reltp; run;

%tfltitle(num=16.2.9.1, type=Listing, text=Listing of Pharmacodynamic Biomarker Results,
          pop=Pharmacodynamic Analysis Population,
          foot=%str(One row per PD analysis record over the repeated-dosing period. Change and % change vs baseline (BASE) as provided in ADPD. MAD: treatment column = TRT01A (= dose level); records ordered by study day then time post-dose.));
proc report data=pd nowd split='*';
  columns trt subjid PARAM ('Study Day*/ Timepoint' AVISIT ATPT) ADT
          ('Observed*Value' cval) ('Baseline' cbase)
          ('Change' cchg) ('% Change' cpchg);
  define trt    / order 'Treatment (Dose)' width=18 flow;
  define subjid / order 'Participant'   width=12;
  define PARAM  / order 'PD Parameter (units)' width=24 flow;
  define AVISIT / display 'Study Day' width=12 flow;
  define ATPT   / display 'Timepoint' width=12 flow;
  define ADT    / display 'Date' width=12;
  define cval   / display center width=10;
  define cbase  / display center width=10;
  define cchg   / display center width=8;
  define cpchg  / display center width=8;
  break after trt / page;                     /* one dose level per page block */
run;
