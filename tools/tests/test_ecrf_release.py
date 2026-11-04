"""Adversarial checks for additive eCRF publication over the pinned R release."""
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import tarfile
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
import zipfile

ROOT = Path(__file__).resolve().parents[2]


def load(name, relative):
    spec = importlib.util.spec_from_file_location(name, ROOT / relative)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


P = load('ecrf_refresh_under_test', '.github/pages/refresh_public_pages.py')
A = load('ecrf_archive_under_test', '.github/pages/browser_assets.py')


class ReleaseBoundary(unittest.TestCase):
    def test_only_additive_ecrf_and_exact_public_paths_are_eligible(self):
        self.assertTrue(P.allowed_change('A', 'ecrf_pipeline/risk_app.py', '100644', 'x'))
        self.assertTrue(P.allowed_change('M', 'toolkit_launcher/catalog.json', '100644', 'x'))
        for status, name in [('M', 'ecrf_pipeline/risk_app.py'), ('D', 'README.md'),
                             ('A', 'apps/methods/app.R'), ('M', 'browser_modules/methods/methods.R'),
                             ('M', 'vaccine/analysis.R'), ('M', 'toolkit_launcher/analysis_runner.R'),
                             ('M', 'browser_modules/workbench/runtime.mjs'), ('M', 'apps/_shared/launch.js'),
                             ('M', 'build_pages.py'), ('M', 'random.html')]:
            with self.subTest(status=status, name=name):
                self.assertFalse(P.allowed_change(status, name, '100644', 'x'))

    def test_executable_and_link_modes_cannot_expand_the_boundary(self):
        for name in ['ecrf_pipeline/new.sh', 'ecrf_pipeline/risk_app.py', 'README.md']:
            for mode in ['100755', '120000', '160000']:
                self.assertFalse(P.allowed_change('A', name, mode, 'x'))
        for name, blob in P.ECRF_EXECUTABLES.items():
            self.assertTrue(P.allowed_change('A', name, '100755', blob))
            self.assertFalse(P.allowed_change('A', name, '100755', 'altered'))
            self.assertFalse(P.allowed_change('M', name, '100755', blob))

    def test_path_traversal_and_absolute_paths_are_rejected(self):
        for name in ['/tmp/escape', '../escape', 'ecrf_pipeline/../../escape', 'ecrf_pipeline\\escape']:
            with self.subTest(name=name), self.assertRaises(ValueError):
                P.safe_member(name)

    def tar_container(self, root, members):
        tar_bytes = io.BytesIO()
        with tarfile.open(fileobj=tar_bytes, mode='w') as tar:
            for name, kind in members:
                info = tarfile.TarInfo(name)
                if kind == 'file':
                    info.size = 1; tar.addfile(info, io.BytesIO(b'x'))
                else:
                    info.type = kind; info.linkname = 'elsewhere'; tar.addfile(info)
        archive = root / 'artifact.zip'
        with zipfile.ZipFile(archive, 'w') as z:
            z.writestr('artifact.tar', tar_bytes.getvalue())
        return archive

    def test_extractor_rejects_links_special_files_and_normalized_duplicates(self):
        for members in [[('link', tarfile.SYMTYPE)], [('link', tarfile.LNKTYPE)],
                        [('pipe', tarfile.FIFOTYPE)], [('../escape', 'file')],
                        [('ok', 'file'), ('./ok', 'file')]]:
            with self.subTest(members=members), tempfile.TemporaryDirectory() as directory:
                root = Path(directory); archive = self.tar_container(root, members)
                with patch.object(P, 'ARTIFACT_SHA', P.sha(archive)), self.assertRaises(ValueError):
                    P.extract(archive, root / 'site')

    def test_digest_is_checked_before_extraction(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); archive = self.tar_container(root, [('file', 'file')])
            with patch.object(P, 'ARTIFACT_SHA', 'wrong'), self.assertRaisesRegex(ValueError, 'digest'):
                P.extract(archive, root / 'site')
            self.assertFalse((root / 'site').exists())

    def test_artifact_metadata_and_successful_source_run_are_both_required(self):
        run = {'repository': {'full_name': P.REPO}, 'head_sha': P.BASE,
               'path': '.github/workflows/pages.yml', 'head_branch': 'main',
               'status': 'completed', 'conclusion': 'success'}
        artifact = {'expired': False, 'name': 'github-pages', 'digest': 'sha256:' + P.ARTIFACT_SHA,
                    'workflow_run': {'id': P.RUN, 'head_sha': P.BASE}}
        def invoke(r, a):
            with patch.object(P.subprocess, 'check_output', side_effect=[json.dumps(r), json.dumps(a)]):
                return P.verified_artifact()
        self.assertEqual(invoke(run, artifact), artifact)
        for key, value in [('expired', True), ('digest', 'wrong'), ('name', 'other')]:
            with self.subTest(key=key), self.assertRaises(ValueError):
                invoke(run, dict(artifact, **{key: value}))
        for key, value in [('conclusion', 'failure'), ('head_branch', 'unreviewed'), ('head_sha', 'different')]:
            with self.subTest(key=key), self.assertRaises(ValueError):
                invoke(dict(run, **{key: value}), artifact)


class CompleteOverlay(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='ecrf-overlay-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve() / 'source'; self.root.mkdir()
        self.git('init', '-q')
        (self.root / 'README.md').write_text('Original public guide\n')
        (self.root / 'legacy.R').write_text('unchanged scientific source\n')
        self.commit()
        self.base = self.git('rev-parse', 'HEAD').strip()
        self.patch_root = patch.object(P, 'ROOT', self.root); self.patch_root.start(); self.addCleanup(self.patch_root.stop)
        self.patch_base = patch.object(P, 'BASE', self.base); self.patch_base.start(); self.addCleanup(self.patch_base.stop)
        self.patch_assets = patch.object(A, 'ROOT', self.root); self.patch_assets.start(); self.addCleanup(self.patch_assets.stop)
        self.patch_module = patch.object(P, 'module', side_effect=lambda name, path: A if 'assets' in name else SimpleNamespace(validate_source_manifest=lambda *args: None))
        self.patch_module.start(); self.addCleanup(self.patch_module.stop)
        oldsite = Path(self.temp.name) / 'base-site'; (oldsite / 'browser-runtime').mkdir(parents=True)
        (oldsite / 'README.md').write_text('Original public guide\n')
        (oldsite / 'shinylive/webr').mkdir(parents=True)
        (oldsite / 'shinylive/webr/R.wasm').write_bytes(b'proven runtime bytes')
        (oldsite / 'apps/methods').mkdir(parents=True)
        (oldsite / 'apps/methods/app.json').write_bytes(b'proven app bundle')
        self.metadata = {'schema': 1, 'validation': A.archive(oldsite / 'browser-runtime/validation-sources.zip', A.reviewed_files()),
                         'guided': A.archive(oldsite / 'browser-runtime/guided-sources.zip', []),
                         'python': {'immutable': 'runtime provenance'}, 'r_compatibility': {'immutable': 'compat provenance'}}
        (oldsite / 'browser-runtime/sources.json').write_text(json.dumps(self.metadata, indent=2)+'\n')
        buf = io.BytesIO()
        with tarfile.open(fileobj=buf, mode='w') as tar:
            for file in sorted(oldsite.rglob('*')):
                if file.is_file(): tar.add(file, arcname=file.relative_to(oldsite).as_posix())
        self.archive = Path(self.temp.name) / 'pages.zip'
        with zipfile.ZipFile(self.archive, 'w') as z: z.writestr('artifact.tar', buf.getvalue())
        self.patch_sha = patch.object(P, 'ARTIFACT_SHA', P.sha(self.archive)); self.patch_sha.start(); self.addCleanup(self.patch_sha.stop)
        (self.root / 'README.md').write_text('New public guide\n')
        (self.root / 'ecrf_pipeline').mkdir()
        (self.root / 'ecrf_pipeline/risk_app.py').write_text('new separately tested eCRF program\n')
        self.commit()
        self.site = Path(self.temp.name) / 'refreshed-site'

    def git(self, *args):
        return subprocess.check_output(['git', *args], cwd=self.root, text=True)

    def commit(self):
        self.git('add', '.')
        self.git('-c', 'user.name=QC', '-c', 'user.email=qc@example.invalid', 'commit', '-qm', 'fixture')

    def test_real_git_diff_and_full_overlay_preserve_legacy_bytes(self):
        P.refresh(self.archive, self.site)
        self.assertEqual((self.site / 'shinylive/webr/R.wasm').read_bytes(), b'proven runtime bytes')
        self.assertEqual((self.site / 'apps/methods/app.json').read_bytes(), b'proven app bundle')
        self.assertEqual((self.site / 'ecrf_pipeline/risk_app.py').read_bytes(), (self.root / 'ecrf_pipeline/risk_app.py').read_bytes())
        metadata = json.loads((self.site / 'browser-runtime/sources.json').read_text())
        self.assertEqual({k:v for k,v in metadata.items() if k!='validation'}, {k:v for k,v in self.metadata.items() if k!='validation'})
        P.verify_reference(self.site)
        evidence = json.loads((self.site / 'public-update-provenance.json').read_text())
        self.assertTrue(evidence['existing_runtime_and_scientific_files_unchanged'])
        self.assertEqual(set(evidence['new_ecrf_files']), {'ecrf_pipeline/risk_app.py'})

    def test_changed_existing_scientific_source_requires_full_build(self):
        (self.root / 'legacy.R').write_text('changed computation\n'); self.commit()
        with self.assertRaisesRegex(ValueError, 'full build'): P.changes()

    def test_uncommitted_source_drift_is_not_hidden_in_archive(self):
        (self.root / 'legacy.R').write_text('unexpected working copy change\n')
        with self.assertRaisesRegex(ValueError, 'clean committed source'): P.refresh(self.archive, self.site)

    def test_uncommitted_change_to_allowed_path_cannot_claim_head_provenance(self):
        (self.root / 'README.md').write_text('Uncommitted but allowlisted wording\n')
        with self.assertRaisesRegex(ValueError, 'clean committed source'):
            P.refresh(self.archive, self.site)
        self.assertFalse(self.site.exists())

    def test_only_generated_site_output_is_excluded_from_clean_source_check(self):
        (self.root / '_site').mkdir()
        (self.root / '_site/index.html').write_text('generated output')
        P.assert_clean_source()
        self.assertNotIn('_site/index.html', A.reviewed_files())

    def test_untracked_file_cannot_enter_reference_snapshot(self):
        (self.root / 'ecrf_pipeline/unreviewed.py').write_text('uncommitted program\n')
        with self.assertRaisesRegex(ValueError, 'clean committed source'):
            P.refresh(self.archive, self.site)

    def test_full_inventory_catches_runtime_mutation_during_overlay(self):
        original = A.archive
        def mutate(destination, names):
            result = original(destination, names)
            (self.site / 'shinylive/webr/R.wasm').write_bytes(b'unexpected runtime replacement')
            return result
        with patch.object(A, 'archive', side_effect=mutate), self.assertRaisesRegex(ValueError, 'Unexpected deployed-file changes'):
            P.refresh(self.archive, self.site)

    def test_reference_check_rejects_tampered_member_and_record(self):
        P.refresh(self.archive, self.site)
        archive = self.site / 'browser-runtime/validation-sources.zip'
        with zipfile.ZipFile(archive, 'a') as z: z.writestr('unexpected.py', 'extra')
        with self.assertRaisesRegex(ValueError, 'digest/size'): P.verify_reference(self.site)


if __name__ == '__main__':
    unittest.main(verbosity=2)
