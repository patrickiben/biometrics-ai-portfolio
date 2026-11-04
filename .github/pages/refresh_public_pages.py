"""Overlay reviewed public copy and additive eCRF apps on the tested R release.

The pinned legacy runtime is immutable. Every new eCRF source is checked by the
separate native/browser gates before either publication route can deploy.
"""
from pathlib import Path, PurePosixPath
import argparse
import hashlib
import importlib.util
import json
import os
import shutil
import subprocess
import tarfile
import zipfile

ROOT = Path(__file__).resolve().parents[2]
BASE = 'a5f97927ff10fca93877351fb9f33444618aac90'
RUN = 41735220609
ARTIFACT = 13289245446
ARTIFACT_SHA = '20322eb263acdebf2dbd77c56c7c4f31b93362c22e762ad44588e0c2453ea68f'
REPO = 'patrickiben/biometrics-ai-portfolio'
PUBLIC = {
    'Biostatistics.html', 'START_HERE.html', 'README.md', 'TOOLKIT_SETUP.html',
    'capabilities.json', 'toolkit_launcher/catalog.json', 'toolkit_launcher/catalog.js',
    'browser_modules/README.md',
    'validation_harness/index.html', 'validation_harness/README.md',
    'validation_harness/EVIDENCE_LEDGER.md', 'validation_harness/ledger.json',
}
INFRA = {'.github/workflows/pages.yml', '.github/pages/refresh_public_pages.py',
         '.github/pages/smoke/smoke.mjs', 'toolkit_launcher/source_manifest.json',
         '.github/workflows/ecrf-qc.yml', '.github/workflows/package-check.yml',
         '.github/pages/build_site.R', 'package_qc.py',
         'browser_modules/tests/navigation-browser.cjs', 'tools/tests/test_ecrf_release.py'}
# Imported native launchers keep their original executable bit. No new or changed
# executable file is eligible; these exact Git blobs are part of the subtree import.
ECRF_EXECUTABLES = {
    'ecrf_pipeline/Launch Central statistical monitoring.command': '328c2f22b1124050c60a09fb94c8a405726cdb48',
    'ecrf_pipeline/Launch Coding QC assist.command': 'de405771c86cdd4b877a44cfd9188ff0e1d7ddfe',
    'ecrf_pipeline/Launch De-identification review assist.command': 'c3e20942f089f8566f48eed764c2fd846ad25bd6',
    'ecrf_pipeline/Launch Participant risk screening.command': '3a52d49940baa9f749e321f603cd4f4b59d22841',
    'ecrf_pipeline/run_anomaly.sh': '9af83aa92c3c9acaf80456e5f29017fb60d4addb',
    'ecrf_pipeline/run_meddra.sh': '9af79331f0a3f31724d9b2dc6d1c2f539bb0f6c0',
    'ecrf_pipeline/run_phi.sh': '7ff0697acd5ba245a1bb50aa9b2bfe5d938cb9da',
    'ecrf_pipeline/run_risk.sh': '2bf16fedcf9c30593e1da81b97c5b691595c3639',
}
DERIVED = {'browser-runtime/validation-sources.zip', 'browser-runtime/sources.json',
           'public-update-provenance.json'}


def sha(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def allowed_change(status, name, mode, blob):
    safe_member(name)
    if status not in {'A', 'M'}:
        return False
    additive = status == 'A' and name.startswith('ecrf_pipeline/')
    if not additive and name not in PUBLIC | INFRA:
        return False
    if mode == '100644':
        return True
    return additive and mode == '100755' and ECRF_EXECUTABLES.get(name) == blob


def assert_clean_source():
    modified = subprocess.check_output(['git', 'diff', '--name-only', '-z', 'HEAD'], cwd=ROOT)
    untracked = subprocess.check_output(['git', 'ls-files', '--others', '--exclude-standard', '-z'], cwd=ROOT).decode().split('\0')
    # _site is the workflow's generated deployment destination, excluded from
    # reviewed_files(). Tracked changes are never exempted, even under _site.
    if modified or any(name and not name.startswith('_site/') for name in untracked):
        raise ValueError('Publication requires a clean committed source checkout; commit reviewed files before refreshing.')


def changes():
    assert_clean_source()
    subprocess.run(['git', 'merge-base', '--is-ancestor', BASE, 'HEAD'], cwd=ROOT, check=True)
    raw = subprocess.check_output(['git', 'diff', '--name-status', '--no-renames', '-z', BASE, 'HEAD'], cwd=ROOT).decode()
    fields = raw.rstrip('\0').split('\0') if raw else []
    if len(fields) % 2:
        raise ValueError('Malformed source diff')
    result = {}
    for status, name in zip(fields[::2], fields[1::2]):
        entry = subprocess.check_output(['git', 'ls-tree', 'HEAD', '--', name], cwd=ROOT, text=True).split()
        if len(entry) < 3 or not allowed_change(status, name, entry[0], entry[2]):
            raise ValueError('Change requires the full build: ' + status + ' ' + name)
        if (ROOT / name).is_symlink() or not (ROOT / name).is_file():
            raise ValueError('Only regular checked-out files may be refreshed: ' + name)
        result[name] = status
    if not result or not any(name in PUBLIC or name.startswith('ecrf_pipeline/') for name in result):
        raise ValueError('No bounded public-page or additive eCRF update')
    return result


def verified_artifact():
    def api(path):
        return json.loads(subprocess.check_output(['gh', 'api', 'repos/' + REPO + path], text=True))
    run = api('/actions/runs/' + str(RUN))
    if not (run['repository']['full_name'] == REPO and run['head_sha'] == BASE
            and run['path'] == '.github/workflows/pages.yml' and run['head_branch'] == 'main'
            and run['status'] == 'completed' and run['conclusion'] == 'success'):
        raise ValueError('The pinned Pages run is not a successful main release')
    artifact = api('/actions/artifacts/' + str(ARTIFACT))
    if not (not artifact['expired'] and artifact['name'] == 'github-pages'
            and artifact['digest'] == 'sha256:' + ARTIFACT_SHA
            and artifact['workflow_run']['id'] == RUN and artifact['workflow_run']['head_sha'] == BASE):
        raise ValueError('The pinned Pages artifact is unavailable or does not match')
    return artifact


def download_artifact(destination):
    verified_artifact()
    with destination.open('wb') as stream:
        subprocess.run(['gh', 'api', f'repos/{REPO}/actions/artifacts/{ARTIFACT}/zip'], stdout=stream, check=True)
    if sha(destination) != ARTIFACT_SHA:
        raise ValueError('Downloaded artifact digest mismatch')


def safe_member(name):
    path = PurePosixPath(name)
    if path.is_absolute() or '..' in path.parts or '\\' in name:
        raise ValueError('Unsafe artifact member: ' + name)
    return path


def extract(archive, site):
    if sha(archive) != ARTIFACT_SHA:
        raise ValueError('Published artifact digest mismatch')
    with zipfile.ZipFile(archive) as z:
        if z.namelist() != ['artifact.tar'] or z.testzip():
            raise ValueError('Unexpected Pages artifact container')
        with z.open('artifact.tar') as stream, tarfile.open(fileobj=stream, mode='r|*') as tar:
            seen = set()
            for member in tar:
                name = safe_member(member.name)
                if str(name) in seen:
                    raise ValueError('Duplicate artifact member')
                seen.add(str(name))
                target = site / name
                if member.isdir():
                    target.mkdir(parents=True, exist_ok=True)
                elif member.isfile():
                    target.parent.mkdir(parents=True, exist_ok=True)
                    with target.open('wb') as out:
                        shutil.copyfileobj(tar.extractfile(member), out)
                else:
                    raise ValueError('Artifact links and special files are prohibited')


def inventory(site):
    return {p.relative_to(site).as_posix(): sha(p) for p in sorted(site.rglob('*')) if p.is_file()}


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, ROOT / path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


def refresh(archive, site):
    changed = changes()
    if site.exists():
        raise ValueError('Destination must be new')
    site.mkdir(parents=True)
    extract(archive, site)
    before = inventory(site)
    overlays = {name for name in changed if name in PUBLIC or name.startswith('ecrf_pipeline/')
                or (name in INFRA and not name.startswith('.github/'))}
    for name in overlays:
        target = site / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / name, target)
    assets = module('refresh_assets', '.github/pages/browser_assets.py')
    validation = module('refresh_validation', 'browser_modules/validation/browser_validation.py')
    names = assets.reviewed_files()
    validation.validate_source_manifest(ROOT, names)
    metadata_path = site / 'browser-runtime/sources.json'
    metadata = json.loads(metadata_path.read_text())
    old_members = metadata['validation']['files']
    new_record = assets.archive(site / 'browser-runtime/validation-sources.zip', names)
    member_changes = {p for p in old_members.keys() | new_record['files'].keys()
                      if old_members.get(p) != new_record['files'].get(p)}
    if member_changes != set(changed):
        raise ValueError('Reference archive changed outside the reviewed source diff: ' + repr(sorted(member_changes ^ set(changed))))
    metadata['validation'] = new_record
    metadata_path.write_text(json.dumps(metadata, indent=2) + '\n')
    after = inventory(site)
    modified = {p for p in before.keys() | after.keys() if before.get(p) != after.get(p)}
    allowed = overlays | DERIVED
    if modified - allowed or before.keys() - after.keys():
        raise ValueError('Unexpected deployed-file changes: ' + repr(sorted(modified - allowed)))
    provenance = {'base_commit': BASE, 'base_successful_pages_run': RUN,
                  'base_artifact_id': ARTIFACT, 'base_artifact_sha256': ARTIFACT_SHA,
                  'target_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
                  'source_changes': changed, 'reference_member_changes': sorted(member_changes),
                  'deployed_changes': {p: {'before': before.get(p), 'after': after.get(p)} for p in sorted(modified)},
                  'unchanged_deployed_files': sum(before.get(p) == value for p, value in after.items()),
                  'existing_runtime_and_scientific_files_unchanged': True,
                  'new_ecrf_files': {p: after[p] for p in sorted(modified) if p.startswith('ecrf_pipeline/')},
                  'new_ecrf_qc_required': 'Three native dependency variants, actual browser uploads/analyses/exports, navigation and source-archive integrity; required by Pages before deployment'}
    (site / 'public-update-provenance.json').write_text(json.dumps(provenance, indent=2) + '\n')
    print(json.dumps(provenance, indent=2))


def verify_reference(site):
    assert_clean_source()
    assets = module('reference_assets', '.github/pages/browser_assets.py')
    names = assets.reviewed_files()
    metadata = json.loads((site / 'browser-runtime/sources.json').read_text())
    for kind, wanted in [('validation', names), ('guided', [p for p in names if p in assets.GUIDED or any(p.startswith(d) for d in assets.GUIDED_DIRS)])]:
        record = metadata[kind]
        archive = site / 'browser-runtime' / (kind + '-sources.zip')
        if sha(archive) != record['sha256'] or archive.stat().st_size != record['bytes']:
            raise ValueError('Source archive digest/size mismatch: ' + kind)
        expected = {p: sha(ROOT / p) for p in wanted}
        if record['files'] != expected:
            raise ValueError('Source metadata differs from current reviewed checkout: ' + kind)
        with zipfile.ZipFile(archive) as z:
            if z.testzip() or len(z.namelist()) != len(set(z.namelist())) or set(z.namelist()) != set(expected):
                raise ValueError('Source archive members differ: ' + kind)
            for name in z.namelist():
                safe_member(name)
                if hashlib.sha256(z.read(name)).hexdigest() != expected[name]:
                    raise ValueError('Source archive member differs: ' + name)
    print('PASS: complete guided and validation archives match the reviewed checkout')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--classify', action='store_true')
    parser.add_argument('--archive', type=Path)
    parser.add_argument('--site', type=Path)
    parser.add_argument('--download', type=Path)
    parser.add_argument('--verify-site', type=Path)
    args = parser.parse_args()
    if args.classify:
        try:
            changes()
            verified_artifact()
            eligible = True
        except (ValueError, KeyError, OSError, subprocess.CalledProcessError):
            eligible = False
        value = 'true' if eligible else 'false'
        print('reuse=' + value)
        if os.environ.get('GITHUB_OUTPUT'):
            with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
                output.write('reuse=' + value + '\n')
    elif args.download:
        download_artifact(args.download)
    elif args.verify_site:
        verify_reference(args.verify_site)
    else:
        if not args.archive or not args.site:
            parser.error('--archive and --site are required')
        refresh(args.archive, args.site)
