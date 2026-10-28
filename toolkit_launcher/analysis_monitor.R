# Deterministic operational/screening checks on canonical study inputs.
# Reports thresholds and counts only; no clinical decisions, routing or messages.
analysis_monitor <- function(check, build, cfg) {
  schema <- list(
    liver=c("USUBJID","alt_x","ast_x","tbl_x","alp_x"),
    qtcf=c("USUBJID","QTCF","DQTCF"),
    ae=c("USUBJID","COHORT","AESER","AETOXGR","TRTEMFL"),
    dlt=c("USUBJID","COHORT","DLT_EVAL","DLTFL"),
    enrollment=c("N_ENROLLED","N_PLANNED_TO_DATE"),
    queries=c("OPEN_FL","QUERY_AGE_DAYS"),
    visits=c("USUBJID","VISIT","ACTDT","PLANDT","WINDOW_DAYS"),
    clinical=c("USUBJID","TRT01P"),randomization=c("USUBJID","IXRS_TRT"))
  read_input <- function(slot, numeric=character(), dates=character()) {
    x <- utils::read.csv(file.path(build,"inputs",paste0(slot,".csv")),colClasses="character",check.names=FALSE,na.strings="",fileEncoding="UTF-8")
    if(!nrow(x)) stop(paste("Required feed",slot,"has no records."))
    if(anyDuplicated(names(x))||!all(schema[[slot]]%in%names(x)))stop(paste(slot,"needs the canonical required columns, without duplicate headers."))
    for(key in setdiff(schema[[slot]],"ACTDT"))
      if(any(is.na(x[[key]])|!nzchar(trimws(x[[key]]))))stop(paste(slot,key,"has a missing required value."))
    for(key in intersect(c("AESER","TRTEMFL","DLT_EVAL","DLTFL","OPEN_FL"),names(x)))
      if(any(!x[[key]]%in%c("Y","N")))stop(paste(slot,key,"must contain canonical Y or N flags; unknown is not No."))
    for(key in numeric) {
      x[[key]] <- suppressWarnings(as.numeric(x[[key]]))
      if(any(!is.finite(x[[key]]))) stop(paste(slot,key,"needs finite numeric values."))
    }
    for(key in dates) {
      raw<-x[[key]]; parsed<-as.Date(raw,format="%Y-%m-%d")
      invalid<-!is.na(raw)&(!grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$",raw)|is.na(parsed)|format(parsed,"%Y-%m-%d")!=raw)
      if(any(invalid))stop(paste(slot,key,"needs valid YYYY-MM-DD dates; only an absent actual visit date may be blank."))
      x[[key]]<-parsed
    }
    keys<-if(slot%in%c("liver","qtcf","clinical","randomization"))"USUBJID" else if(slot=="dlt")c("USUBJID","COHORT")else character()
    if(length(keys)&&anyDuplicated(x[keys]))stop(paste(slot,"has duplicate participant analysis keys."))
    x
  }
  config_number<-function(name, minimum=-Inf, maximum=Inf) {
    value<-suppressWarnings(as.numeric(cfg[[name]]))
    if(length(value)!=1L||!is.finite(value)||value<minimum||value>maximum)stop(paste("Invalid configured",name,"threshold."))
    value
  }
  if(check=="liver") {
    d <- read_input("liver",c("alt_x","ast_x","tbl_x","alp_x"))
    if(any(d[c("alt_x","ast_x","tbl_x","alp_x")]<=0))stop("Liver multiples of reference limits must be positive.")
    cfg$alt_threshold<-config_number("alt_threshold",0);cfg$ast_threshold<-config_number("ast_threshold",0);cfg$bilirubin_threshold<-config_number("bilirubin_threshold",0)
    d$alt_threshold<-cfg$alt_threshold;d$ast_threshold<-cfg$ast_threshold;d$bilirubin_threshold<-cfg$bilirubin_threshold
    d$flagged <- (d$alt_x>=cfg$alt_threshold | d$ast_x>=cfg$ast_threshold) & d$tbl_x>cfg$bilirubin_threshold
    d$r_ratio <- d$alt_x/d$alp_x
    d$screen <- ifelse(d$flagged,"Threshold combination met; clinical review required","Threshold combination not met")
    d$severity <- ifelse(d$flagged,"RED","NO FLAG")
    d
  } else if(check=="qtcf") {
    d <- read_input("qtcf",c("QTCF","DQTCF"))
    for(key in c("qtcf_amber","qtcf_red","delta_amber","delta_red"))cfg[[key]]<-config_number(key,0)
    if(cfg$qtcf_amber>=cfg$qtcf_red||cfg$delta_amber>=cfg$delta_red)stop("Red QTcF thresholds must exceed amber thresholds.")
    d$severity <- ifelse(d$QTCF>cfg$qtcf_red | d$DQTCF>cfg$delta_red,"RED",ifelse(d$QTCF>cfg$qtcf_amber | d$DQTCF>cfg$delta_amber,"AMBER","NO FLAG"))
    d$absolute_amber_ms <- cfg$qtcf_amber; d$absolute_red_ms <- cfg$qtcf_red
    d$change_amber_ms <- cfg$delta_amber; d$change_red_ms <- cfg$delta_red
    d
  } else if(check=="ae") {
    d <- read_input("ae","AETOXGR")
    if(any(d$AETOXGR<0|d$AETOXGR>5|d$AETOXGR!=floor(d$AETOXGR)))stop("AE toxicity grades must be integers from zero through five.")
    do.call(rbind,lapply(sort(unique(d$COHORT)),function(cohort) {
      x <- d[d$COHORT==cohort & d$TRTEMFL=="Y",,drop=FALSE]
      sae <- x$AESER=="Y"; severe <- x$AETOXGR>=3
      data.frame(COHORT=cohort,n_sae_participants=length(unique(x$USUBJID[sae])),n_sae_events=sum(sae),n_grade3_participants=length(unique(x$USUBJID[severe])),n_ae_participants=length(unique(x$USUBJID)),severity=if(any(sae|severe)) "AMBER" else "NO FLAG",stringsAsFactors=FALSE)
    }))
  } else if(check=="dlt") {
    d <- read_input("dlt")
    do.call(rbind,lapply(sort(unique(d$COHORT)),function(cohort) {
      x <- d[d$COHORT==cohort,,drop=FALSE]
      n_eval <- sum(x$DLT_EVAL=="Y"); n_dlt <- sum(x$DLT_EVAL=="Y" & x$DLTFL=="Y")
      if(!n_eval) stop(paste("No completed evaluable DLT window for",cohort))
      data.frame(COHORT=cohort,n_evaluable=n_eval,n_dlt=n_dlt,n_pending=sum(x$DLT_EVAL!="Y"),n_pending_dlt_flags=sum(x$DLT_EVAL=="N" & x$DLTFL=="Y"),severity=if(n_dlt>=2) "RED" else if(n_dlt==1) "AMBER" else "NO FLAG",interpretation="Adjudicated count only; no escalation decision",stringsAsFactors=FALSE)
    }))
  } else if(check=="enrollment") {
    d <- read_input("enrollment",c("N_ENROLLED","N_PLANNED_TO_DATE"))
    if(any(d$N_ENROLLED<0|d$N_ENROLLED!=floor(d$N_ENROLLED)|d$N_PLANNED_TO_DATE!=floor(d$N_PLANNED_TO_DATE)))stop("Enrollment counts must be nonnegative integers.")
    cfg$enrollment_ratio<-config_number("enrollment_ratio",0)
    if(any(d$N_PLANNED_TO_DATE<=0)) stop("Planned enrollment denominator must be positive.")
    d$ratio <- d$N_ENROLLED/d$N_PLANNED_TO_DATE; d$threshold <- cfg$enrollment_ratio
    d$severity <- ifelse(d$ratio<cfg$enrollment_ratio,"AMBER","NO FLAG"); d
  } else if(check=="queries") {
    d <- read_input("queries","QUERY_AGE_DAYS")
    if(any(d$QUERY_AGE_DAYS<0))stop("Query age cannot be negative.")
    cfg$query_days<-config_number("query_days",0)
    n_open <- sum(d$OPEN_FL=="Y"); aged <- sum(d$OPEN_FL=="Y" & d$QUERY_AGE_DAYS>cfg$query_days)
    data.frame(n_open=n_open,n_aged=aged,age_threshold_days=cfg$query_days,severity=if(aged>0) "AMBER" else "NO FLAG",stringsAsFactors=FALSE)
  } else if(check=="visits") {
    d <- read_input("visits","WINDOW_DAYS",c("ACTDT","PLANDT"))
    if(any(d$WINDOW_DAYS<0|d$WINDOW_DAYS!=floor(d$WINDOW_DAYS)))stop("Visit windows must be nonnegative whole days.")
    reference <- as.Date(cfg$analysis_date,format="%Y-%m-%d")
    if(length(reference)!=1L||is.na(reference)||!grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$",cfg$analysis_date)||format(reference,"%Y-%m-%d")!=cfg$analysis_date||anyNA(d$PLANDT)) stop("Visits require a valid explicit analysis date and planned dates.")
    overdue <- is.na(d$ACTDT) & d$PLANDT<reference
    outside <- !is.na(d$ACTDT) & abs(as.numeric(d$ACTDT-d$PLANDT))>d$WINDOW_DAYS
    d$analysis_date <- reference
    d$window_end <- d$PLANDT+d$WINDOW_DAYS
    d$missing_past_window <- is.na(d$ACTDT)&d$window_end<reference
    d$flag <- ifelse(overdue,"Past planned visit date; not completed",ifelse(outside,"Outside supplied visit window","No timing flag"))
    d$severity <- ifelse(overdue|outside,"AMBER","NO FLAG"); d
  } else if(check=="irt") {
    a <- read_input("clinical"); b <- read_input("randomization")
    a$in_clinical <- TRUE; b$in_randomization <- TRUE
    d <- merge(a,b,by="USUBJID",all=TRUE,sort=TRUE)
    d$flag <- ifelse(is.na(d$in_clinical),"In randomization feed; absent from clinical feed",ifelse(is.na(d$in_randomization),"In clinical feed; absent from randomization feed",ifelse(d$TRT01P!=d$IXRS_TRT,"Treatment assignment differs","Assignments agree")))
    d$severity <- ifelse(d$flag=="Assignments agree","NO FLAG","AMBER")
    d$in_clinical <- NULL;d$in_randomization <- NULL;d
  } else stop("Unknown monitoring check.")
}
