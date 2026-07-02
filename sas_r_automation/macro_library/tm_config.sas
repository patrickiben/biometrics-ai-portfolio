/*====================================================================================
  tm_config.sas  -  per-study constants for the TRIALMON monitor. Copy + edit per study;
  %include before monitor_driver.sas. Keeps study id, paths, recipients, the medical
  monitor, feeds, and thresholds OUT of the driver so a second study (or a rotating MM)
  is one file, not a code edit.
====================================================================================*/
%global CFG_STUDY CFG_ROOT CFG_SMTP CFG_STATE CFG_SDTM CFG_ADAM CFG_SAFE CFG_IXRS
        CFG_SUPPORT CFG_BACKUP CFG_ALIAS CFG_PM CFG_MGR CFG_MM_NAME CFG_MM_PHONE
        CFG_FEEDS CFG_MAXAGE CFG_ALTM CFG_BILM CFG_DOSEVAR CFG_ENROLL_KRI CFG_QRY_AGE;

/* --- study & paths --- */
%let CFG_STUDY  = CP101;
%let CFG_ROOT   = /opt/trialmon/cp101;
%let CFG_SMTP   = smtp.internal.example.com;
%let CFG_STATE  = /opt/trialmon/cp101/state;       /* persistent: seen-flags + heartbeat */
%let CFG_SDTM   = /data/cp101/sdtm;
%let CFG_ADAM   = /data/cp101/adam;
%let CFG_SAFE   = /data/cp101/safety;
%let CFG_IXRS   = /data/cp101/ixrs;

/* --- recipients & escalation (role aliases + a backup, never one inbox) --- */
%let CFG_SUPPORT= biostat.cover@example.com;
%let CFG_BACKUP = biostat.backup@example.com;       /* also the watchdog / fail-loud target */
%let CFG_ALIAS  = biostat-cover@example.com;
%let CFG_PM     = pm.cp101@example.com;
%let CFG_MGR    = manager@example.com;
%let CFG_MM_NAME= %str(Dr. R. Okafor);
%let CFG_MM_PHONE= +1-555-0100;

/* --- feeds & freshness --- */
%let CFG_FEEDS  = adam.adlb adam.adeg adam.adae safe.sae ixrs.rand;
%let CFG_MAXAGE = 26;                                /* hours before a feed is flagged stale */

/* --- thresholds (pre-specified from the protocol/SAP) --- */
%let CFG_ALTM     = 3;       /* Hy's-Law ALT/AST multiple of ULN (strict >)  */
%let CFG_BILM     = 2;       /* Hy's-Law total bilirubin multiple of ULN     */
%let CFG_DOSEVAR  = COHORT;  /* the DOSE-LEVEL key for the 3+3 DLT tally; set to DOSELVL if cohort != dose level */
%let CFG_ENROLL_KRI = 0.80;  /* enrollment KRI floor (fraction of plan)      */
%let CFG_QRY_AGE  = 30;      /* open-query aging threshold (days)            */
