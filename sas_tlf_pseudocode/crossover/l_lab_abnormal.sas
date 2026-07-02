/******************************************************************************
* LISTING   : l_lab_abnormal  (Crossover - 2x2 or Williams)
* TITLE     : Listing of Abnormal Laboratory Values
* POPULATION: Safety Population (SAFFL='Y'), on-treatment records (ONTRTFL='Y')
* INPUT     : ADLB (PARAM/PARAMCD, AVAL, BASE, CHG, ANRIND, A1LO/A1HI, ATOXGRN,
*             AVISIT/AVISITN, ADT/ADY, TRTA/TRTAN, APERIOD/APERIODC, TRTSEQP, ONTRTFL)
* NOTE      : PSEUDOCODE. One row per abnormal laboratory record, ordered by
*             sequence, participant, treatment period and collection day. Within-
*             participant crossover -> show TRTSEQP (sequence), APERIODC (period)
*             and TRTA (analysis treatment) so each record is anchored to the
*             period in which it occurred. Abnormal = ANRIND in (LOW,HIGH) or a
*             CTCAE toxicity grade >= 1 (ATOXGRN); on-treatment scope ONTRTFL='Y'.
*             Reference range and flag shown.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=CROSSOVER);     /* TRTVAR=TRTA TRTNVAR=TRTAN BYPERIOD=APERIOD APERIODC SEQVAR=TRTSEQP */

data lb;
  set adam.adlb(where=(SAFFL='Y' and ONTRTFL='Y'
                       and (upcase(ANRIND) in ('LOW','HIGH') or ATOXGRN>=1)));
  length subjid $20 seq $12 per $12 trt $40 flag $6 rng $24 grade $6;
  subjid = scan(USUBJID,-1,'-');            /* short site-participant id          */
  seq    = &SEQVAR;                          /* randomized sequence (TRTSEQP)  */
  per    = APERIODC;                         /* treatment period label         */
  trt    = &TRTVAR;                          /* analysis treatment (TRTA)      */
  flag   = ifc(upcase(ANRIND)='HIGH','High',ifc(upcase(ANRIND)='LOW','Low',' '));
  grade  = ifc(missing(ATOXGRN),' ',put(ATOXGRN,1.)); /* CTCAE toxicity grade   */
  rng    = catx(' - ', put(A1LO,best8.), put(A1HI,best8.));  /* reference range */
  colday = ifc(missing(ADY),' ',put(ADY,4.));               /* study day      */
  keep seq subjid per trt PARAM AVISIT colday AVAL BASE CHG rng flag grade
       APERIOD ADY;                          /* numeric period/day sort keys   */
run;

/* sort by sequence, participant, period, parameter, day - period anchors the row;
   sort on numeric APERIOD/ADY (not the character labels) so multi-digit days order right */
proc sort data=lb; by seq subjid APERIOD PARAM ADY; run;

%tfltitle(num=16.2.8.2, type=Listing, text=Listing of Abnormal Laboratory Values,
          pop=Safety Population,
          foot=%str(Abnormal = normal-range indicator Low/High (ANRIND) or a CTCAE toxicity grade >= 1 (ATOXGRN); on-treatment records (ONTRTFL=Y). Sequence = randomized treatment order (TRTSEQP); Period = treatment period; Treatment = analysis treatment in that period (crossover). Reference range = A1LO - A1HI. SI units. Source: ADLB.));
proc report data=lb nowd split='*';
  columns seq subjid per trt ('Laboratory*Parameter' PARAM) AVISIT colday
          ('Value' AVAL) ('Baseline' BASE) ('Change' CHG)
          ('Reference*Range' rng) ('Flag' flag) ('Grade' grade);
  define seq    / order 'Sequence' width=10;
  define subjid / order 'Participant'  width=12;
  define per    / order 'Period'   width=10;
  define trt    / order 'Treatment' width=16 flow;
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
