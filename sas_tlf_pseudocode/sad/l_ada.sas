/******************************************************************************
* LISTING   : l_ada  (SAD - Single Ascending Dose)
* TITLE     : Listing of Anti-Drug Antibody (ADA) Results
* POPULATION: Immunogenicity / ADA Evaluable Population (ADAFL='Y')
* INPUT     : ADIS (immunogenicity analysis: PARAM/PARAMCD, AVALC/AVAL =
*             ADA/NAb result, titer; AVISIT/ATPT sampling; ADaM-derived
*             baseline and treatment-emergent flags)
* NOTE      : PSEUDOCODE. One row per ADA sample record, ordered by dose level,
*             participant, then visit/timepoint. SAD: one (single) dose per participant;
*             treatment column = TRT01A (= dose level, placebo pooled). Single
*             dose => sampling at baseline and scheduled post-dose times. Shows
*             result, titer and the ADaM-provided status flags (baseline,
*             treatment-emergent, NAb) - no re-derivation of the assay outcome.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=SAD);

data ada;
  set adam.adis(where=(ADAFL='Y'));
  length subjid $20 trt $40 result $16 titer $12 bsln $4 teflag $4 nab $12;
  subjid = scan(USUBJID,-1,'-');              /* short site-participant id        */
  trt    = &TRTVAR;                           /* dose-level column            */
  result = AVALC;                             /* ADA result (Positive/Negative)*/
  titer  = ifc(missing(AVAL),' ',put(AVAL,8.));   /* reported titer            */
  bsln   = ifc(ABLFL='Y','Yes','No');         /* baseline record              */
  teflag = ifc(ADAEMFL='Y','Yes','No');       /* treatment-emergent ADA       */
  nab    = NABRESC;                           /* NAb result (if assessed)     */
  reltm  = coalesce(ATPTN, AVISITN);          /* sort key: time after dose    */
  keep trt subjid PARAM PARAMCD AVISIT AVISITN ATPT reltm ADT
       result titer bsln teflag nab;
run;

proc sort data=ada; by trt subjid PARAM reltm AVISITN; run;

%tfltitle(num=16.2.10.1, type=Listing, text=Listing of Anti-Drug Antibody (ADA) Results,
          pop=Immunogenicity (ADA Evaluable) Population,
          foot=%str(One row per ADA sample. TE-ADA = treatment-emergent (induced or boosted) per ADIS. NAb = neutralizing antibody result. SAD: single dose; treatment column = TRT01A (dose level, placebo pooled).));
proc report data=ada nowd split='*';
  columns trt subjid PARAM ('Visit*/ Timepoint' AVISIT ATPT) ADT
          ('ADA*Result' result) ('Titer' titer) ('Baseline' bsln)
          ('TE-ADA' teflag) ('NAb*Result' nab);
  define trt    / order 'Dose Level' width=18 flow;
  define subjid / order 'Participant'   width=12;
  define PARAM  / order 'Assay (parameter)' width=22 flow;
  define AVISIT / display 'Visit' width=12 flow;
  define ATPT   / display 'Timepoint' width=12 flow;
  define ADT    / display 'Date' width=12;
  define result / display center width=10;
  define titer  / display center width=8;
  define bsln   / display center width=8;
  define teflag / display center width=7;
  define nab    / display center width=10;
  break after trt / page;                     /* one dose level per page block */
run;
