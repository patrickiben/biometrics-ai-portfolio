/******************************************************************************
* LISTING   : l_pk_conc  (Crossover - 2x2 or Williams)
* TITLE     : Listing of Individual Plasma Concentrations
* POPULATION: PK Concentration Population (PKFL='Y')
* INPUT     : ADPC (AVAL = concentration; ATPT/ATPTN nominal; ARELTM/NRRELTM
*             actual relative time; AVALC carries BLQ tokens)
* NOTE      : PSEUDOCODE. One row per sample. Crossover -> show APERIOD, the
*             treatment received that period (TRTA) and the planned sequence
*             (TRTSEQP) so each participant's period-by-period samples are clear.
*             Ordered by participant, period, nominal time. BLQ shown as the token
*             from AVALC, not a number.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=CROSSOVER);     /* TRTA + APERIOD/APERIODC + TRTSEQP       */

data pc;
  set adam.adpc(where=(PKFL='Y'));
  length subjid $20 seq $12 per $10 trt $40 conc $16 acttm $10 nomtm $10;
  subjid = scan(USUBJID,-1,'-');            /* short site-participant id          */
  seq    = &SEQVAR;                          /* planned sequence e.g. TR / RT  */
  per    = APERIODC;                         /* period label (Period 1/2/...)  */
  trt    = &TRTVAR;                          /* treatment received this period */
  nomtm  = ATPT;                             /* nominal time label             */
  acttm  = ifc(missing(ARELTM),' ',put(ARELTM,8.2));  /* actual rel time (h)   */
  /* show BLQ token where flagged, else formatted numeric concentration       */
  if upcase(AVALC)='BLQ' then conc='BLQ';
  else conc = put(AVAL, 8.3);
  keep subjid seq per APERIOD trt PARAMCD ATPTN nomtm acttm conc;
run;

proc sort data=pc; by subjid APERIOD ATPTN; run;

%tfltitle(num=16.2.10.1, type=Listing,
   text=%str(Listing of Individual Plasma Concentrations),
   pop=Pharmacokinetic Concentration Population,
   foot=%str(BLQ = below limit of quantitation. Period and treatment received shown per crossover design; planned sequence per TRTSEQP. Nominal and actual relative sampling times displayed.));
proc report data=pc nowd split='*';
  columns subjid seq per trt PARAMCD ('Time (h)' nomtm acttm) conc;
  define subjid / order 'Participant'  width=12;
  define seq    / order 'Sequence' width=10;
  define per    / order 'Period'   width=10;
  define trt    / order 'Treatment' width=18 flow;
  define PARAMCD/ order 'Analyte'  width=10;
  define nomtm  / display 'Nominal' center width=8;
  define acttm  / display 'Actual'  center width=8;
  define conc   / display 'Concentration*(unit)' center width=14;
  break after subjid / skip;                 /* one participant block at a time    */
run;
