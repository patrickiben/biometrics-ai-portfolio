# Deterministic synthetic analysis records; not clinical data or CDISC certification.
analysis_fixture <- function(design = 'parallel', n = 24L) {
  stopifnot(design %in% c('parallel','crossover','single_sequence','sad','mad'), n >= 12L, n %% 4L == 0L)
  multi <- design %in% c('crossover','single_sequence')
  ascending <- design %in% c('sad','mad')
  ids <- sprintf('P%03d', seq_len(n))
  dose <- if (ascending) rep(c(0,10,20,40), length.out=n) else if (multi) rep(10,n) else rep(c(0,10),length.out=n)
  arm <- if (ascending) ifelse(dose==0,'Placebo',paste0('Dose ',dose)) else if (multi) rep('Reference',n) else ifelse(dose==0,'Placebo','Test')
  seq <- if (design=='crossover') rep(c('Reference / Test','Test / Reference'),length.out=n) else if(multi) rep('Reference / Test',n) else arm
  adsl <- data.frame(STUDYID='SYNTHETIC-QC', USUBJID=ids, TRT01A=arm, TRT01AN=match(arm,unique(arm)),
    TRT02A=if(multi) 'Test' else arm, TRTSEQP=seq, TRTSEQPN=match(seq,unique(seq)),
    SAFFL='Y',PKFL=ifelse(dose>0,'Y','N'),PDFL='Y',ITTFL='Y',ADAFL='Y',ISEVALFL='Y',ENRLFL='Y',RANDFL='Y',
    COMPLFL=ifelse(seq_len(n)%%8==0,'N','Y'),DCSFL=ifelse(seq_len(n)%%8==0,'Y','N'),DCSREAS=ifelse(seq_len(n)%%8==0,'Withdrawal by participant',NA_character_),
    COMPDOSF='Y',PKSSFL='Y',COMPP1FL='Y',COMPP2FL='Y',CONFL='Y',DCPERIOD=ifelse(seq_len(n)%%8==0,2,NA),
    AGE=21+seq_len(n),SEX=rep(c('F','M'),length.out=n),RACE=rep(c('Asian','White','Black or African American'),length.out=n),ETHNIC='Not Hispanic or Latino',AGEGR1='18-64',
    HEIGHTBL=160+seq_len(n)%%20,WEIGHTBL=55+seq_len(n),BMIBL=21+seq_len(n)%%8,SBPBL=110+seq_len(n)%%12,DBPBL=65+seq_len(n)%%12,PULSEBL=60+seq_len(n)%%15,
    SYSBPBL=110+seq_len(n)%%12,DIABPBL=65+seq_len(n)%%12,HRBL=60+seq_len(n)%%15,QTCFBL=390+seq_len(n)%%20,
    CRCLBL=90+seq_len(n),EGFRBL=90+seq_len(n),CREATBL=.7+seq_len(n)/100,BSACRBL=.7+seq_len(n)/100,
    SMOKSTAT='Never',ALCOHOL='No',RENALCAT='Normal',DISSEVBL='Not applicable',CHILDPOT='Not applicable',BMICAT='Normal',BMIGR1='Normal',RENALGR1='Normal',RENALGR='Normal',RFGR1='Normal',HEPATGR1='Normal',CYPPHENO='Normal',SITEID='SITE-01',
    RANDDT=as.Date('2026-01-01'),TRTSDT=as.Date('2026-01-02'),TRTEDT=as.Date('2026-01-16'),EOSDT=as.Date('2026-01-17'),EOSSTT='COMPLETED',DTHDT=as.Date(NA),
    RFSTDTC='2026-01-02',RFENDTC='2026-01-17',DCSDTC='',TR01SDTM='2026-01-02T08:00:00',TR02SDTM='2026-01-10T08:00:00',CUMDOSEN=dose*if(design=='mad')14 else 1,
    stringsAsFactors=FALSE)
  periods <- if(multi) 1:2 else 1L
  ex <- expand.grid(USUBJID=ids,APERIOD=periods,stringsAsFactors=FALSE)
  i <- match(ex$USUBJID,ids)
  ex$TRTA <- if(multi) ifelse((if(design=='crossover')i%%2==1 else TRUE)==(ex$APERIOD==1),'Reference','Test') else arm[i]
  ex$TRTAN <- match(ex$TRTA,if(multi)c('Reference','Test')else unique(arm))
  ex$APERIODC <- if(design=='single_sequence')ifelse(ex$APERIOD==1,'Reference','Test')else paste('Period',ex$APERIOD)
  ex$EXDOSE <- dose[i]
  add_common <- function(df) {
    i<-match(df$USUBJID,ids)
    for(k in c('STUDYID','TRT01A','TRT01AN','TRTSEQP','TRTSEQPN','SAFFL','PKFL','ITTFL','PDFL','ADAFL','ISEVALFL'))if(!k%in%names(df))df[[k]]<-adsl[[k]][i]
    if(!'APERIOD'%in%names(df))df$APERIOD<-1L
    if(!'APERIODC'%in%names(df))df$APERIODC<-if(design=='single_sequence')'Reference'else'Period 1'
    if(!'TRTA'%in%names(df))df$TRTA<-adsl$TRT01A[i]
    if(!'TRTAN'%in%names(df))df$TRTAN<-adsl$TRT01AN[i]
    df$APERIODN<-df$APERIOD
    df
  }
  ex<-add_common(ex)
  expand <- function(grid, columns) {grid$.join<-1L;columns$.join<-1L;z<-merge(grid,columns,by='.join',sort=FALSE);z$.join<-NULL;z}
  adex<-expand(ex,data.frame(PARAMCD=c('DURD','TDOSE','NDOSE','DOSINT')))
  adex$PARAM<-c(DURD='Duration',TDOSE='Total dose',NDOSE='Number of doses',DOSINT='Dose intensity')[adex$PARAMCD]
  adex$AVAL<-ifelse(adex$PARAMCD=='DURD',if(design=='mad')14 else 1,ifelse(adex$PARAMCD=='TDOSE',adex$EXDOSE*if(design=='mad')14 else 1,ifelse(adex$PARAMCD=='NDOSE',if(design=='mad')14 else 1,100)))
  adex$EXDOSU<-'mg';adex$EXSTDTC<-'2026-01-02';adex$EXENDTC<-'2026-01-16';adex$EXDUR<-if(design=='mad')14 else 1;adex$EXDOSFRQ<-'QD';adex$TRTDURD<-adex$EXDUR;adex$NDOSES<-adex$EXDUR;adex$EXCMPLPC<-100;adex$EXPLDOS<-adex$EXDOSE;adex$EXADJ<-'N';adex$COMPDOSF<-'Y';adex$PKSSFL<-'Y';adex$ANL01FL<-'Y';adex$WEIGHTBL<-adsl$WEIGHTBL[match(adex$USUBJID,ids)]
  if(ascending||multi)adex<-adex[adex$PARAMCD=='TDOSE',,drop=FALSE]
  time<-expand.grid(ADY=if(design=='mad')c(1,5,7,14)else 1,ATPTN=c(0,1,2,4,8),stringsAsFactors=FALSE)
  time$AVISITN<-time$ADY;time$AVISIT<-paste('Day',time$ADY);time$ATPT<-ifelse(time$ATPTN==0,'Pre-dose',paste(time$ATPTN,'hours'))
  adpc<-expand(ex,time);i<-match(adpc$USUBJID,ids)
  adpc$PARAMCD<-'CONC';adpc$PARAM<-'Plasma concentration';adpc$AVAL<-adpc$EXDOSE*(.2+exp(-adpc$ATPTN/4))*(1+.015*i+.006*sin(i*adpc$ATPTN))*(1+ifelse(adpc$TRTA=='Test',.05,0))*(1+.012*adpc$ADY)*exp(.015*sin(i*adpc$ADY+adpc$ATPTN))
  adpc$AVALC<-ifelse(adpc$AVAL==0,'BLQ','');adpc$AVALU<-'ng/mL';adpc$ANL01FL<-'Y';adpc$ATM<-adpc$ATPTN;adpc$NRRELTM<-adpc$ATPTN;adpc$ARRLT<-adpc$ATPTN;adpc$AFRLT<-adpc$ATPTN;adpc$ARELTM<-adpc$ATPTN;adpc$ADT<-as.Date('2026-01-01')+adpc$ADY;adpc$ADTM<-paste0(adpc$ADT,'T08:00:00');adpc$ABLFL<-'N';adpc$ONTRTFL<-'Y'
  ppgrid<-data.frame(PARAMCD=c('CMAX','AUCLST','AUCIFO','TMAX','T12','CL','VZ','LAMZ','CMAXSS','AUCTAU','TMAXSS','CMINSS','CAVGSS','CLSS'),stringsAsFactors=FALSE)
  adpp<-expand(ex[ex$EXDOSE>0,,drop=FALSE],ppgrid);i<-match(adpp$USUBJID,ids)
  vals<-c(CMAX=10,AUCLST=100,AUCIFO=110,TMAX=2,T12=5,CL=3,VZ=20,LAMZ=.14,CMAXSS=13,AUCTAU=130,TMAXSS=2,CMINSS=4,CAVGSS=8,CLSS=3)
  adpp$AVAL<-unname(vals[adpp$PARAMCD])*(adpp$EXDOSE/10)^(ifelse(adpp$PARAMCD%in%c('TMAX','TMAXSS','T12','CL','VZ','LAMZ'),0,1))*(1+.01*i+.012*sin(i*1.7))*(ifelse(adpp$TRTA=='Test',1.05,1));adpp$AVAL<-adpp$AVAL*exp(.03*sin(i*adpp$APERIOD+1));adpp$PARAM<-adpp$PARAMCD;adpp$AVALC<-'';adpp$AVALU<-'Study units';adpp$ADY<-ifelse(grepl('SS$|TAU$',adpp$PARAMCD),14,1);adpp$AVISITN<-adpp$ADY;adpp$AVISIT<-paste('Day',adpp$ADY);adpp$DTYPE<-'';adpp$ANL01FL<-'Y'
  if(design=='mad'){ss<-adpp[adpp$PARAMCD%in%c('CMAX','AUCLST','AUCIFO'),];ss$AVAL<-ss$AVAL*1.3;ss$ADY<-14;ss$AVISITN<-14;ss$AVISIT<-'Day 14';adpp<-rbind(adpp,ss)}
  pd<-adpc;pd$PARAMCD<-'PDMARK1';pd$PARAM<-'PD biomarker';pd$BASE<-20+.1*match(pd$USUBJID,ids);pd$AVAL<-pd$BASE+pd$AVAL*.2+.05*sin(seq_len(nrow(pd)));pd$CHG<-pd$AVAL-pd$BASE;pd$PCHG<-100*pd$CHG/pd$BASE;pd$AVALU<-'units';pd$PKFL<-NULL
  measure <- function(params,base_values,units) {
    d<-expand(ex,expand(data.frame(PARAMCD=params),time));i<-match(d$USUBJID,ids)
    d$PARAM<-d$PARAMCD;d$BASE<-unname(base_values[d$PARAMCD])+.04*i;d$CHG<-(.5+.1*sin(i+d$ATPTN))*d$EXDOSE/10+.03*d$ATPTN+.01*d$ADY+.04*sin(i*d$ATPTN+d$ADY);d$AVAL<-d$BASE+d$CHG;d$PCHG<-100*d$CHG/d$BASE;d$AVALU<-unname(units[d$PARAMCD]);d$ABLFL<-'N';d$ONTRTFL<-'Y';d$ANL01FL<-'Y';d$ADT<-as.Date('2026-01-01')+d$ADY
    b<-d[d$ADY==1&d$ATPTN==0,,drop=FALSE];b$ADY<--1;b$AVISITN<-0;b$AVISIT<-'Baseline';b$ATPTN<--1;b$ATPT<-'Baseline';b$AVAL<-b$BASE;b$CHG<-0;b$PCHG<-0;b$ABLFL<-'Y';b$ONTRTFL<-'N';b$ADT<-as.Date('2025-12-31');rbind(b,d)
  }
  advs<-measure(c('SYSBP','DIABP','PULSE','TEMP','RESP','WEIGHT'),c(SYSBP=115,DIABP=70,PULSE=65,TEMP=36.5,RESP=16,WEIGHT=70),c(SYSBP='mmHg',DIABP='mmHg',PULSE='beats/min',TEMP='C',RESP='breaths/min',WEIGHT='kg'));advs$ANRLO<-0;advs$ANRHI<-1000;advs$ANRIND<-'NORMAL';advs$A1LO<-advs$ANRLO;advs$A1HI<-advs$ANRHI
  adeg<-measure(c('QTCF','QT','HR','PR','QRS'),c(QTCF=400,QT=390,HR=65,PR=150,QRS=90),c(QTCF='ms',QT='ms',HR='beats/min',PR='ms',QRS='ms'));adeg$ANRIND<-'NORMAL';adeg$EGINTP<-'NORMAL';adeg$ANRLO<-0;adeg$ANRHI<-1000
  adlb<-measure(c('ALT','AST','BILI','ALP','CREAT','K','NA','HGB','WBC','PLAT'),c(ALT=20,AST=22,BILI=.5,ALP=70,CREAT=.8,K=4,'NA'=140,HGB=14,WBC=7,PLAT=240),c(ALT='U/L',AST='U/L',BILI='mg/dL',ALP='U/L',CREAT='mg/dL',K='mmol/L','NA'='mmol/L',HGB='g/dL',WBC='10^9/L',PLAT='10^9/L'))
  adlb$A1LO<-adlb$BASE*.5;adlb$A1HI<-adlb$BASE*1.5;adlb$ANRLO<-adlb$A1LO;adlb$ANRHI<-adlb$A1HI;adlb$R2ULN<-adlb$AVAL/adlb$A1HI;adlb$ANRIND<-ifelse(adlb$AVAL>adlb$A1HI,'HIGH','NORMAL');adlb$BNRIND<-'NORMAL';adlb$ATOXGRN<-ifelse(adlb$ANRIND=='HIGH',1,0);adlb$BTOXGRN<-0;adlb$ATOXGRH<-adlb$ATOXGRN;adlb$ATOXGRL<-0;adlb$ATOXGR<-as.character(adlb$ATOXGRN);adlb$CRIT1FL<-ifelse(adlb$R2ULN>1.5,'Y','N');adlb$ADTC<-as.character(adlb$ADT)
  adae<-ex[seq_len(nrow(ex))%%3==0,,drop=FALSE];i<-match(adae$USUBJID,ids);adae$TRTEMFL<-'Y';adae$AESOC<-'Nervous system disorders';adae$AEDECOD<-ifelse(i%%2==0,'Headache','Dizziness');adae$AESEVN<-1+i%%3;adae$ASEV<-c('MILD','MODERATE','SEVERE')[adae$AESEVN];adae$AREL<-ifelse(i%%2==0,'RELATED','NOT RELATED');adae$AESER<-ifelse(i%%12==0,'Y','N');adae$AESDTH<-'N';adae$AEACN<-ifelse(i%%8==0,'DRUG WITHDRAWN','DOSE NOT CHANGED');adae$AEOUT<-'RECOVERED/RESOLVED';adae$ASTDT<-as.Date('2026-01-03');adae$AENDT<-as.Date('2026-01-04');adae$ASTDY<-2;adae$AENDY<-3;adae$ADURN<-2;for(k in c('AESCONG','AESDISAB','AESHOSP','AESLIFE','AESMIE'))adae[[k]]<-'N'
  adis<-expand(ex,expand.grid(PARAMCD=c('ADA','NAB'),AVISITN=c(0,14),stringsAsFactors=FALSE));i<-match(adis$USUBJID,ids);adis$PARAM<-adis$PARAMCD;adis$PARCAT1<-'ADA';adis$AVISIT<-ifelse(adis$AVISITN==0,'Baseline','Day 14');adis$ADY<-ifelse(adis$AVISITN==0,-1,14);adis$ATPTN<-0;adis$ATPT<-'Pre-dose';adis$ADT<-as.Date('2026-01-01')+adis$ADY;adis$ABLFL<-ifelse(adis$AVISITN==0,'Y','N');adis$BASEADA<-ifelse(i%%7==0,'POSITIVE','NEGATIVE');adis$AVALC<-ifelse(i%%7==0 | (i%%5==0 & adis$AVISITN>0),'POSITIVE','NEGATIVE');adis$AVAL<-ifelse(adis$AVALC=='POSITIVE',40,0);adis$ADATITER<-adis$AVAL;adis$BASE<-ifelse(adis$BASEADA=='POSITIVE',10,0);adis$TEADAFL<-ifelse(i%%5==0 & adis$AVISITN>0,'Y','N');adis$ADAINDFL<-ifelse(adis$TEADAFL=='Y'&adis$BASEADA=='NEGATIVE','Y','N');adis$ADABSTFL<-ifelse(adis$TEADAFL=='Y'&adis$BASEADA=='POSITIVE','Y','N');adis$ADAPERFL<-adis$TEADAFL;adis$ADATRNFL<-'N';adis$NABFL<-ifelse(adis$PARAMCD=='NAB'&adis$AVALC=='POSITIVE','Y','N');adis$NABRES<-adis$AVALC;adis$NABRESC<-adis$AVALC;adis$ADABLFL<-ifelse(adis$BASEADA=='POSITIVE','Y','N');adis$ADAEMFL<-adis$TEADAFL;adis$ADAPOSFL<-ifelse(adis$AVALC=='POSITIVE','Y','N');adis$TRTEMFL<-adis$TEADAFL
  admh<-adsl[seq_len(n)%%4==0,c('USUBJID') ,drop=FALSE];admh<-add_common(admh);admh$MHBODSYS<-'Immune system disorders';admh$MHDECOD<-'Seasonal allergy';admh$MHCAT<-'General';admh$MHOCCUR<-'Y'
  adcm<-ex[seq_len(nrow(ex))%%4==0,,drop=FALSE];adcm$CMCLAS<-'Analgesics';adcm$CMDECOD<-'Paracetamol';adcm$PREFL<-'Y';adcm$ONTRTFL<-'Y';adcm$CONFL<-'Y'
  addv<-ex[seq_len(nrow(ex))%%6==0,,drop=FALSE];addv$DVCAT<-'Procedure';addv$DVDECOD<-'Visit out of window';addv$IMPDVFL<-'Y';addv$ENRLFL<-'Y';addv$RANDFL<-'Y'
  list(adsl=adsl,adae=adae,adcm=adcm,addv=addv,adeg=adeg,adex=adex,adis=adis,adlb=adlb,admh=admh,adpc=adpc,adpd=pd,adpp=adpp,advs=advs)
}

analysis_fixture_settings <- function(design='parallel') {
  list(reference_label='Reference',test_label='Test',placebo_label='Placebo',
    dose_map=if(design%in%c('sad','mad'))c(Placebo=0,'Dose 10'=10,'Dose 20'=20,'Dose 40'=40)else c(Placebo=0,Test=10,Reference=10),
    dose_unit='mg', analysis_day=if(design=='mad')14 else 1,
    profile_days=if(design=='mad')c(1,14)else 1, steady_state_first_day=5,
    pd_parameters='PDMARK1', pd_endpoint='PDMARK1', be_parameters=c('CMAX','AUCLST','AUCIFO'),
    accumulation_day1=1, accumulation_dayn=14)
}
