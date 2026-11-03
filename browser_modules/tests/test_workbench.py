"""Browser provider contracts, including failure atomicity and complete exports."""
import base64,csv,html,json,tempfile,unittest
from html.parser import HTMLParser
from pathlib import Path
from browser_modules.workbench import backend
ROOT=Path(__file__).resolve().parents[2]
class BrowserProviders(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory();backend.ROOT=ROOT;backend.SESSION=Path(self.temp.name)/'session';backend.reset()
 def tearDown(self):self.temp.cleanup()
 def values(self,module):return {f['id']:f.get('default',False if f['type']=='checkbox' else [] if f['type'] in ('multiselect','template-select') else '') for step in backend.schema(module)['steps'] for f in step['fields']}
 def test_monitor_complete_eight_check_package_and_unexecuted_sas(self):
  ex=backend.example('sas_monitor');v=self.values('sas_monitor');v.update(ex['values']);v['review_confirmed']=True;b=backend.build('sas_monitor',v)
  self.assertTrue(b['ok'],b);self.assertIn('run_monitor.sas',b['files']);self.assertEqual(len(json.loads(b['files']['browser_input_inventory.json'])['inputs']),9);self.assertFalse(json.loads(b['files']['audit.json'])['approved']);self.assertIn('toolkit_launcher/analysis_runner.R',b['files'])
 def test_rejected_replacement_removes_old_input(self):
  backend.example('sas_monitor');bad=base64.b64encode(b'OPEN_FL,OPEN_FL\nY,31\n').decode()
  with self.assertRaises(ValueError):backend.import_csv('sas_monitor','queries','bad.csv',bad)
  self.assertNotIn('queries',backend.inputs_for('sas_monitor'))
  with self.assertRaises(ValueError):backend.import_csv('sas_monitor','../../private','bad.csv',bad)
 def test_malformed_rows_encoding_and_profile_types_fail(self):
  for raw in [b'OPEN_FL,QUERY_AGE_DAYS\nY\n',b'OPEN_FL,QUERY_AGE_DAYS\n"Y,31',b'\xff']:
   with self.assertRaises((ValueError,UnicodeError,csv.Error)):backend.import_csv('sas_monitor','queries','bad.csv',base64.b64encode(raw).decode())
  for v in [{'checks':'liver'},{'review_confirmed':'true'},{'columns':{'liver':[]}},{'unknown':1}]:
   with self.assertRaises(ValueError):backend.check_profile('sas_monitor',v)
 def test_ae_pk_contracts_and_no_automatic_confirmation(self):
  for kind in ('ae','pk'):
   ex=backend.example('interpretation',summary_type=kind);v=self.values('interpretation');v.update(ex['values']);self.assertTrue(backend.validate('interpretation',v)['errors']);v.update(review_confirmed=True,aggregate_confirmed=True);b=backend.build('interpretation',v);self.assertTrue(b['ok'],b);self.assertIn('verify_preview.R',b['files'])
 def test_localmind_never_enables_loopback_and_retains_raw_findings(self):
  ex=backend.example('localmind');v=self.values('localmind');v.update(ex['values']);v.update(review_confirmed=True,enable_model=True,model_name='irrelevant');b=backend.build('localmind',v);self.assertTrue(b['ok'],b);self.assertFalse(b['validation']['normalized']['enable_model']);self.assertEqual(len(b['review']['rows']),2);self.assertEqual(b['review']['labels']['severity'],['LOW','MEDIUM','HIGH']);self.assertFalse(json.loads(b['files']['audit.json'])['approved'])
 def test_localmind_browser_guidance_is_primary_and_desktop_references_are_preserved(self):
  ex=backend.example('localmind');v=self.values('localmind');v.update(ex['values']);v['review_confirmed']=True;b=backend.build('localmind',v);self.assertTrue(b['ok'],b)
  files=b['files'];guide=files['BROWSER_START_HERE.txt'];self.assertEqual(guide,files['START_HERE.txt'])
  for text in ['Edit owner, severity, novelty, reviewer and review notes in the browser','Load optional browser model','WebGPU','first download','Suggest labels for this finding','apply any chosen labels manually','Download current review CSV','review_UNAPPROVED.json','review_UNAPPROVED.csv','model_audit_UNAPPROVED.json','Download complete ZIP','All findings, labels and suggestions remain unapproved','audit.json is the original setup/reference audit']:
   self.assertIn(text,guide)
  primary=guide+files['setup_review.html']+' '.join(b['limitations'])
  for stale in ['analysis_report.html','These results were computed','install httr2','RStudio','Ollama','No model has been contacted']:
   self.assertNotIn(stale,primary)
  canonical=backend.guided_modules.build('localmind',b['validation']['normalized'],backend.selected_inputs('localmind',b['validation']['normalized']),ROOT)
  for name in ['study.Rproj','run_local_model.R','R/slm_companion.R','open_review.sas','inputs/findings.csv','review.csv','audit.json']:
   self.assertEqual(files[name],canonical['files'][name],name)
  self.assertTrue(files['DESKTOP_REFERENCE_START_HERE.txt'].endswith(canonical['files']['START_HERE.txt']))
  self.assertIn('Optional desktop reference only',files['DESKTOP_REFERENCE_START_HERE.txt']);self.assertIn('Ollama',files['DESKTOP_REFERENCE_START_HERE.txt'])
  self.assertEqual(json.loads(files['audit.json'])['execution'],'not_run');self.assertFalse(json.loads(files['audit.json'])['approved'])
 def test_localmind_browser_guide_escapes_study_values_and_keeps_theme_controls(self):
  ex=backend.example('localmind');v=self.values('localmind');v.update(ex['values']);v.update(review_confirmed=True,study_id='NEUTRAL <img src=x onerror=alert(1)> & "study"',study_title='<script>window.untrustedTitle=1</script>')
  b=backend.build('localmind',v);self.assertTrue(b['ok'],b);document=b['files']['setup_review.html']
  for field in ['study_id','study_title']:
   self.assertIn(html.escape(v[field]),document);self.assertNotIn(v[field],document)
  class Tags(HTMLParser):
   def __init__(self):super().__init__();self.tags=[]
   def handle_starttag(self,tag,attrs):self.tags.append((tag,dict(attrs)))
  parsed=Tags();parsed.feed(document)
  self.assertFalse(any(tag=='img' for tag,attrs in parsed.tags));self.assertEqual(sum(tag=='script' for tag,attrs in parsed.tags),1)
  self.assertTrue(any(tag=='button' and attrs.get('id')=='theme' for tag,attrs in parsed.tags));self.assertIn(':root[data-theme="light"]',document);self.assertIn(':root:not([data-theme="dark"])',document)
  self.assertIn('does not report current inference status or completed numerical analyses',document)
 def test_browser_schema_and_analysis_guide_do_not_claim_desktop_execution_or_success(self):
  browser=backend.schema('localmind');desktop=backend.guided_modules.schema('localmind',ROOT)
  self.assertIn('browser-model suggestions',browser['intro']);self.assertNotIn('generated R driver',browser['intro']);self.assertIn('generated R driver',desktop['intro'])
  self.assertEqual(next(s for s in browser['steps'] if s['id']=='model')['title'],'Optional browser model')
  ex=backend.example('sas_monitor');v=self.values('sas_monitor');v.update(ex['values']);v['review_confirmed']=True;b=backend.build('sas_monitor',v);self.assertTrue(b['ok'],b);guide=b['files']['BROWSER_START_HERE.txt']
  self.assertIn('does not establish whether an analysis completed',guide);self.assertIn('execution_status.csv',guide);self.assertIn('analysis_report.html',guide);self.assertNotIn('These results were computed',guide)
  self.assertNotIn('analysis_report.html',b['files']);self.assertEqual(json.loads(b['files']['audit.json'])['execution'],'not_run')
 def test_inactive_feed_is_excluded_from_export_and_provenance(self):
  ex=backend.example('interpretation');v=self.values('interpretation');v.update(ex['values']);v.update(review_confirmed=True,aggregate_confirmed=True)
  backend.import_csv('interpretation','pk_summary','other-study.csv',base64.b64encode(b'private_column\nUNSELECTED-OTHER-STUDY\n').decode());b=backend.build('interpretation',v)
  self.assertTrue(b['ok']);self.assertNotIn('uploads/pk_summary.csv',b['files']);self.assertNotIn('UNSELECTED-OTHER-STUDY',json.dumps(b));self.assertEqual(set(json.loads(b['files']['browser_input_inventory.json'])['inputs']),{'ae_summary'})
 def test_full_csv_quotes_unicode_and_zero_rows(self):
  raw='finding_id,rule,findtext\r\nF1,Rule,"A quoted, μ value\nsecond line"\r\n';meta=backend.import_csv('localmind','findings','example.csv',base64.b64encode(raw.encode()).decode());self.assertEqual(meta['rows'],1);self.assertIn('μ',meta['preview'][0][2]);backend.reset();self.assertEqual(backend.inputs_for('localmind'),{})
if __name__=='__main__':unittest.main()
