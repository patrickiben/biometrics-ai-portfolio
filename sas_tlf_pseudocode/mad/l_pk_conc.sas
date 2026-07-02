/******************************************************************************
* LISTING   : l_pk_conc  (MAD - Multiple Ascending Dose)
* TITLE     : Listing of Individual Plasma Drug Concentrations
* POPULATION: PK Concentration Population (PKFL='Y')
* INPUT     : ADPC
* NOTE      : PSEUDOCODE. One row per concentration record, ordered by dose level
*             then participant then study day then nominal/actual time. MAD: repeated
*             daily dosing; column var = TRT01A (= dose level). Each participant
*             contributes samples across multiple dosing days (e.g. full profiles
*             on Day 1 and on the last steady-state day Day N, plus daily pre-dose
*             troughs in between), so the listing shows AVISIT (study day) and the
*             within-interval nominal vs actual time, concentration, and BLQ flag.
*             Listings present all collected samples (not summarized).
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=MAD);                       /* TRTVAR=TRT01A (= dose)     */

data pc;
  set adam.adpc(where=(PKFL='Y'));
  length subjid $20 trt $40 analyte $40 blq $4 vis $20;
  subjid = scan(USUBJID,-1,'-');            /* short site-participant id        */
  trt    = &TRTVAR;                          /* dose level                   */
  analyte= PARAM;                            /* analyte + units              */
  vis    = AVISIT;                           /* study day (Day 1 ... Day N)  */
  ntime  = ATPTN;                            /* nominal time within interval */
  atime  = NRRELTM;                          /* actual relative time (h)     */
  conc   = AVAL;                             /* reported concentration       */
  blq    = ifc(ABLFL='Y','BLQ',' ');         /* below LLOQ flag              */
  keep trt subjid analyte PARAMCD vis AVISITN ADTM ntime atime conc blq AVALC;
run;

proc sort data=pc; by trt subjid PARAMCD AVISITN ntime atime; run;

%tfltitle(num=16.2.11.1, type=Listing,
   text=%str(Listing of Individual Plasma Drug Concentrations),
   pop=Pharmacokinetic Concentration Population,
   foot=%str(BLQ = below the lower limit of quantification (LLOQ). Day = study day of the dosing interval (Day 1 = first dose, Day N = last/steady-state dose). Nominal = protocol-scheduled time within the interval; Actual = recorded sampling time relative to that day's dose. Concentrations as reported by the bioanalytical lab.));
proc report data=pc nowd split='*';
  columns trt subjid analyte vis ('Time (h)' ntime atime) conc blq;
  define trt     / order 'Dose*Level' width=18 flow;
  define subjid  / order 'Participant'   width=12;
  define analyte / order 'Analyte (units)' width=20 flow;
  define vis     / order 'Study*Day' width=12 flow;
  define ntime   / display 'Nominal' center width=8;
  define atime   / display 'Actual'  center width=8;
  define conc    / display 'Concentration' center width=14;
  define blq     / display center width=6;
  break after trt    / page;                 /* one dose level per page block */
  break after subjid / skip;
run;
