/******************************************************************************
* LISTING   : l_pk_param  (Crossover - 2x2 or Williams)
* TITLE     : Listing of Individual PK Parameters
* POPULATION: PK Parameter Population (PKFL='Y')
* INPUT     : ADPP (PARAMCD = CMAX, TMAX, AUCLST, AUCIFO, T12, CL, VZ, ...)
* NOTE      : PSEUDOCODE. One row per participant x period (one set of parameters
*             per dosing period). Crossover -> show APERIOD, treatment received
*             (TRTA) and planned sequence (TRTSEQP) so the within-participant
*             period structure is explicit. Parameters pivoted to columns;
*             ordered by participant then period.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=CROSSOVER);     /* TRTA + APERIOD/APERIODC + TRTSEQP        */

data pp;
  set adam.adpp(where=(PKFL='Y'));
  length subjid $20 seq $12 per $10 trt $40 cval $16;
  subjid = scan(USUBJID,-1,'-');
  seq    = &SEQVAR;                          /* planned sequence (TR / RT)      */
  per    = APERIODC;                         /* period label                    */
  trt    = &TRTVAR;                          /* treatment received this period  */
  cval   = ifc(missing(AVAL),'NC',put(AVAL,8.3));   /* NC = not calculable      */
  keep subjid seq per APERIOD trt PARAMCD cval;
run;

/*--- pivot parameters to columns: one row per participant x period ----------*/
proc sort data=pp; by subjid APERIOD seq per trt; run;
proc transpose data=pp out=_w(drop=_name_);
  by subjid APERIOD seq per trt; id PARAMCD; var cval;   /* CMAX TMAX AUCLST...*/
run;
proc sort data=_w; by subjid APERIOD; run;

%tfltitle(num=16.2.10.2, type=Listing,
   text=%str(Listing of Individual Pharmacokinetic Parameters),
   pop=Pharmacokinetic Parameter Population,
   foot=%str(One row per participant and dosing period. NC = not calculable. Period and treatment received shown per crossover design; planned sequence per TRTSEQP. Units per parameter header.));
proc report data=_w nowd split='*';
  columns subjid seq per trt CMAX TMAX AUCLST AUCIFO T12 CL VZ;
  define subjid / order 'Participant'  width=12;
  define seq    / order 'Sequence' width=10;
  define per    / order 'Period'   width=10;
  define trt    / display 'Treatment' width=16 flow;
  define CMAX   / display 'Cmax*(unit)'    center width=10;
  define TMAX   / display 'Tmax*(h)'       center width=8;
  define AUCLST / display 'AUClast*(unit)' center width=12;
  define AUCIFO / display 'AUCinf*(unit)'  center width=12;
  define T12    / display 't1/2*(h)'       center width=8;
  define CL     / display 'CL/F*(unit)'    center width=10;
  define VZ     / display 'Vz/F*(unit)'    center width=10;
  break after subjid / skip;
run;
