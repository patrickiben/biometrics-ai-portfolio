/******************************************************************************
* LISTING   : l_pk_param  (Single-/fixed-sequence - e.g. DDI)
* TITLE     : Listing of Individual PK Parameters
* POPULATION: PK Parameter Population (PKFL='Y')
* INPUT     : ADPP (PARAMCD = CMAX, TMAX, AUCLST, AUCIFO, T12, CLFO, VZFO, ...)
*             CLFO = oral clearance CL/F; VZFO = oral volume Vz/F (extravascular)
* NOTE      : PSEUDOCODE. One row per participant x period (one set of parameters
*             per dosing period). Single-/fixed-sequence -> show APERIOD/
*             APERIODC (Reference vs Test) and the treatment given that period
*             (TRTA). There is NO randomized sequence column; the fixed period
*             order makes the within-participant Reference->Test structure explicit.
*             Parameters pivoted to columns; ordered by participant then period.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=SINGLESEQ);     /* TRTA + APERIOD/APERIODC; SEQVAR empty     */

data pp;
  set adam.adpp(where=(PKFL='Y'));
  length subjid $20 per $24 trt $40 cval $16;
  subjid = scan(USUBJID,-1,'-');
  per    = APERIODC;                         /* period label (Reference/Test)   */
  trt    = &TRTVAR;                          /* treatment given this period     */
  cval   = ifc(missing(AVAL),'NC',put(AVAL,8.3));   /* NC = not calculable      */
  keep subjid per APERIOD trt PARAMCD cval;
run;

/*--- pivot parameters to columns: one row per participant x period ----------*/
proc sort data=pp; by subjid APERIOD per trt; run;
proc transpose data=pp out=_w(drop=_name_);
  by subjid APERIOD per trt; id PARAMCD; var cval;   /* CMAX TMAX AUCLST ...   */
run;
proc sort data=_w; by subjid APERIOD; run;

%tfltitle(num=16.2.10.2, type=Listing,
   text=%str(Listing of Individual Pharmacokinetic Parameters),
   pop=Pharmacokinetic Parameter Population,
   foot=%str(One row per participant and dosing period. NC = not calculable. Period and treatment given shown per single-/fixed-sequence design; period order is fixed for all participants (no randomized sequence). Units per parameter header.));
proc report data=_w nowd split='*';
  columns subjid per trt CMAX TMAX AUCLST AUCIFO T12 CLFO VZFO;
  define subjid / order 'Participant'  width=12;
  define per    / order 'Period'   width=16 flow;
  define trt    / display 'Treatment' width=16 flow;
  define CMAX   / display 'Cmax*(unit)'    center width=10;
  define TMAX   / display 'Tmax*(h)'       center width=8;
  define AUCLST / display 'AUClast*(unit)' center width=12;
  define AUCIFO / display 'AUCinf*(unit)'  center width=12;
  define T12    / display 't1/2*(h)'       center width=8;
  define CLFO   / display 'CL/F*(unit)'    center width=10;
  define VZFO   / display 'Vz/F*(unit)'    center width=10;
  break after subjid / skip;
run;
