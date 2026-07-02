/******************************************************************************
* LISTING   : l_pk_param  (Parallel-group)
* TITLE     : Listing of Individual Plasma PK Parameters
* POPULATION: PK Parameter Population (PKFL='Y')
* INPUT     : ADPP (PARAMCD = CMAX, TMAX, AUCLST, AUCIFO, T12, CL, VZ, LAMZ, ...)
* NOTE      : PSEUDOCODE. One row per participant (parameters across columns),
*             ordered by treatment then participant. Parallel-group: one treatment
*             per participant, column var = TRT01A (= dose level). Non-estimable
*             parameters (BLQ-driven) shown as NE/blank per AVALC. Listings
*             present individual derived NCA parameters as computed in ADPP.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=PARALLEL);                 /* TRTVAR=TRT01A              */

data pp;
  set adam.adpp(where=(PKFL='Y'));
  length subjid $20 trt $40;
  subjid = scan(USUBJID,-1,'-');             /* short site-participant id        */
  trt    = &TRTVAR;                           /* treatment (= dose level)     */
  /* AVALC carries 'NE' for non-estimable; AVAL = numeric value              */
  keep trt &TRTNVAR subjid PARAMCD PARAM AVAL AVALC;
run;

/*--- one row per participant; parameters become columns ----------------------*/
proc sort data=pp; by trt &TRTNVAR subjid PARAMCD; run;
proc transpose data=pp out=_wide(drop=_name_);
  by trt &TRTNVAR subjid;
  id PARAMCD;                                 /* CMAX TMAX AUCLST AUCIFO ...  */
  var AVAL;                                   /* (NE values carried via AVALC)*/
run;

%tfltitle(num=16.2.11.2, type=Listing,
   text=%str(Listing of Individual Plasma Pharmacokinetic Parameters),
   pop=Pharmacokinetic Parameter Population,
   foot=%str(NE = not estimable. Parameters as derived by non-compartmental analysis in ADPP. Tmax in hours; exposure in concentration*time units; CL/Vz in volume(/time) units.));
proc report data=_wide nowd split='*';
  columns trt subjid CMAX TMAX AUCLST AUCIFO T12 CL VZ;
  define trt    / order 'Treatment*(Dose)' width=18 flow;
  define subjid / order 'Participant' width=12;
  define CMAX   / display 'Cmax'    center width=10;
  define TMAX   / display 'Tmax (h)' center width=8;
  define AUCLST / display 'AUClast' center width=10;
  define AUCIFO / display 'AUCinf'  center width=10;
  define T12    / display 't1/2 (h)' center width=8;
  define CL     / display 'CL/F'    center width=8;
  define VZ     / display 'Vz/F'    center width=8;
  break after trt / page;                     /* one treatment per page block */
run;
