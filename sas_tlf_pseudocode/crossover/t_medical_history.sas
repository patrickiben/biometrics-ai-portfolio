/******************************************************************************
* TABLE     : t_medical_history  (Crossover - 2x2 or Williams)
* TITLE     : Medical History by System Organ Class and Preferred Term
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADMH
* NOTE      : PSEUDOCODE. Counts = PARTICIPANTS with >=1 condition (distinct
*             USUBJID), NOT history rows. Medical history is collected at
*             screening and is PARTICIPANT-level (fixed before any period), so
*             columns = randomized SEQUENCE (TRTSEQP) + Total -- TRTA is NOT
*             used (would double-count a participant). SOC sorted by overall
*             frequency desc; PT within SOC desc. % denominator = Safety N per
*             sequence (%bign).
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=CROSSOVER);     /* SEQVAR=TRTSEQP                          */

/* participant-level denominators per randomized SEQUENCE + Total                */
%bign(ds=adam.adsl, trtvar=&SEQVAR, trtn=TRTSEQPN, popfl=SAFFL, out=_bign);

/* ADMH with sequence attached; general (ongoing/past) medical history       */
data mh;
  merge adam.admh(in=m where=(SAFFL='Y' and MHCAT='GENERAL MEDICAL HISTORY'))
        adam.adsl(keep=USUBJID &SEQVAR TRTSEQPN);
  by USUBJID; if m;
run;

/*--- counting macro: distinct participants per sequence at a coding level -----*/
%macro mhcount(byvars=, level=, ord0=);
  proc sql;
    create table _mh_&ord0 as
      select &SEQVAR as seq length=200, TRTSEQPN as seqn, %unquote(&byvars),
             count(distinct USUBJID) as nsubj
      from mh group by &SEQVAR, TRTSEQPN, %unquote(&byvars)
    union all
      select 'Total' as seq, 9999 as seqn, %unquote(&byvars),
             count(distinct USUBJID) as nsubj
      from mh group by %unquote(&byvars);
  quit;
  data _mh_&ord0; set _mh_&ord0; length term $200; level=&level;
    %if &level=0 %then %do; term='Participants with any medical history'; %end;
    %else %if &level=1 %then %do; term=MHBODSYS; %end;     /* SOC            */
    %else %do; term='   '||MHDECOD; %end;                  /* preferred term */
  run;
%mend;
%mhcount(byvars=%str(_dummy),           level=0, ord0=0);
%mhcount(byvars=%str(MHBODSYS),         level=1, ord0=1);
%mhcount(byvars=%str(MHBODSYS MHDECOD), level=2, ord0=2);

/*--- ordering: SOC by Total-column participants desc; PT within SOC desc ------*/
proc sql;
  create table _socord as select MHBODSYS, sum(nsubj) as socn from _mh_1
    where seq='Total' group by MHBODSYS;
  create table _ptord  as select MHBODSYS, MHDECOD, sum(nsubj) as ptn from _mh_2
    where seq='Total' group by MHBODSYS, MHDECOD;
quit;

/*--- assemble, attach denominators, format n (%), transpose -------------*/
data _rep0; set _mh_0 _mh_1 _mh_2; run;
proc sql;
  create table _rep as
    select r.*, b.N as denom,
           catx(' ', put(r.nsubj,4.), cats('(',put(100*r.nsubj/b.N,5.1),'%)')) as value length=20
    from _rep0 r left join _bign b on r.seqn=b.trtn;
quit;
/* attach socn/ptn sort keys (merge _socord/_ptord) and order accordingly    */
proc sort data=_rep; by level term; run;
proc transpose data=_rep out=_wide; by level term; id seqn; var value; run;  /* seq cols + Total */

%tfltitle(num=14.1.7, type=Table,
   text=%str(Medical History by System Organ Class and Preferred Term),
   pop=Safety Population,
   foot=%str(A participant is counted once at each level. Columns are randomized treatment sequences (TRTSEQP). Coded with MedDRA v27.0. Percentages based on Safety N per sequence.));
proc report data=_wide nowd split='|';
  columns level term ("Treatment Sequence" _NAME_  /* seq cols + Total */);
  define level / order noprint;
  define term  / order 'System Organ Class / Preferred Term' width=44 flow;
  /* define <each sequence var> / display center "&seqhdr (N=&n)";          */
run;
