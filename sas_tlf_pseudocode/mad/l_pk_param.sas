/******************************************************************************
* LISTING   : l_pk_param  (MAD - Multiple Ascending Dose)
* TITLE     : Listing of Individual Plasma PK Parameters
* POPULATION: PK Parameter Population (PKFL='Y')
* INPUT     : ADPP (PARAMCD = day-1: CMAX TMAX AUCLST AUCIFO T12 CLFO VZFO ;
*             steady-state day-N: CMAXSS TMAXSS AUCTAU CMINSS CTROUGH CAVGSS CLSS ;
*             accumulation: RACMAX RACAUC ; AVISIT/AVISITN = study day)
* NOTE      : PSEUDOCODE. One row per participant per study day (parameters across
*             columns), ordered by dose level then participant then day. MAD: repeated
*             dosing; column var = TRT01A (= dose level). Day 1 carries the
*             single-dose NCA parameters; Day N carries the steady-state set; the
*             accumulation ratios Rac (steady-state vs Day 1) are listed on the
*             Day-N row. Non-estimable parameters (BLQ-driven) shown as NE/blank
*             per AVALC. Listings present individual derived NCA parameters as
*             computed in ADPP.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=MAD);                       /* TRTVAR=TRT01A (= dose)     */

data pp;
  set adam.adpp(where=(PKFL='Y'));
  length subjid $20 trt $40 vis $20;
  subjid = scan(USUBJID,-1,'-');             /* short site-participant id        */
  trt    = &TRTVAR;                           /* dose level                   */
  vis    = AVISIT;                            /* study day (Day 1 ... Day N)  */
  /* AVALC carries 'NE' for non-estimable; AVAL = numeric value              */
  keep trt &TRTNVAR subjid vis AVISITN PARAMCD PARAM AVAL AVALC;
run;

/*--- one row per participant per study day; parameters become columns --------*/
proc sort data=pp; by trt &TRTNVAR subjid AVISITN vis PARAMCD; run;
proc transpose data=pp out=_wide(drop=_name_);
  by trt &TRTNVAR subjid AVISITN vis;
  id PARAMCD;     /* CMAX TMAX AUCLST AUCIFO CMAXSS AUCTAU CMINSS CTROUGH ... */
  var AVAL;                                   /* (NE values carried via AVALC)*/
run;

%tfltitle(num=16.2.11.2, type=Listing,
   text=%str(Listing of Individual Plasma Pharmacokinetic Parameters),
   pop=Pharmacokinetic Parameter Population,
   foot=%str(NE = not estimable. Day = study day of the derived parameter (Day 1 = single-dose NCA; Day N = steady-state NCA). Rac = accumulation ratio (steady-state vs Day 1), listed on the Day-N row. Parameters derived by non-compartmental analysis in ADPP. Tmax in hours; exposure in concentration*time units; CL/Vz in volume(/time) units.));
proc report data=_wide nowd split='*';
  columns trt subjid vis CMAX TMAX AUCLST AUCIFO T12 CLFO VZFO
          CMAXSS TMAXSS AUCTAU CMINSS CTROUGH CAVGSS CLSS RACMAX RACAUC;
  define trt     / order 'Dose*Level' width=16 flow;
  define subjid  / order 'Participant' width=10;
  define vis     / order 'Study*Day' width=8;
  define CMAX    / display 'Cmax'      center width=8;
  define TMAX    / display 'Tmax (h)'  center width=8;
  define AUCLST  / display 'AUClast'   center width=9;
  define AUCIFO  / display 'AUCinf'    center width=9;
  define T12     / display 't1/2 (h)'  center width=8;
  define CLFO    / display 'CL/F'      center width=8;
  define VZFO    / display 'Vz/F'      center width=8;
  define CMAXSS  / display 'Cmax,ss'   center width=8;
  define TMAXSS  / display 'Tmax,ss'   center width=8;
  define AUCTAU  / display 'AUCtau'    center width=9;
  define CMINSS  / display 'Cmin,ss'   center width=8;
  define CTROUGH / display 'Ctrough'   center width=8;
  define CAVGSS  / display 'Cavg,ss'   center width=8;
  define CLSS    / display 'CL,ss/F'   center width=8;
  define RACMAX  / display 'Rac*(Cmax)' center width=8;
  define RACAUC  / display 'Rac*(AUC)'  center width=8;
  break after trt / page;                     /* one dose level per page block */
  break after subjid / skip;
run;
