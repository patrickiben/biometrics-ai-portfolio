/******************************************************************************
* LISTING   : l_ada  (Crossover - 2x2 or Williams)
* TITLE     : Listing of Anti-Drug Antibody (ADA) Results
* POPULATION: Immunogenicity / ADA-Evaluable Population (ISEVALFL='Y')
* INPUT     : ADIS (PARCAT1='ADA'; ADA + NAb assay results, titers, status
*             flags; AVALC; AVISIT/ADT; TRTA, APERIODC, TRTSEQP)
* NOTE      : PSEUDOCODE. Participant-level listing ordered by sequence, participant,
*             treatment PERIOD, treatment, parameter (ADA / NAb / titer),
*             visit/sample date. Shows assay result (Pos/Neg), titer, and the
*             participant-level status flags carried on ADIS. Crossover key:
*             TRTSEQP / APERIODC / TRTA all retained so a reader can see each
*             participant's ADA status under each treatment / period.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=CROSSOVER);     /* SEQVAR=TRTSEQP ; BYPERIOD=APERIOD APERIODC ; TRTVAR=TRTA */

data ada;
  set adam.adis(where=(ISEVALFL='Y' and PARCAT1='ADA'));
  length subjid $20 status $40;
  subjid = scan(USUBJID, -1, '-');           /* short participant id for display  */
  /* compact status string from ADIS flags (no re-derivation):
     baseline pos / treatment-emergent / induced / boosted / persistent /
     transient / NAb positive                                              */
  status = catx('; ',
            ifc(ADABLFL='Y','Baseline+',''),
            ifc(TEADAFL='Y','Trt-emergent',''),
            ifc(ADAPERFL='Y','Persistent',ifc(ADATRNFL='Y','Transient','')),
            ifc(NABFL='Y','NAb+',''));
run;

proc sort data=ada;
  by &SEQVAR USUBJID APERIOD APERIODC &TRTVAR PARAMCD AVISITN ADT;
run;

%tfltitle(num=16.2.9.1, type=Listing,
   text=%str(Listing of Anti-Drug Antibody (ADA) Results),
   pop=Immunogenicity Analysis Population,
   foot=%str(AVALC = assay result (Positive/Negative); titer where applicable. Status = participant-level immunogenicity flags from ADIS (treatment-emergent = induced or boosted). Ordered by sequence, participant, treatment period.));
proc report data=ada nowd split='|';
  columns &SEQVAR subjid APERIODC &TRTVAR PARAM AVISIT ADT
          AVALC AVAL status;
  define &SEQVAR / order 'Sequence'        width=10;
  define subjid  / order 'Participant'         width=10;
  define APERIODC/ order 'Period'          width=10;
  define &TRTVAR / order 'Treatment'       width=16;
  define PARAM   / order 'Assay/Parameter' width=22;
  define AVISIT  / order 'Visit'           width=14;
  define ADT     / display 'Sample Date'   width=11;
  define AVALC   / display 'Result'        width=10;
  define AVAL    / display 'Titer'         width=9;
  define status  / display 'ADA Status'    width=26 flow;
run;
