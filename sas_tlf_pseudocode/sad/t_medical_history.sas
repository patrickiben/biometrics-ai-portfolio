/******************************************************************************
* TABLE     : t_medical_history  (Single Ascending Dose)
* TITLE     : Medical History
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADMH
* NOTE      : PSEUDOCODE. Counts = PARTICIPANTS with >=1 condition (distinct
*             USUBJID), NOT history rows. n (%) per column; % denom = SAFFL N
*             per column. Summarized by MedDRA SOC (MHBODSYS) and Preferred
*             Term (MHDECOD). SAD: parallel ascending-dose cohorts, ONE
*             treatment per participant; columns = TRT01A = assigned dose level
*             (placebo often pooled across cohorts).
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=SAD);                      /* -> TRTVAR=TRT01A, TRTNVAR=TRT01AN */

%bign(ds=adam.adsl, trtvar=&TRTVAR, trtn=&TRTNVAR, popfl=SAFFL, out=_bign);

/* Safety-population medical-history records; keep ongoing/past per protocol.
   Treatment + SOC/PT carried on ADMH (no re-derivation).                     */
data admh; set adam.admh(where=(SAFFL='Y')); run;

/*--- 1) "Any condition" overall row (distinct participants) -------------------*/
%aecount(ds=admh, trtvar=&TRTVAR, popden=_bign, where=%str(SAFFL='Y'),
         byvars=%str(_dummy), out=_any);       /* _dummy=1 -> overall row     */

/*--- 2) by SOC (distinct participants within SOC) ----------------------------*/
%aecount(ds=admh, trtvar=&TRTVAR, popden=_bign, where=%str(SAFFL='Y'),
         byvars=%str(MHBODSYS), out=_soc);

/*--- 3) by SOC*PT (distinct participants within SOC and PT) ------------------*/
%aecount(ds=admh, trtvar=&TRTVAR, popden=_bign, where=%str(SAFFL='Y'),
         byvars=%str(MHBODSYS MHDECOD), out=_socpt);

/*--- ordering: SOC by Total-column participant count desc; PT within SOC desc -*/
proc sql;
  create table _socord as
    select MHBODSYS, sum(nsubj) as socn from _soc group by MHBODSYS;
  create table _ptord as
    select MHBODSYS, MHDECOD, sum(nsubj) as ptn from _socpt
    group by MHBODSYS, MHDECOD;
quit;

/*--- assemble report shell: Any -> SOC -> indented PT --------------------*/
data _rep;
  set _any(in=a) _soc(in=s) _socpt(in=p);
  length term $200;
  if a then do; term='Participants with any medical history'; level=0; end;
  else if s then do; term=MHBODSYS;       level=1; end;
  else do; term='   '||MHDECOD;           level=2; end;
  /* value = catx(' ', put(nsubj,4.), cats('(',put(100*nsubj/N,5.1),'%)'))    */
run;
proc transpose data=_rep out=_wide; by socn ptn level term; id &TRTNVAR; var value; run;

%tfltitle(num=14.1.7, type=Table, text=Medical History,
          pop=Safety Population,
          foot=%str(A participant is counted once at each level. MedDRA v27.0. Column = assigned dose level (TRT01A); placebo may be pooled. Percentages based on Safety Population N per dose level.));
proc report data=_wide nowd split='|';
  columns socn ptn level term ("Dose Level" /* dose cols + Total */);
  define socn  / order descending noprint;
  define ptn   / order descending noprint;
  define level / order noprint;
  define term  / order 'System Organ Class|  Preferred Term' width=44 flow;
run;
