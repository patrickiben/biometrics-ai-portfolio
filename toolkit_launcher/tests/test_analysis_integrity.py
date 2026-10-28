"""Independent adversarial checks for pinned computation and truthful failures."""
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import zipfile

from toolkit_launcher import analysis_jobs as analysis, runtime
from toolkit_launcher.tests import test_analysis_jobs as job_fixture
from toolkit_launcher.tests import test_guided_setup as setup_fixture
from toolkit_launcher import guided_setup


class AnalysisIntegrityTests(unittest.TestCase):
    def setUp(self):
        self.fixture = job_fixture.AnalysisJobsTests()
        self.fixture.setUp()

    def tearDown(self):
        self.fixture.tearDown()

    def installed_copy(self, directory):
        source = Path(directory)
        for name in analysis.ENGINE_FILES:
            target = source / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes((runtime.ROOT / name).read_bytes())
        return source

    def test_monitor_adapter_and_theme_each_change_engine_identity(self):
        with tempfile.TemporaryDirectory() as temp:
            source = self.installed_copy(temp)
            with patch.object(analysis, 'ROOT', source):
                before = analysis.engine_fingerprint()
                for name in analysis.ENGINE_FILES:
                    path = source / name
                    original = path.read_bytes()
                    path.write_bytes(original + b'\n# synthetic revision\n')
                    self.assertNotEqual(before, analysis.engine_fingerprint(), name)
                    path.write_bytes(original)
                    self.assertEqual(before, analysis.engine_fingerprint())

    def test_generated_revision_rejects_changed_monitor_implementation(self):
        f = self.fixture
        with tempfile.TemporaryDirectory() as temp:
            source = self.installed_copy(temp)
            fingerprints = {name: hashlib.sha256((source / name).read_bytes()).hexdigest() for name in analysis.ENGINE_FILES}
            path = f.bundle / 'source_fingerprints.json'
            path.write_text(json.dumps(fingerprints), encoding='utf-8')
            f.manifest['files']['source_fingerprints.json'] = hashlib.sha256(path.read_bytes()).hexdigest()
            f.set_inventory()
            with patch.object(analysis, 'ROOT', source):
                analysis.resolve_build(f.root, f.module, f.build_id)
                monitor = source / 'toolkit_launcher/analysis_monitor.R'
                monitor.write_text(monitor.read_text() + '\n# changed method\n')
                with self.assertRaisesRegex(runtime.InputError, 'changed since this package'):
                    analysis.resolve_build(f.root, f.module, f.build_id)

    def test_result_must_match_run_identity_and_exact_selected_outputs(self):
        f = self.fixture
        plan, folder, _ = f.plan()
        f.valid_results(folder)
        analysis.verify_results(folder, plan)
        path = folder / 'output_manifest.json'
        original = json.loads(path.read_text())
        for edit, error in [('wrong_run', 'provenance'), ('wrong_output', 'every selected'), ('duplicate', 'every selected')]:
            manifest = json.loads(json.dumps(original))
            if edit == 'wrong_run':
                manifest['run_id'] = 'run-' + '0' * 32
            elif edit == 'wrong_output':
                manifest['outputs'][0]['id'] = 'unrequested'
            else:
                manifest['outputs'].append(manifest['outputs'][0])
            path.write_text(json.dumps(manifest))
            with self.assertRaisesRegex(runtime.InputError, error):
                analysis.verify_results(folder, plan)
        path.write_text(json.dumps(original))
        (folder / 'execution_status.csv').write_text('output,status\ninterpretation,failed\n')
        with self.assertRaisesRegex(runtime.InputError, 'status table'):
            analysis.verify_results(folder, plan)

    def test_changed_inputs_invalidate_every_downloaded_success_claim(self):
        f = self.fixture
        _, folder, _ = f.plan()
        def changed_input(argv, cwd):
            f.valid_results(folder)
            (folder / 'analysis_report.html').write_text("<html><main><p>All selected outputs completed.</p></main></html>")
            (f.bundle / 'inputs/result.csv').write_text('changed during computation')
            return subprocess.CompletedProcess(argv, 0)
        with patch.object(analysis.subprocess, 'run', side_effect=changed_input):
            self.assertEqual(analysis.execute(folder / 'plan.json', 'fixed-Rscript'), 1)
        qc = json.loads((folder / 'qc.json').read_text())
        manifest = json.loads((folder / 'output_manifest.json').read_text())
        self.assertFalse(qc['passed'])
        self.assertFalse(qc['approved'])
        self.assertEqual(manifest['status'], 'failed')
        self.assertEqual(manifest['outputs'][0]['status'], 'invalidated')
        self.assertFalse((folder / 'table.csv').exists())
        page = (folder / 'analysis_report.html').read_text()
        self.assertIn('Numerical results were invalidated', page)
        self.assertIn('Light / dark', page)
        self.assertNotIn('All selected outputs completed', page)
        with zipfile.ZipFile(folder / 'results.zip') as archive:
            self.assertFalse(json.loads(archive.read('qc.json'))['passed'])
            self.assertEqual(json.loads(archive.read('output_manifest.json'))['status'], 'failed')
            self.assertNotIn('table.csv', archive.namelist())
            self.assertNotIn(b'All selected outputs completed', archive.read('analysis_report.html'))

    def test_bad_result_metadata_cannot_prevent_failure_diagnostics(self):
        f = self.fixture
        _, folder, _ = f.plan()
        def corrupted_results(argv, cwd):
            f.valid_results(folder)
            (folder / 'qc.json').write_text(json.dumps({'errors': 7}))
            (folder / 'output_manifest.json').write_text(json.dumps({'outputs': [None]}))
            return subprocess.CompletedProcess(argv, 0)
        with patch.object(analysis.subprocess, 'run', side_effect=corrupted_results):
            self.assertEqual(analysis.execute(folder / 'plan.json', 'fixed-Rscript'), 1)
        self.assertTrue((folder / 'execution_error.json').is_file())
        self.assertFalse(json.loads((folder / 'qc.json').read_text())['passed'])


class AnalysisGenerationRaceTests(unittest.TestCase):
    def setUp(self):
        self.fixture = setup_fixture.GuidedSetupTests()
        self.fixture.setUp()

    def tearDown(self):
        self.fixture.tearDown()

    def test_changed_inputs_or_sources_during_build_never_publish_revision(self):
        f = self.fixture
        provider = guided_setup.provider(f.module)
        build = provider.build
        for change in ('input', 'source'):
            f.preview()
            def changed_build(*args, **kwargs):
                generated = build(*args, **kwargs)
                if change == 'input':
                    (f.root / 'template_inputs/sas_monitor/queries.csv').write_text('Open,Age\nY,77\n')
                else:
                    source = f.root / 'sas_r_automation/macro_library/monitor_driver.sas'
                    source.write_text(source.read_text() + '\n/* modified during build */\n')
                return generated
            with patch.object(provider, 'build', side_effect=changed_build):
                with self.assertRaisesRegex(runtime.InputError, 'changed during generation'):
                    guided_setup.act(f.root, f.module, 'generate', f.values)
            self.assertFalse(list((f.root / 'template_outputs').glob('**/setup-*')))


if __name__ == '__main__':
    unittest.main()
