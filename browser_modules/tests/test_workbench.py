"""Browser provider contracts, including failure atomicity and complete exports."""
import base64,csv,json,tempfile,unittest
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
 def test_inactive_feed_is_excluded_from_export_and_provenance(self):
  ex=backend.example('interpretation');v=self.values('interpretation');v.update(ex['values']);v.update(review_confirmed=True,aggregate_confirmed=True)
  backend.import_csv('interpretation','pk_summary','other-study.csv',base64.b64encode(b'private_column\nUNSELECTED-OTHER-STUDY\n').decode());b=backend.build('interpretation',v)
  self.assertTrue(b['ok']);self.assertNotIn('uploads/pk_summary.csv',b['files']);self.assertNotIn('UNSELECTED-OTHER-STUDY',json.dumps(b));self.assertEqual(set(json.loads(b['files']['browser_input_inventory.json'])['inputs']),{'ae_summary'})
 def test_full_csv_quotes_unicode_and_zero_rows(self):
  raw='finding_id,rule,findtext\r\nF1,Rule,"A quoted, μ value\nsecond line"\r\n';meta=backend.import_csv('localmind','findings','example.csv',base64.b64encode(raw.encode()).decode());self.assertEqual(meta['rows'],1);self.assertIn('μ',meta['preview'][0][2]);backend.reset();self.assertEqual(backend.inputs_for('localmind'),{})
if __name__=='__main__':unittest.main()
