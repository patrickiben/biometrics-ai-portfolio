/******************************************************************************
* LISTING   : l_pd  (Parallel-group)
* TITLE     : Listing of Pharmacodynamic Biomarker Results
* POPULATION: PD / Pharmacodynamic Analysis Population (PDFL='Y')
* INPUT     : ADPD (PARAM/PARAMCD; AVAL, BASE, CHG, PCHG; AVISIT/ATPT;
*             ADTM/ADT analysis date-time)
* NOTE      : PSEUDOCODE. One row per PD analysis record, ordered by
*             treatment, participant, parameter, then visit/timepoint. Parallel-
*             group: treatment column = TRT01A. Shows observed value,
*             baseline, change and % change from ADaM (no re-derivation).
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=PARALLEL);

data pd;
  set adam.adpd(where=(PDFL='Y'));
  length subjid $20 trt $40 cval cbase cchg cpchg $12;
  subjid = scan(USUBJID,-1,'-');              /* short site-participant id        */
  trt    = &TRTVAR;                           /* treatment (dose) column      */
  cval   = put(AVAL,  8.2);
  cbase  = put(BASE,  8.2);
  cchg   = ifc(missing(CHG), ' ', put(CHG, 8.2));
  cpchg  = ifc(missing(PCHG),' ', put(PCHG,8.1));
  reltm  = coalesce(ATPTN, AVISITN);          /* sort key: visit/timepoint    */
  keep trt subjid PARAM PARAMCD AVISIT AVISITN ATPT ATPTN reltm ADT
       cval cbase cchg cpchg;
run;

proc sort data=pd; by trt subjid PARAM reltm AVISITN; run;

%tfltitle(num=16.2.10.1, type=Listing, text=Listing of Pharmacodynamic Biomarker Results,
          pop=Pharmacodynamic Analysis Population,
          foot=%str(One row per PD analysis record. Change and % change vs baseline (BASE) as provided in ADPD. Parallel-group: treatment column = TRT01A.));
proc report data=pd nowd split='*';
  columns trt subjid PARAM ('Visit*/ Timepoint' AVISIT ATPT) ADT
          ('Observed*Value' cval) ('Baseline' cbase)
          ('Change' cchg) ('% Change' cpchg);
  define trt    / order 'Treatment' width=18 flow;
  define subjid / order 'Participant'   width=12;
  define PARAM  / order 'PD Parameter (units)' width=24 flow;
  define AVISIT / display 'Visit' width=12 flow;
  define ATPT   / display 'Timepoint' width=12 flow;
  define ADT    / display 'Date' width=12;
  define cval   / display center width=10;
  define cbase  / display center width=10;
  define cchg   / display center width=8;
  define cpchg  / display center width=8;
  break after trt / page;                     /* one treatment per page block */
run;
