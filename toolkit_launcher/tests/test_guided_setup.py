"""Private study intake, reproducible preview and versioned generation boundaries."""
import base64
import json
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest.mock import patch
import zipfile

from toolkit_launcher import guided_setup as setup
from toolkit_launcher.runtime import InputError, ROOT


class GuidedSetupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='guided study spaces ')
        self.root = Path(self.temp.name) / 'workspace'
        self.root.mkdir()
        shutil.copytree(ROOT / 'sas_r_automation/macro_library', self.root / 'sas_r_automation/macro_library')
        self.module = 'sas_monitor'
        self.values = dict(study_id='STUDY-NEUTRAL', checks=['queries'], review_confirmed=True,
                           columns={'queries': {'OPEN_FL': 'Open', 'QUERY_AGE_DAYS': 'Age'}})
        self.upload('Open,Age\nY,31\nN,5\n')

    def tearDown(self):
        self.temp.cleanup()

    def upload(self, text):
        return setup.upload(self.root, self.module, 'queries', 'Study queries.csv', base64.b64encode(text.encode()).decode())

    def preview(self):
        result = setup.act(self.root, self.module, 'validate', self.values)
        self.assertFalse(result['report']['errors'], result)
        return result

    def test_generated_package_is_private_versioned_and_uses_mapped_data(self):
        self.preview()
        source = self.root / 'sas_r_automation/macro_library/monitor_driver.sas'
        original = source.read_bytes()
        with patch('subprocess.Popen', side_effect=AssertionError('Generation must never execute a process')):
            first = setup.act(self.root, self.module, 'generate', self.values)
            second = setup.act(self.root, self.module, 'generate', self.values)
        self.assertNotEqual(first['build']['zip_path'], second['build']['zip_path'])
        self.assertEqual(source.read_bytes(), original)
        with zipfile.ZipFile(self.root / first['build']['zip_path']) as archive:
            self.assertEqual(archive.read('inputs/queries.csv').decode(), 'OPEN_FL,QUERY_AGE_DAYS\nY,31.0\nN,5.0\n')
            self.assertIn('SETUP_REPORT.html', archive.namelist())
            profile = json.loads(archive.read('setup_profile.json'))
            self.assertEqual(profile['values']['study_id'], 'STUDY-NEUTRAL')
            manifest = json.loads(archive.read('input_manifest.json'))
            self.assertNotIn('absolute_path', manifest['queries'])
            self.assertNotIn(str(self.root), archive.read('input_manifest.json').decode())
            self.assertTrue(json.loads(archive.read('source_fingerprints.json')))
            self.assertIn(b'No analysis program', archive.read('SETUP_REPORT.html'))
        self.assertEqual(len(setup.state(self.root, self.module)['builds']), 2)

    def test_generation_requires_current_successful_preview(self):
        self.assertTrue(setup.act(self.root, self.module, 'generate', self.values)['report']['errors'])
        self.preview()
        changed = dict(self.values, query_days=20)
        self.assertTrue(setup.act(self.root, self.module, 'generate', changed)['report']['errors'])
        self.upload('Open,Age\nY,41\n')
        self.assertTrue(setup.act(self.root, self.module, 'generate', self.values)['report']['errors'])
        self.preview()
        source = self.root / 'sas_r_automation/macro_library/monitor_driver.sas'
        source.write_text(source.read_text() + '\n/* reviewed local change */\n')
        self.assertTrue(setup.act(self.root, self.module, 'generate', self.values)['report']['errors'])
        self.preview()
        self.assertIn('build', setup.act(self.root, self.module, 'generate', self.values))

    def test_replacing_inputs_preserves_backup_and_invalid_csv_preserves_current(self):
        self.upload('Open,Age\nY,45\n')
        self.assertTrue(list((self.root.parent / 'input-backups').glob('*.csv')))
        original = (self.root / 'template_inputs/sas_monitor/queries.csv').read_bytes()
        for invalid in ('Open,Open\nY,4\n', 'Open,Age\nY\n', '__proto__,Age\nY,3\n', 'Open,Age\nY,\x00\n'):
            with self.subTest(invalid=invalid), self.assertRaises(InputError):
                self.upload(invalid)
        self.assertEqual((self.root / 'template_inputs/sas_monitor/queries.csv').read_bytes(), original)
        self.assertFalse(list((self.root / 'template_inputs/sas_monitor').glob('.input-*')))

    def test_header_only_intake_is_allowed_but_required_feed_still_fails_preview(self):
        result = self.upload('Open,Age\n')
        self.assertEqual(result['input']['rows'], 0)
        report = setup.act(self.root, self.module, 'validate', self.values)['report']
        self.assertTrue(report['errors'])
        self.assertNotIn('build', setup.act(self.root, self.module, 'generate', self.values))

    def test_profiles_are_reusable_settings_not_data_or_cross_module_state(self):
        setup.act(self.root, self.module, 'save', self.values)
        profile = json.loads((self.root / setup.profile_path(self.module)).read_text())
        other = Path(self.temp.name) / 'other'
        other.mkdir()
        setup.import_profile(other, self.module, profile)
        state = setup.state(other, self.module)
        self.assertEqual(state['values']['study_id'], 'STUDY-NEUTRAL')
        self.assertFalse(state['inputs'])
        self.assertFalse(state['builds'])
        for bad in (dict(profile, module_id='localmind'), dict(profile, schema=2), dict(profile, private_path='/tmp/file')):
            with self.assertRaises(InputError):
                setup.import_profile(other, self.module, bad)

    def test_profile_shape_and_csv_slot_are_allowlisted(self):
        for values in ([], {'command': 'echo bad'}, {'columns': {'outside': {}}}, {'query_days': float('inf')}, {'study_id': '\x00'}):
            with self.subTest(values=values), self.assertRaises(InputError):
                setup.act(self.root, self.module, 'save', values)
        for module in ('../escape', [], None):
            with self.assertRaises(InputError):
                setup.state(self.root, module)
        for slot in ('../escape', [], None):
            with self.assertRaises(InputError):
                setup.upload(self.root, self.module, slot, 'test.csv', 'YWJj')
        with self.assertRaises(InputError):
            setup.act(self.root, self.module, [], {})

    def test_private_input_and_output_symlinks_are_rejected(self):
        outsider = Path(self.temp.name) / 'outside'
        outsider.mkdir()
        target = self.root / 'template_inputs/sas_monitor/queries.csv'
        target.unlink()
        target.symlink_to(outsider / 'queries.csv')
        with self.assertRaises(InputError):
            self.upload('Open,Age\nY,31\n')
        self.assertFalse((outsider / 'queries.csv').exists())
        target.unlink()
        self.upload('Open,Age\nY,31\n')
        self.preview()
        (self.root / 'template_outputs').symlink_to(outsider, target_is_directory=True)
        with self.assertRaises(InputError):
            setup.act(self.root, self.module, 'generate', self.values)
        self.assertFalse(list(outsider.iterdir()))

    def test_source_links_are_rejected_before_provider_reads(self):
        outside = Path(self.temp.name) / 'sensitive.R'
        outside.write_text('PRIVATE CONTENT')
        (self.root / 'sas_r_automation/macro_library/linked.R').symlink_to(outside)
        with patch.object(setup.provider(self.module), 'schema', side_effect=AssertionError('Provider must not read linked sources')):
            with self.assertRaises(InputError):
                setup.state(self.root, self.module)

    def test_unsafe_generated_paths_roll_back_without_partial_bundle(self):
        self.preview()
        for filename in ('../../outside.txt', 'C:/outside.txt', 'run.sh', 'nested/../outside.txt'):
            with self.subTest(filename=filename), patch.object(setup.provider(self.module), 'build', return_value={'files': {'safe.txt': 'first', filename: 'bad'}}):
                with self.assertRaises(InputError):
                    setup.act(self.root, self.module, 'generate', self.values)
                self.assertFalse(list((self.root / 'template_outputs/sas_monitor').iterdir()))
        self.assertFalse((self.root.parent / 'outside.txt').exists())

    def test_report_escapes_study_text_and_retains_light_dark_control(self):
        spec = setup.schema(self.root, self.module)
        report = setup.readiness_html(self.module, {'study_id': '<img src=x onerror=alert(1)>'}, {'summary': ['<script>bad()</script>']}, {}, {}, [])
        self.assertNotIn('<img', report)
        self.assertNotIn('<script>bad()', report)
        self.assertIn('&lt;img', report)
        self.assertIn('theme-toggle', report)
        self.assertIn('data-theme="dark"', report)


if __name__ == '__main__':
    unittest.main()
