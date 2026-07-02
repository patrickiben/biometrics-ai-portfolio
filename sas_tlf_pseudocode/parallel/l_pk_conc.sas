/******************************************************************************
* LISTING   : l_pk_conc  (Parallel-group)
* TITLE     : Listing of Individual Plasma Drug Concentrations
* POPULATION: PK Concentration Population (PKFL='Y')
* INPUT     : ADPC
* NOTE      : PSEUDOCODE. One row per concentration record, ordered by
*             treatment then participant then nominal/actual time. Parallel-group:
*             one treatment per participant, column var = TRT01A (= dose level).
*             Shows nominal vs actual relative time, concentration, and BLQ
*             flag. Listings present all collected samples (not summarized).
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=PARALLEL);                 /* TRTVAR=TRT01A              */

data pc;
  set adam.adpc(where=(PKFL='Y'));
  length subjid $20 trt $40 analyte $40 blq $4 vis $20;
  subjid = scan(USUBJID,-1,'-');            /* short site-participant id        */
  trt    = &TRTVAR;                          /* treatment (= dose level)     */
  analyte= PARAM;                            /* analyte + units              */
  vis    = AVISIT;                           /* scheduled visit / day        */
  ntime  = ATPTN;                            /* nominal relative time (h)    */
  atime  = NRRELTM;                          /* actual relative time (h)     */
  conc   = AVAL;                             /* reported concentration       */
  blq    = ifc(ABLFL='Y','BLQ',' ');         /* below LLOQ flag              */
  keep trt subjid analyte PARAMCD vis ADTM ntime atime conc blq AVALC;
run;

proc sort data=pc; by trt subjid PARAMCD ntime atime; run;

%tfltitle(num=16.2.11.1, type=Listing,
   text=%str(Listing of Individual Plasma Drug Concentrations),
   pop=Pharmacokinetic Concentration Population,
   foot=%str(BLQ = below the lower limit of quantification (LLOQ). Nominal = protocol-scheduled time; Actual = recorded sampling time relative to dose. Concentrations as reported by the bioanalytical lab.));
proc report data=pc nowd split='*';
  columns trt subjid analyte vis ('Time (h)' ntime atime) conc blq;
  define trt     / order 'Treatment*(Dose)' width=18 flow;
  define subjid  / order 'Participant'   width=12;
  define analyte / order 'Analyte (units)' width=20 flow;
  define vis     / display 'Visit'   width=14 flow;
  define ntime   / display 'Nominal' center width=8;
  define atime   / display 'Actual'  center width=8;
  define conc    / display 'Concentration' center width=14;
  define blq     / display center width=6;
  break after trt    / page;                 /* one treatment per page block */
  break after subjid / skip;
run;
