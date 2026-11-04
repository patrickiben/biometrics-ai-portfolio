"""Publish a bounded documentation update over the fully tested release artifact."""
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
    'Biostatistics.html', 'START_HERE.html', 'README.md',
    'validation_harness/index.html', 'validation_harness/README.md',
    'validation_harness/EVIDENCE_LEDGER.md', 'validation_harness/ledger.json',
}
INFRA = {'.github/workflows/pages.yml', '.github/pages/refresh_public_pages.py',
         '.github/pages/smoke/smoke.mjs', 'toolkit_launcher/source_manifest.json'}
DERIVED = {'browser-runtime/validation-sources.zip', 'browser-runtime/sources.json',
           'public-update-provenance.json'}


def sha(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def changes():
    subprocess.run(['git', 'merge-base', '--is-ancestor', BASE, 'HEAD'], cwd=ROOT, check=True)
    rows = subprocess.check_output(['git', 'diff', '--name-status', '--no-renames', BASE, 'HEAD'], cwd=ROOT, text=True).splitlines()
    result = {}
    for row in rows:
        status, name = row.split('\t')
        if status not in {'A', 'M'} or name not in PUBLIC | INFRA:
            raise ValueError('Change requires the full build: ' + row)
        mode = subprocess.check_output(['git', 'ls-files', '-s', '--', name], cwd=ROOT, text=True).split()[0]
        if mode != '100644' or (ROOT / name).is_symlink():
            raise ValueError('Only regular non-executable source files may be refreshed: ' + name)
        result[name] = status
    if not result or not (result.keys() & PUBLIC):
        raise ValueError('No bounded public-page update')
    return result


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
    for name in changed.keys() & PUBLIC:
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
    allowed = (changed.keys() & PUBLIC) | DERIVED
    if modified - allowed or before.keys() - after.keys():
        raise ValueError('Unexpected deployed-file changes: ' + repr(sorted(modified - allowed)))
    provenance = {'base_commit': BASE, 'base_successful_pages_run': RUN,
                  'base_artifact_id': ARTIFACT, 'base_artifact_sha256': ARTIFACT_SHA,
                  'target_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
                  'source_changes': changed, 'reference_member_changes': sorted(member_changes),
                  'deployed_changes': {p: {'before': before.get(p), 'after': after.get(p)} for p in sorted(modified)},
                  'unchanged_deployed_files': sum(before.get(p) == value for p, value in after.items()),
                  'runtime_and_scientific_files_unchanged': True}
    (site / 'public-update-provenance.json').write_text(json.dumps(provenance, indent=2) + '\n')
    print(json.dumps(provenance, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--classify', action='store_true')
    parser.add_argument('--archive', type=Path)
    parser.add_argument('--site', type=Path)
    args = parser.parse_args()
    if args.classify:
        try:
            changes()
            artifact = json.loads(subprocess.check_output(
                ['gh', 'api', f'repos/{REPO}/actions/artifacts/{ARTIFACT}'], text=True))
            eligible = (not artifact['expired'] and artifact['name'] == 'github-pages'
                        and artifact['digest'] == 'sha256:' + ARTIFACT_SHA
                        and artifact['workflow_run']['id'] == RUN
                        and artifact['workflow_run']['head_sha'] == BASE)
        except (ValueError, KeyError, subprocess.CalledProcessError):
            eligible = False
        value = 'true' if eligible else 'false'
        print('reuse=' + value)
        if os.environ.get('GITHUB_OUTPUT'):
            with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
                output.write('reuse=' + value + '\n')
    else:
        if not args.archive or not args.site:
            parser.error('--archive and --site are required')
        refresh(args.archive, args.site)
