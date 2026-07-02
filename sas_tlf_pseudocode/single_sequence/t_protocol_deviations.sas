/******************************************************************************
* TABLE     : t_protocol_deviations  (Single-/Fixed-Sequence, e.g. DDI)
* TITLE     : Important Protocol Deviations by Category
* POPULATION: All Enrolled Participants (ENRLFL='Y')
* INPUT     : ADDV deviation domain (IMPDVFL/DVCAT); ADSL for sequence + enrolled N
* NOTE      : PSEUDOCODE. Counts = PARTICIPANTS with >=1 deviation (distinct
*             USUBJID), NOT deviation rows. Single-sequence design: ONE column
*             (treatment sequence) + Total; deviations may additionally be
*             flagged by period (APERIOD) where the deviation domain carries
*             it (e.g. dosing-window deviations differ between reference and
*             test periods). % denominator = N enrolled per the chosen
*             population. Deviation categories from the ADaM deviation domain.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=SINGLESEQ);     /* TRTVAR=TRTA, BYPERIOD=APERIOD APERIODC */

%bign(ds=adam.adsl, trtvar=&SEQVAR, trtn=&SEQVARN, popfl=ENRLFL, out=_bign);

/* important deviations only; one record per deviation in ADDV (DVDECOD/DVCAT);
   restrict to ENROLLED participants; sequence label/code merged from ADSL        */
data dv;
  merge adam.addv(in=d where=(IMPDVFL='Y'))   /* important protocol deviations */
        adam.adsl(keep=USUBJID &SEQVAR &SEQVARN ENRLFL where=(ENRLFL='Y') in=s);
  by USUBJID; if d and s;
  length seq $200;
  seq = &SEQVAR;                           /* fixed-sequence label            */
run;

/*--- 1) "Any important deviation" overall row (distinct participants) ---------*/
proc sql;
  create table _any as
    select seq as trt length=200, &SEQVARN as trtn, count(distinct USUBJID) as nsubj
    from dv group by seq, &SEQVARN
  union all
    select 'Total' as trt, 9999 as trtn, count(distinct USUBJID) as nsubj from dv;
quit;
data _any; set _any; length term $200; term='Participants with any important deviation';
  level=0; ord=0;
run;

/*--- 2) by deviation category (distinct participants within category) ---------*/
proc sql;
  create table _cat as
    select seq as trt length=200, &SEQVARN as trtn, DVCAT,
           count(distinct USUBJID) as nsubj
    from dv group by seq, &SEQVARN, DVCAT
  union all
    select 'Total' as trt, 9999 as trtn, DVCAT, count(distinct USUBJID) as nsubj
    from dv group by DVCAT;
quit;
data _cat; set _cat; length term $200; term=DVCAT; level=1; run;

/*--- ordering key: category by Total-column participant count desc ------------*/
proc sql;
  create table _ord as select DVCAT, sum(nsubj) as catn
    from _cat where trt='Total' group by DVCAT;
quit;

/*--- assemble, compute n (%) vs denominator, transpose -------------------*/
data _rep; set _any _cat; run;
proc sql;
  create table _repn as select a.*, b.N, c.catn
    from _rep a left join _bign b on a.trtn=b.trtn
               left join _ord  c on a.DVCAT=c.DVCAT;
quit;
data _repv; set _repn; length value $30;
  if level=0 then catn=1e9;                /* keep the "Any" row on top       */
  value=catx(' ', put(nsubj,4.), cats('(',put(100*nsubj/N,5.1),'%)'));
run;
proc sort data=_repv; by descending catn level term; run;
proc transpose data=_repv out=_wide; by descending catn level term; id trtn; var value; run;

%tfltitle(num=14.1.5, type=Table, text=Important Protocol Deviations by Category,
   pop=All Enrolled Participants,
   foot=%str(A participant is counted once per category. Important deviations only (IMPDVFL=Y); categories from the ADaM deviation domain (DVCAT). Dosing-window and PK-sampling deviations may occur in either the reference (Period 1) or test (Period 2) period. Percentages based on the number of participants enrolled.));
proc report data=_wide nowd split='|';
  columns catn level term ("Treatment Sequence" /* sequence col + Total */);
  define catn  / order descending noprint;
  define level / order noprint;
  define term  / order 'Deviation Category' width=44 flow;
run;
