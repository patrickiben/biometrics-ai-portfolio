"""Immutable study revisions, honest run verdicts and recoverable diagnostics."""
import csv
import hashlib
import json
import re
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

from toolkit_launcher import analysis_jobs as analysis, jobs, runtime
from toolkit_launcher.tests.helpers import make_source, wait_for_job


class AnalysisJobsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='analysis space ')
        self.root = Path(self.temp.name) / 'workspace'
        self.root.mkdir()
        (self.root / 'launch_app.R').write_text('# project marker\n', encoding='utf-8')
        self.module = 'interpretation'
        self.build_id = 'setup-' + 'a' * 24
        self.bundle = self.root / 'template_outputs' / self.module / self.build_id
        self.bundle.mkdir(parents=True)
        self.files = {'setup_profile.json': '{}\n', 'inputs/result.csv': 'label,n\n001,5\n'}
        for name, value in self.files.items():
            path = self.bundle / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(value.encode('utf-8'))
        self.manifest = {'schema': 1, 'module_id': self.module, 'files': {name: hashlib.sha256(value.encode()).hexdigest() for name, value in self.files.items()}}
        self.set_inventory()

    def tearDown(self):
        self.temp.cleanup()

    def set_inventory(self):
        manifest = self.bundle / 'analysis_bundle.json'
        manifest.write_text(json.dumps(self.manifest), encoding='utf-8')
        self.record = {'module_id': self.module, 'build_id': self.build_id, 'engine': 'r', 'bundle_sha256': hashlib.sha256(manifest.read_bytes()).hexdigest()}
        config = self.root / 'toolkit_configuration'
        config.mkdir(exist_ok=True)
        (config / (self.module + '.builds.json')).write_text(json.dumps([self.record]), encoding='utf-8')

    def plan(self):
        plan, relative = analysis.prepare_run(self.root, self.module, self.build_id)
        return plan, Path(plan['run_root']), relative

    def valid_results(self, folder):
        for name in analysis.RESULTS:
            (folder / name).write_text('Synthetic output\n', encoding='utf-8')
        (folder / 'table.csv').write_text('group,n\nA,5\n', encoding='utf-8')
        (folder / 'qc.json').write_text(json.dumps({'schema': 1, 'passed': True, 'status': 'passed', 'all_selected_outputs_completed': True, 'approved': False}), encoding='utf-8')
        plan = json.loads((folder / 'plan.json').read_text(encoding='utf-8'))
        identity = {key: plan[key] for key in ('module_id','build_id','run_id','bundle_sha256','engine_sha256')}
        (folder / 'output_manifest.json').write_text(json.dumps(dict(identity, schema=1, status='succeeded', approved=False, outputs=[{'id':'interpretation','status':'completed','files':['table.csv']} ])), encoding='utf-8')
        (folder / 'execution_status.csv').write_text('output,status,error\ninterpretation,completed,\n', encoding='utf-8')


    def test_every_explicit_r_dependency_is_installed_by_launcher_and_analysis_ci(self):
        # Inspect real executable calls, excluding comments that discuss optional
        # alternatives. A locally preinstalled package must not hide a missing
        # Check/Install dependency on a clean user's machine or a CI runner.
        def without_comments(text):
            result, quote, escaped = [], None, False
            for line in text.splitlines(keepends=True):
                for char in line:
                    if quote:
                        result.append(char)
                        if escaped:
                            escaped = False
                        elif char == chr(92):
                            escaped = True
                        elif char == quote:
                            quote = None
                    elif char == '#':
                        result.append('\n')
                        break
                    else:
                        result.append(char)
                        if char in ('"', "'", '`'):
                            quote = char
            return ''.join(result)
        sources = list((runtime.ROOT / 'r_tlf_pseudocode').rglob('*.R'))
        sources += [runtime.ROOT / 'toolkit_launcher/analysis_runner.R', runtime.ROOT / 'toolkit_launcher/analysis_monitor.R']
        dependencies = set()
        for source in sources:
            text = without_comments(source.read_text(encoding='utf-8'))
            dependencies.update(re.findall(r'\b([A-Za-z][A-Za-z0-9.]*)::', text))
            dependencies.update(re.findall(r'\b(?:library|require)\(\s*[\"\']?([A-Za-z][A-Za-z0-9.]*)', text))
            dependencies.update(re.findall(r'\brequireNamespace\(\s*[\"\']([A-Za-z][A-Za-z0-9.]*)[\"\']', text))
        base_packages = {'base','compiler','datasets','graphics','grDevices','grid','methods','parallel','splines','stats','stats4','tcltk','tools','utils'}
        needed = dependencies - base_packages
        self.assertIn('patchwork', needed)
        self.assertFalse(needed - set(jobs.ANALYSIS_PACKAGES), 'Missing launcher packages: ' + ', '.join(sorted(needed-set(jobs.ANALYSIS_PACKAGES))))
        workflow = (runtime.ROOT / '.github/workflows/package-check.yml').read_text(encoding='utf-8').split('  runnable-analysis:', 1)[1]
        installed = set(re.findall(r'any::([A-Za-z][A-Za-z0-9.]*)', workflow))
        self.assertFalse(needed-installed, 'Missing clean-CI packages: ' + ', '.join(sorted(needed-installed)))

    def test_revision_is_pinned_and_runs_never_reuse_a_results_folder(self):
        record, bundle = analysis.resolve_build(self.root, self.module, self.build_id)
        self.assertEqual(bundle, self.bundle)
        first, path, _ = self.plan()
        second, other, _ = self.plan()
        self.assertNotEqual(path, other)
        self.assertEqual(first['build_id'], second['build_id'])
        self.assertEqual(first['source_root'], str(runtime.ROOT))
        self.assertFalse(first['approved'])
        analysis.validate_plan(path / 'plan.json')
        self.assertEqual((self.bundle / 'inputs/result.csv').read_text(encoding='utf-8'), self.files['inputs/result.csv'])

    def test_input_manifest_and_extra_file_changes_are_rejected(self):
        path = self.bundle / 'inputs/result.csv'
        path.write_text('changed', encoding='utf-8')
        with self.assertRaises(runtime.InputError):
            analysis.resolve_build(self.root, self.module, self.build_id)
        self.manifest['files']['inputs/result.csv'] = hashlib.sha256(path.read_bytes()).hexdigest()
        (self.bundle / 'analysis_bundle.json').write_text(json.dumps(self.manifest), encoding='utf-8')
        with self.assertRaises(runtime.InputError):
            analysis.resolve_build(self.root, self.module, self.build_id)
        self.set_inventory()
        (self.bundle / 'extra.R').write_text('stop("unlisted")', encoding='utf-8')
        with self.assertRaises(runtime.InputError):
            analysis.resolve_build(self.root, self.module, self.build_id)
        (self.bundle / 'extra.R').unlink()
        (self.bundle / 'study-setup.zip').write_bytes(b'Optional transport archive')
        analysis.resolve_build(self.root, self.module, self.build_id)

    def test_wrong_project_module_ids_paths_and_symlinks_are_rejected(self):
        for module, ident in [('localmind', self.build_id), ([], self.build_id), (self.module, '../escape'), (self.module, 'setup-'+'b'*24)]:
            with self.subTest(module=module, ident=ident), self.assertRaises(runtime.InputError):
                analysis.resolve_build(self.root, module, ident)
        outsider = Path(self.temp.name) / 'outside.csv'
        outsider.write_text('secret', encoding='utf-8')
        path = self.bundle / 'inputs/result.csv'
        path.unlink()
        path.symlink_to(outsider)
        with self.assertRaises(runtime.InputError):
            analysis.resolve_build(self.root, self.module, self.build_id)

    def test_install_consent_and_fixed_argv_do_not_accept_commands(self):
        opts = {'module_id': self.module, 'build_id': self.build_id}
        for action, extra in [('analysis.check', {'command': 'echo bad'}), ('analysis.run', {'script': '/tmp/user.R'}), ('analysis.install', {})]:
            with self.subTest(action=action), self.assertRaises(jobs.JobError):
                jobs.build_plan(action, self.root, dict(opts, **extra))
        if shutil.which('Rscript'):
            plan = jobs.build_plan('analysis.check', self.root, opts)
            self.assertIn('--vanilla', plan['commands'][0]['argv'])
            self.assertNotIn('source(', plan['commands'][0]['argv'][-1])
            self.assertEqual(plan['outputs'], [])

    def test_exit_zero_is_not_a_success_without_complete_qc_and_outputs(self):
        _, folder, _ = self.plan()
        def fake_r(argv, cwd):
            self.assertEqual(argv[1], '--vanilla')
            self.assertEqual(argv[2], str(runtime.ROOT / 'toolkit_launcher/analysis_runner.R'))
            self.valid_results(folder)
            (folder / 'qc.json').write_text(json.dumps({'schema': 1, 'passed': False, 'status': 'failed', 'approved': False}), encoding='utf-8')
            return subprocess.CompletedProcess(argv, 0)
        with patch.object(analysis.subprocess, 'run', side_effect=fake_r):
            self.assertEqual(analysis.execute(folder / 'plan.json', 'fixed-Rscript'), 1)
        self.assertTrue((folder / 'execution_error.json').is_file())
        with zipfile.ZipFile(folder / 'results.zip') as archive:
            self.assertIn('execution_error.json', archive.namelist())
            self.assertNotIn('plan.json', archive.namelist())

    def test_success_requires_manifest_files_and_preserves_separate_attempts(self):
        _, folder, _ = self.plan()
        def fake_r(argv, cwd):
            self.valid_results(folder)
            return subprocess.CompletedProcess(argv, 0)
        with patch.object(analysis.subprocess, 'run', side_effect=fake_r):
            self.assertEqual(analysis.execute(folder / 'plan.json', 'fixed-Rscript'), 0)
        with zipfile.ZipFile(folder / 'results.zip') as archive:
            self.assertEqual(archive.read('table.csv'), (folder / 'table.csv').read_bytes())
        (folder / 'table.csv').unlink()
        with self.assertRaises(runtime.InputError):
            analysis.verify_results(folder)

    def test_changed_inputs_during_execution_fail_the_run(self):
        _, folder, _ = self.plan()
        def fake_r(argv, cwd):
            self.valid_results(folder)
            (self.bundle / 'inputs/result.csv').write_text('changed while running', encoding='utf-8')
            return subprocess.CompletedProcess(argv, 0)
        with patch.object(analysis.subprocess, 'run', side_effect=fake_r):
            self.assertEqual(analysis.execute(folder / 'plan.json', 'fixed-Rscript'), 1)
        self.assertIn('changed', (folder / 'execution_error.json').read_text(encoding='utf-8'))

    def test_diagnostic_archive_does_not_follow_output_symlinks(self):
        _, folder, _ = self.plan()
        outside = Path(self.temp.name) / 'private.txt'
        outside.write_text('private', encoding='utf-8')
        (folder / 'linked.txt').symlink_to(outside)
        with self.assertRaises(runtime.InputError):
            analysis.archive_results(folder)
        self.assertFalse((folder / 'results.zip').exists())
        self.assertFalse((folder / '.results.zip').exists())

    @unittest.skipUnless(shutil.which('Rscript'), 'R is not installed')
    def test_real_r_engine_exports_known_values_and_failure_diagnostics(self):
        rscript = shutil.which('Rscript')
        ready = subprocess.run([rscript, '--vanilla', '-e', 'quit(status=if(requireNamespace("jsonlite",quietly=TRUE)) 0 else 1)'], capture_output=True)
        if ready.returncode:
            self.skipTest('The real R runner requires jsonlite')
        # A tiny trusted fixture isolates the execution/export contract from the
        # separate statistical template suite. It does not require the TLF stack.
        self.module = 'r_tlf'
        self.bundle = self.root / 'template_outputs' / self.module / self.build_id
        self.bundle.mkdir(parents=True)
        files = {
            'setup_profile.json': json.dumps({'values': {'study_id': 'SYNTHETIC-ENGINE-QC', 'outputs': ['t_example']}}),
            'r/00_setup.R': 'fixture_value <- 7\n',
            'r/programs/t_example.R': 'print(data.frame(Arm=c("A","B"), N=c(fixture_value,11), Mean=c(2.5,3.75)))\n',
        }
        for name, value in files.items():
            path = self.bundle / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(value.encode('utf-8'))
        self.manifest = {'schema': 1, 'module_id': self.module, 'files': {name: hashlib.sha256(value.encode()).hexdigest() for name, value in files.items()}}
        self.set_inventory()
        _, success, _ = self.plan()
        self.assertEqual(analysis.execute(success / 'plan.json', rscript), 0)
        manifest = analysis.verify_results(success)
        self.assertEqual(manifest['outputs'][0]['id'], 't_example')
        with (success / 'outputs/t_example/component-01.csv').open(newline='', encoding='utf-8') as stream:
            self.assertEqual(list(csv.DictReader(stream)), [{'Arm':'A','N':'7','Mean':'2.5'}, {'Arm':'B','N':'11','Mean':'3.75'}])
        with zipfile.ZipFile(success / 'results.zip') as archive:
            self.assertIn('outputs/t_example/component-01.csv', archive.namelist())
            self.assertIn('analysis_report.html', archive.namelist())
            self.assertNotIn('plan.json', archive.namelist())
        program = self.bundle / 'r/programs/t_example.R'
        program.write_text('print(data.frame(ShouldNotSurvive=99)); stop("Deliberate synthetic failure")\n', encoding='utf-8')
        self.manifest['files']['r/programs/t_example.R'] = hashlib.sha256(program.read_bytes()).hexdigest()
        self.set_inventory()
        _, failed, _ = self.plan()
        self.assertNotEqual(success, failed)
        self.assertEqual(analysis.execute(failed / 'plan.json', rscript), 1)
        for name in analysis.RESULTS:
            self.assertTrue((failed / name).is_file(), name)
        self.assertFalse(json.loads((failed / 'qc.json').read_text())['passed'])
        self.assertIn('Deliberate synthetic failure', (failed / 'analysis_report.html').read_text())
        self.assertFalse((failed / 'outputs/t_example/component-01.csv').exists())
        with zipfile.ZipFile(failed / 'results.zip') as archive:
            self.assertIn('execution_error.json', archive.namelist())
            self.assertIn('outputs/t_example/program.log', archive.namelist())
        self.assertTrue((success / 'outputs/t_example/component-01.csv').is_file())

    def test_failed_supervised_job_exposes_diagnostics_and_restores_run_identity(self):
        source = make_source(Path(self.temp.name) / 'source')
        workspace = runtime.Workspace(Path(self.temp.name) / 'private', source)
        try:
            ident = workspace.create_project('Synthetic failure')['id']
            root = workspace.project(ident)
            diagnostic = 'run-qc.json'
            code = 'from pathlib import Path; Path("run-qc.json").write_text("failed"); raise SystemExit(2)'
            plan = {'commands': [{'argv': [sys.executable, '-c', code], 'cwd': str(root), 'env': {}}], 'outputs': ['not-present.csv'], 'failure_outputs': [diagnostic], 'output_labels': {diagnostic: 'QC report'}, 'analysis': {'module_id': self.module, 'build_id': self.build_id, 'run_id': 'run-'+'c'*32}}
            with patch.object(jobs, 'build_plan', return_value=plan):
                started = workspace.start(ident, 'analysis.run', {})
            result = wait_for_job(workspace, started['id'])
            self.assertEqual(result['status'], 'failed')
            self.assertEqual(result['outputs'], [{'path': diagnostic, 'label': 'Diagnostic: QC report'}])
            self.assertEqual(result['analysis']['build_id'], self.build_id)
            workspace.close()
            reopened = runtime.Workspace(Path(self.temp.name) / 'private', source)
            try:
                restored = reopened.job_state(started['id'])
                self.assertEqual(restored['analysis'], result['analysis'])
                self.assertEqual(restored['outputs'], result['outputs'])
            finally:
                reopened.close()
        finally:
            workspace.close()


if __name__ == '__main__':
    unittest.main()
