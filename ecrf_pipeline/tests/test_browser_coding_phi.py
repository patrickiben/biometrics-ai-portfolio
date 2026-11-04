"""Browser intake/export contracts; core algorithms remain the canonical app functions.
The UI tests explicitly simulate only the browser branch in native AppTest. Actual
WebAssembly upload/execution is covered by the separate browser integration suite.
"""
import ast, csv, io, json, os, pathlib, tempfile, types, unittest, zipfile
from unittest.mock import patch
import pandas as pd
from streamlit.testing.v1 import AppTest

ROOT=pathlib.Path(__file__).resolve().parents[1]
MARKER='# ========================= UI EXECUTION ========================='

def load(name):
    p=ROOT/(name+'_app.py');ns={'__name__':'browser_contract_'+name,'__file__':str(p)}
    exec(compile(p.read_text().split(MARKER)[0],str(p),'exec'),ns)
    return ns

class BrowserContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls): cls.c=load('meddra');cls.p=load('phi')

    def test_runtime_guard_requires_platform_and_explicit_flag(self):
        for name in ['meddra','phi']:
            tree=ast.parse((ROOT/(name+'_app.py')).read_text())
            value=next(n.value for n in tree.body if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='BROWSER_REQUESTED' for t in n.targets))
            for platform,flag,expected in [('darwin','1',False),('linux','1',False),('emscripten','0',False),('emscripten',None,False),('emscripten','1',True)]:
                actual=eval(compile(ast.Expression(value),'guard','eval'),{'sys':types.SimpleNamespace(platform=platform),'os':types.SimpleNamespace(environ={'ECRF_BROWSER':flag} if flag else {})})
                self.assertEqual(actual,expected)

    def test_strict_csv_preserves_strings_and_rejects_ambiguous_intake(self):
        for app in (self.c,self.p):
            read=app['_browser_csv'];df=read('custom.csv',b'participant,note,value\n0001,"line 1\nline 2",NA\n')
            self.assertEqual(df.iloc[0].tolist(),['0001','line 1\nline 2','NA'])
            for name,data in [('x.csv',b'a,a\n1,2\n'),('x.csv',b'a,A \n1,2\n'),('x.csv',b'a,b\n1\n'),('x.csv',b'a\n"unterminated'),('x.csv',b'a\n\xff'),('../x.csv',b'a\n1'),('a\\b.csv',b'a\n1'),('x.csv',b'a\nx\x00'),('x.csv',b'a\n'+b'x'*20001),('x.csv',b'a,b\n')]:
                with self.subTest(name=name,data=data[:25]),self.assertRaises(ValueError):read(name,data)
            with self.assertRaises(ValueError):read('large.csv',b'a\n'+b'x'*(10*1024*1024))
            with self.assertRaises(ValueError):read('rows.csv',b'a\n1\n2\n',max_rows=1)

    def test_filename_collisions_and_total_size_rejected(self):
        def upload(name,b):return types.SimpleNamespace(name=name,getvalue=lambda:b)
        for app in (self.c,self.p):
            with self.assertRaises(ValueError):app['_browser_uploads']([upload('a.csv',b'a\n1'),upload('A.csv',b'a\n2')])
            with self.assertRaises(ValueError):app['_browser_uploads']([upload(f'{i}.csv',b'x'*8000000) for i in range(3)])

    def test_formula_safe_csv_and_lossless_json(self):
        values=['=1+1',' \t@SUM(1)','\t-HYPERLINK("x")','\ufeff+CMD','-1.5','001','line1\nline2','<img src=x onerror=alert(1)>']
        for app in (self.c,self.p):
            encoded=app['_browser_export_csv'](pd.DataFrame({'text':values,'numeric':[-1.5]*len(values)}))
            rows=list(csv.DictReader(io.StringIO(encoded.decode())))
            self.assertTrue(all(rows[i]['text'].startswith("'") for i in range(4)))
            self.assertEqual([r['text'] for r in rows[4:]],values[4:]);self.assertEqual(rows[0]['numeric'],'-1.5')
            self.assertEqual(json.loads(app['_browser_json'](values)),values)
            unsafe_header=pd.DataFrame({'=1+1':['text'], ' \t@SUM(1)':['001']})
            header=list(csv.reader(io.StringIO(app['_browser_export_csv'](unsafe_header).decode())))[0]
            self.assertEqual(header,["'=1+1","' \t@SUM(1)"])
            self.assertEqual(json.loads(app['_browser_json'](unsafe_header.to_dict('records'))),unsafe_header.to_dict('records'))

    def test_dictionary_mapping_currency_and_conflicts(self):
        raw=pd.DataFrame({'term':['headache','nausea','old'],'preferred':['Headache','Nausea','Retired'],'code':['0001','0002','0003'],'current':['Y','Y','N']})
        m={'llt_name':'term','pt_name':'preferred','pt_code':'code','currency':'current'}
        d=self.c['_browser_dictionary'](raw,m);self.assertEqual(d['pt_code'].tolist(),['0001','0002'])
        with self.assertRaises(ValueError):self.c['_browser_dictionary'](raw,m,'Z')
        bad=raw.copy();bad.loc[1,'code']='0001'
        with self.assertRaises(ValueError):self.c['_browser_dictionary'](bad,m)
        bad=raw.copy();bad.loc[0,'term']=' '
        with self.assertRaises(ValueError):self.c['_browser_dictionary'](bad,m)

    def test_coding_reuses_scores_and_never_approves_or_exports_unselected_data(self):
        df=pd.DataFrame({'study':['A','B'],'person':['001','001'],'event':['1','1'],'raw':['headache','headache'],'unused':['SECRET-A','SECRET-B']})
        d=pd.DataFrame({'llt_name':['headache','nausea'],'pt_name':['Headache','Nausea'],'pt_code':['0001','0002']})
        m={'client.csv':{'study':'study','participant':'person','key':'event','verbatim':'raw'}}
        config={'dictionary_name_version':'Uploaded v1','active_values':'Y','dictionary_mapping':{},'study_mapping':m}
        result=self.c['_browser_coding_result']([('client.csv',df)],d,m,0.88,config,[],{'sha256':'test'})
        top=result['table'][result['table']['CANDIDATE_RANK']==1]
        self.assertEqual(top['REVIEW_SCORE'].tolist(),[1.0,1.0]);self.assertEqual(top['PREFERRED_TERM_CODE'].tolist(),['0001','0001'])
        self.assertEqual(set(result['table']['REVIEW_STATUS']),{'UNREVIEWED_CANDIDATE'})
        self.assertEqual(top['STUDY_ID'].tolist(),['A','B']);self.assertEqual(top['SOURCE_ROW'].tolist(),[1,2])
        with zipfile.ZipFile(io.BytesIO(result['zip'])) as z:
            allbytes=b'\n'.join(z.read(n) for n in z.namelist());self.assertNotIn(b'SECRET-',allbytes);self.assertNotIn(b'AUTO_COMMIT',allbytes)
            self.assertIsNone(z.testzip())

    def test_phi_default_path_matches_canonical_redaction(self):
        texts=['Patient Jane Smith called 212-555-1234','Email jane@example.com','Participant J.M., ZIP 02139','No identifier noted','']
        for text in texts:
            sp=self.p['t2_phi'](text);expected,flags,_=self.p['t4_phi'](text,sp,self.p['t3_phi'](text,sp),0.85)
            actual,got=self.p['_browser_phi_text'](text,list(self.p['TAG']),[],0.85)
            self.assertEqual(actual,expected);self.assertEqual(got,flags)

    def test_phi_literals_overlap_pattern_masks_without_remnants_or_tag_corruption(self):
        text='Contact Orion at 212-555-1234 today.'
        actual,flags=self.p['_browser_phi_text'](text,list(self.p['TAG']),['Orion at 212-555-1234'],0.85)
        self.assertEqual(actual,'Contact [REDACTED_CUSTOM_TERM] today.')
        self.assertNotIn('Orion',actual)
        self.assertTrue(any(f['ENTITY']=='CUSTOM_TERM' and f['SPAN']=='Orion at 212-555-1234' for f in flags))
        actual,flags=self.p['_browser_phi_text']('Call 212-555-1234',list(self.p['TAG']),['REDACTED'],0.85)
        self.assertNotIn('CUSTOM_TERM',actual)
        self.assertEqual(actual,'Call '+self.p['TAG']['PHONE'])
        actual,_=self.p['_browser_phi_text']('abcde',[],['abc','cde'],0.85)
        self.assertEqual(actual,'[REDACTED_CUSTOM_TERM]')

    def test_phi_clean_export_excludes_originals_terms_and_unselected_fields(self):
        df=pd.DataFrame({'notes':['Patient Jane Smith, call 212-555-1234. Case Orion.'],'numeric_id':['12345678'],'hidden':['HIDDEN-SECRET']})
        result=self.p['_browser_phi_result']([('client.csv',df)],{'client.csv':['notes','numeric_id']},
            {'client.csv':['notes','numeric_id']},list(self.p['TAG']),['Orion','12345678'],0.85,[{'name':'client.csv','sha256':'x','bytes':100}])
        with zipfile.ZipFile(io.BytesIO(result['zip'])) as z:
            data=b'\n'.join(z.read(n) for n in z.namelist())
            for secret in [b'Jane Smith',b'212-555-1234',b'Orion',b'12345678',b'HIDDEN-SECRET']:self.assertNotIn(secret,data)
            self.assertNotIn('selected_original_fields.json',z.namelist());self.assertIsNone(z.testzip())
        with zipfile.ZipFile(io.BytesIO(result['sensitive_zip'])) as z:
            self.assertIn(b'Jane Smith',z.read('selected_original_fields.json'));self.assertIn(b'Orion',z.read('review_setup.json'));self.assertNotIn(b'HIDDEN-SECRET',z.read('selected_original_fields.json'))

    def test_phi_requires_explicit_scan_and_export_scope(self):
        df=pd.DataFrame({'notes':['hello']})
        with self.assertRaises(ValueError):self.p['_browser_phi_result']([('x.csv',df)],{'x.csv':[]},{'x.csv':[]},list(self.p['TAG']),[],0.85,[])
        with self.assertRaises(ValueError):self.p['_browser_phi_result']([('x.csv',df)],{'x.csv':['notes']},{'x.csv':['missing']},list(self.p['TAG']),[],0.85,[])
        with self.assertRaises(ValueError):self.p['_browser_custom_terms']('x'*201)

    def test_browser_ui_blank_example_staleness_and_reset(self):
        for name,run_label,download_label in [('meddra','Run coding suggestions','Download complete coding package'),('phi','Run de-identification review','Download redacted package')]:
            source=(ROOT/(name+'_app.py')).read_text().replace('BROWSER_REQUESTED = sys.platform == "emscripten" and os.environ.get("ECRF_BROWSER") == "1"','BROWSER_REQUESTED = True')
            source=source.replace("p = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'sample_data', name)",f"p = os.path.join({str(ROOT/'sample_data')!r}, name)")
            with patch.dict(os.environ,{'ECRF_HOSTED':'0'}):
                at=AppTest.from_string(source,default_timeout=90).run();self.assertFalse(at.exception)
                self.assertFalse(any(w.label==run_label for w in at.button));self.assertFalse(any('folder' in w.label.lower() or 'models dir' in w.label.lower() for w in at.text_input))
                next(w for w in at.button if w.label=='Load synthetic example').click().run();self.assertFalse(at.exception,[x.value for x in at.exception])
                next(w for w in at.button if w.label==run_label).click().run();self.assertFalse(at.exception,[x.value for x in at.exception]);self.assertIn('bw_result',at.session_state)
                at.slider[0].set_value(float(at.slider[0].value)-0.01).run();self.assertNotIn('bw_result',at.session_state)
                next(w for w in at.button if w.label=='Reset workspace').click().run();self.assertFalse(at.exception);self.assertNotIn('bw_result',at.session_state)
                self.assertFalse(any(w.label==run_label for w in at.button))

if __name__=='__main__':unittest.main(verbosity=2)
