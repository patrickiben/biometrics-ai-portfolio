/******************************************************************************
* TABLE     : t_protocol_deviations  (Multiple Ascending Dose)
* TITLE     : Important Protocol Deviations
* POPULATION: All Enrolled / Randomized Participants
* INPUT     : ADDV (protocol deviation domain) + ADSL (treatment merge)
* NOTE      : PSEUDOCODE. Counts = PARTICIPANTS with >=1 deviation (distinct
*             USUBJID), NOT deviation rows. n (%) per dose level; % denom =
*             enrolled N per dose column. MAD: parallel ascending-dose cohorts,
*             one dose level per participant -> columns = TRT01A (= dose level),
*             with PLACEBO POOLED into a single column (dose_col) and columns
*             ordered by ascending dose. Row hierarchy (3 levels): Any important
*             deviation -> deviation CATEGORY (DVCAT) -> indented TERM (DVDECOD).
*             Dosing-compliance deviations (missed/extra doses, out-of-window PK
*             sampling) are especially relevant because they affect steady-state
*             and accumulation (Rac) PK. Category/term pulled from ADDV
*             (DVCAT/DVDECOD).
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=MAD);               /* -> TRTVAR=TRT01A, TRTNVAR=TRT01AN */

/* Pool placebo into a single dose column (dose_col) and carry an ascending-dose
   sort key (doseord: placebo first, then ascending TRT01AN). Applied to BOTH
   the denominator source (ADSL, enrolled) and the numerator source (ADDV), so
   the pooled "Placebo" column matches across denominator and counts -- mirrors
   the R twin, which pools placebo on adsl (denom) and on the deviation rows.   */
data _adsl;
  set adam.adsl(where=(ENRLFL='Y'));
  length dose_col $200;
  if upcase(&TRTVAR)='PLACEBO' or &TRTNVAR=0 then do; dose_col='Placebo'; doseord=0; end;
  else do; dose_col=&TRTVAR; doseord=&TRTNVAR; end;
run;

%bign(ds=_adsl, trtvar=dose_col, trtn=doseord, popfl=ENRLFL, out=_bign);

/* important deviations only; treatment carried on ADDV from ADSL merge.
   Use IMPDVFL (important deviation flag); pool placebo into dose_col as above.  */
data addv;
  set adam.addv(where=(IMPDVFL='Y'));
  length dose_col $200;
  if upcase(&TRTVAR)='PLACEBO' or &TRTNVAR=0 then do; dose_col='Placebo'; doseord=0; end;
  else do; dose_col=&TRTVAR; doseord=&TRTNVAR; end;
run;

/*--- 1) "Any important deviation" overall row (distinct participants) ---------*/
%aecount(ds=addv, trtvar=dose_col, popden=_bign, where=%str(IMPDVFL='Y'),
         byvars=%str(_dummy), out=_any);      /* _dummy=1 -> overall row     */

/*--- 2) by deviation category (DVCAT), distinct participants within category --*/
%aecount(ds=addv, trtvar=dose_col, popden=_bign, where=%str(IMPDVFL='Y'),
         byvars=%str(DVCAT), out=_cat);

/*--- 3) by category*term (DVCAT*DVDECOD), distinct participants ---------------*/
%aecount(ds=addv, trtvar=dose_col, popden=_bign, where=%str(IMPDVFL='Y'),
         byvars=%str(DVCAT DVDECOD), out=_cattm);

/*--- ordering: category by Total-column participant count desc; term within ---*/
proc sql;
  create table _catord as
    select DVCAT, sum(nsubj) as catn from _cat group by DVCAT;
  create table _tmord as
    select DVCAT, DVDECOD, sum(nsubj) as tmn from _cattm
    group by DVCAT, DVDECOD;
quit;

/*--- assemble report shell: Any -> Category -> indented Term ------------------
   Merge the ordering keys (catn = category Total-column count; tmn = term count)
   back onto each level so category blocks sort by frequency desc and terms sort
   within their category -- the SAS analogue of the R twin's cat_rank/term_rank. */
proc sort data=_cat   ; by DVCAT;          run;
proc sort data=_cattm ; by DVCAT DVDECOD;  run;
proc sort data=_catord; by DVCAT;          run;
proc sort data=_tmord ; by DVCAT DVDECOD;  run;
data _cat;   merge _cat  (in=c) _catord; by DVCAT;          if c; run;
data _cattm; merge _cattm(in=t) _tmord;  by DVCAT DVDECOD;  if t; run;
/* carry the parent category count onto terms so they sort under their category */
proc sql;
  create table _cattm as
    select a.*, b.catn from _cattm a left join _catord b on a.DVCAT=b.DVCAT;
quit;

data _rep;
  set _any(in=a) _cat(in=c) _cattm(in=t);
  length term $200;
  if a then do; term='Participants with any important deviation'; level=0;
                catn=1e12; tmn=1e12; end;   /* overall row sorts first        */
  else if c then do; term=DVCAT;            level=1; tmn=1e12; end;
  else           do; term='   '||DVDECOD;   level=2;            end;
  /* value = catx(' ', put(nsubj,4.), cats('(',put(100*nsubj/N,5.1),'%)'))   */
run;

/* dose_col -> ascending-dose order lookup (placebo=0 first), then transpose to
   pooled dose columns. id = dose_col (placebo pooled); doseord drives column
   order -> Placebo, then ascending dose cohorts, plus Total (matches R twin).  */
proc sql;
  create table _dord as select distinct dose_col, doseord from _adsl;
quit;
proc sort data=_rep ; by dose_col; run;
proc sort data=_dord; by dose_col; run;
data _rep; merge _rep(in=r) _dord; by dose_col; if r; run;
proc sort data=_rep; by catn tmn level term doseord; run;
proc transpose data=_rep out=_wide; by catn tmn level term; id dose_col; var value; run;

%tfltitle(num=14.1.5, type=Table, text=Important Protocol Deviations,
          pop=All Enrolled Participants,
          foot=%str(Column = assigned dose level (TRT01A); placebo pooled, columns ordered by ascending dose. A participant with multiple deviations is counted once at each level. Important deviations per ADDV (IMPDVFL); dosing-compliance and PK-sampling-window deviations affecting steady-state/Rac PK are captured under their DVCAT. Percentages based on enrolled N per dose level.));
proc report data=_wide nowd split='|';
  columns catn tmn level term ("Dose Level" /* dose cols + Total */);
  define catn / order descending noprint;
  define tmn  / order descending noprint;
  define level/ order noprint;
  define term / order 'Deviation Category|  Description' width=44 flow;
run;
