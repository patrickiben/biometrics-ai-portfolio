/*====================================================================================
  slm_config.sas  -  per-deployment constants for LOCALMIND. %include before the driver.
  Pin the model here; keep the allowlists (the controlled vocabularies the model's output
  is validated against) in one place so adding a label is a config edit, not a code edit.
====================================================================================*/
%global CFG_MODEL CFG_BASE CFG_SEED CFG_BACKUP
        CFG_OWNERS CFG_SEVERITY CFG_NOVELTY;

/* The PINNED model: exact tag + quantization. Must be `ollama pull`-ed already.
   Prefer an Apache-2.0/MIT model (Qwen2.5, Granite, Phi) to avoid licence friction.    */
%let CFG_MODEL = qwen2.5:7b-instruct-q8_0;
%let CFG_BASE  = http://127.0.0.1:11434;     /* loopback only - %slm_init refuses anything else */
%let CFG_SEED  = 42;                          /* fixed seed + temperature 0 = reproducible       */
%let CFG_BACKUP= biostat.backup@example.com;  /* fail-loud target                                */

/* The controlled vocabularies (pipe-delimited). The model's output is rejected if it is
   not on these lists - the in-code trust boundary, analogous to SHEETLINK's allowlist.   */
%let CFG_OWNERS   = DM|PROGRAMMING|PK|MEDICAL CODING|SITE|BIOSTAT;
%let CFG_SEVERITY = CRITICAL|MAJOR|MINOR;
%let CFG_NOVELTY  = NEW|KNOWN;
