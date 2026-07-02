/******************************************************************************
* TABLE     : t_medical_history  (Single-/Fixed-Sequence, e.g. DDI)
* TITLE     : Medical History by System Organ Class and Preferred Term
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADMH
* NOTE      : PSEUDOCODE. Counts = PARTICIPANTS with >=1 condition (distinct
*             USUBJID), NOT condition rows. Single-sequence design: medical
*             history is a pre-treatment, participant-level characteristic shared
*             across both periods, so it is summarized in ONE column (treatment
*             sequence) + Total (NOT by period). SOC sorted by overall
*             frequency desc; PT within SOC desc. % denominator = Safety N.
*             MedDRA SOC (MHBODSYS) and preferred term (MHDECOD) from ADMH.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=SINGLESEQ);     /* TRTVAR=TRTA, TRTNVAR=TRTAN, SEQVAR=    */

%bign(ds=adam.adsl, trtvar=&SEQVAR, trtn=&SEQVARN, popfl=SAFFL, out=_bign);

/* ongoing/past medical history (general history flag); sequence from ADSL --*/
data mh;
  merge adam.admh(in=m where=(SAFFL='Y' and MHCAT='GENERAL MEDICAL HISTORY'))
        adam.adsl(keep=USUBJID &SEQVAR &SEQVARN);
  by USUBJID; if m;
  length seq $200; seq = &SEQVAR;
run;

/*--- 1) any medical history condition, distinct participants -----------------*/
proc sql;
  create table _any as
    select seq as trt length=200, &SEQVARN as trtn, count(distinct USUBJID) as nsubj
    from mh group by seq, &SEQVARN
  union all
    select 'Total' as trt, 9999 as trtn, count(distinct USUBJID) as nsubj from mh;
quit;
data _any; set _any; length term $200; term='Participants with any medical history';
  level=0; run;

/*--- 2) by SOC (distinct participants within SOC) ----------------------------*/
proc sql;
  create table _soc as
    select seq as trt length=200, &SEQVARN as trtn, MHBODSYS,
           count(distinct USUBJID) as nsubj
    from mh group by seq, &SEQVARN, MHBODSYS
  union all
    select 'Total' as trt, 9999 as trtn, MHBODSYS, count(distinct USUBJID) as nsubj
    from mh group by MHBODSYS;
quit;
data _soc; set _soc; length term $200; term=MHBODSYS; level=1; run;

/*--- 3) by SOC*preferred term (distinct participants) ------------------------*/
proc sql;
  create table _pt as
    select seq as trt length=200, &SEQVARN as trtn, MHBODSYS, MHDECOD,
           count(distinct USUBJID) as nsubj
    from mh group by seq, &SEQVARN, MHBODSYS, MHDECOD
  union all
    select 'Total' as trt, 9999 as trtn, MHBODSYS, MHDECOD,
           count(distinct USUBJID) as nsubj
    from mh group by MHBODSYS, MHDECOD;
quit;
data _pt; set _pt; length term $200; term='   '||strip(MHDECOD); level=2; run;

/*--- ordering: SOC by Total-column count desc; PT within SOC desc ---------*/
proc sql;
  create table _socord as select MHBODSYS, sum(nsubj) as socn from _soc
    where trtn=9999 group by MHBODSYS;
  create table _ptord as select MHBODSYS, MHDECOD, sum(nsubj) as ptn from _pt
    where trtn=9999 group by MHBODSYS, MHDECOD;
quit;

/*--- assemble, n (%) vs Safety N, transpose to sequence column + Total -----*/
data _rep; set _any _soc _pt; run;
proc sql;
  create table _repn as select a.*, b.N from _rep a left join _bign b on a.trtn=b.trtn;
quit;
data _repv; set _repn; length value $30;
  value=catx(' ', put(nsubj,4.), cats('(',put(100*nsubj/N,5.1),'%)'));
run;
/* merge socn/ptn sort keys, indent PT under SOC, sort by socn/ptn desc, then: */
proc sort data=_repv; by level term; run;
proc transpose data=_repv out=_wide; by level term; id trtn; var value; run;

%tfltitle(num=14.1.7, type=Table,
   text=%str(Medical History by System Organ Class and Preferred Term),
   pop=Safety Population,
   foot=%str(A participant is counted once at each level. Medical history is a pre-treatment characteristic shared across both periods. SOC ordered by overall frequency; PT within SOC. MedDRA v27.0. Percentages based on Safety Population N.));
proc report data=_wide nowd split='|';
  columns level term ("Treatment Sequence" /* sequence col + Total */);
  define level / order noprint;
  define term  / order 'System Organ Class|  Preferred Term' width=44 flow;
run;
