/******************************************************************************
* LISTING   : l_ada  (Single-/Fixed-Sequence, e.g. DDI)
* TITLE     : Listing of Anti-Drug Antibody (ADA) Results
* POPULATION: Immunogenicity / ADA Evaluable Population (ADAFL='Y')
* INPUT     : ADIS (immunogenicity analysis: PARAM/PARAMCD, AVALC/AVAL =
*             ADA/NAb result, titer; AVISIT/ATPT sampling; APERIODC; ADaM-
*             derived baseline and treatment-emergent flags)
* NOTE      : PSEUDOCODE. One row per ADA sample record, ordered by participant,
*             treatment PERIOD (fixed order), then visit/timepoint. Single-/
*             fixed-sequence: period column = APERIODC (Period 1 = reference;
*             subsequent period(s) = test); no randomized sequence -> no
*             TRTSEQP column. Shows result, titer and the ADaM-provided status
*             flags (baseline, treatment-emergent, NAb) - no re-derivation of
*             the assay outcome.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=SINGLESEQ);     /* BYPERIOD=APERIOD APERIODC ; SEQVAR= (none) ; TRTVAR=TRTA */

data ada;
  set adam.adis(where=(ADAFL='Y'));
  length subjid $20 result $16 titer $12 bsln $4 status $48 nab $12;
  subjid = scan(USUBJID,-1,'-');              /* short site-participant id        */
  result = AVALC;                             /* ADA result (Positive/Negative)*/
  titer  = ifc(missing(AVAL),' ',put(AVAL,8.));   /* reported titer            */
  bsln   = ifc(ADABLFL='Y','Yes','No');       /* baseline ADA-positive        */
  nab    = NABRESC;                           /* NAb result (if assessed)     */
  /* derived ADA status string from the ADIS-specific flags (no re-derivation
     of the assay outcome): treatment-emergent / persistent vs transient / NAb  */
  status = catx('; ',
                ifc(ADABLFL='Y','Baseline+',' '),
                ifc(TEADAFL='Y','Trt-emergent',' '),
                ifc(ADAPERFL='Y','Persistent',ifc(ADATRNFL='Y','Transient',' ')),
                ifc(NABFL='Y','NAb+',' '));
  reltm  = coalesce(ATPTN, AVISITN);          /* sort key                     */
  keep subjid APERIOD APERIODC &TRTVAR PARAM PARAMCD AVISIT AVISITN ATPT
       reltm ADT result titer bsln status nab;
run;

proc sort data=ada; by subjid APERIOD APERIODC &TRTVAR PARAM reltm AVISITN; run;

%tfltitle(num=16.2.9.2, type=Listing, text=Listing of Anti-Drug Antibody (ADA) Results,
          pop=Immunogenicity (ADA Evaluable) Population,
          foot=%str(One row per ADA sample. Status = derived from ADIS flags: Baseline+ (ADABLFL), Trt-emergent (TEADAFL), Persistent/Transient (ADAPERFL/ADATRNFL), NAb+ (NABFL). NAb = neutralizing antibody result. Single-/fixed-sequence: period column = APERIODC (Period 1 = reference; subsequent period(s) = test); ordered by participant, fixed period.));
proc report data=ada nowd split='*';
  columns subjid APERIODC &TRTVAR PARAM ('Visit*/ Timepoint' AVISIT ATPT) ADT
          ('ADA*Result' result) ('Titer' titer) ('Baseline' bsln)
          ('ADA*Status' status) ('NAb*Result' nab);
  define subjid  / order 'Participant'   width=12;
  define APERIODC/ order 'Period'    width=10 flow;
  define &TRTVAR / order 'Treatment' width=16 flow;
  define PARAM   / order 'Assay (parameter)' width=20 flow;
  define AVISIT  / display 'Visit' width=12 flow;
  define ATPT    / display 'Timepoint' width=12 flow;
  define ADT     / display 'Date' width=12;
  define result  / display center width=10;
  define titer   / display center width=8;
  define bsln    / display center width=8;
  define status  / display width=18 flow;
  define nab     / display center width=10;
  break after subjid / skip;                   /* group rows by participant        */
run;
