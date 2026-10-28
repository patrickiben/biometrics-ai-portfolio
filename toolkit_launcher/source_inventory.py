#!/usr/bin/env python3
"""Generate/check the explicit public source inventory copied into private projects."""
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
FILE = ROOT / 'toolkit_launcher/source_manifest.json'


def inventory(root=ROOT):
    raw = subprocess.check_output(['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z'], cwd=root).decode()
    files = set(raw.split('\0')) - {''}
    files.add('toolkit_launcher/source_manifest.json')
    result = []
    for name in sorted(files):
        path = Path(name)
        if any(p in {'.git', '.venv', 'node_modules', '__pycache__', '.biostat-toolkit', '.open-study-tracker', 'mail-preview', '_site', 'toolkit_configuration', 'input-backups'} for p in path.parts):
            continue
        if path.name in {'config.json', 'project.json', 'launcher-settings.json', '.launcher-session.json', '.toolkit.lock', '.desktop-state.json', '.desktop.lock', 'launcher.log'} or re.search(r'\.(?:sqlite3?|db|eml)(?:-(?:wal|shm|journal))?$', name, re.I):
            continue
        if (root / path).is_symlink():
            raise ValueError('Source inventory refuses symbolic links: ' + name)
        if (root / path).is_file() or name == 'toolkit_launcher/source_manifest.json':
            result.append(name)
    return {'schema': 1, 'description': 'Explicit public source files for private project copies. Runtime state is never included.', 'files': result}


if __name__ == '__main__':
    text = json.dumps(inventory(), indent=2) + '\n'
    if '--check' in sys.argv:
        if not FILE.exists() or FILE.read_text(encoding='utf-8') != text:
            print('Source inventory is out of date. Run python3 toolkit_launcher/source_inventory.py.')
            sys.exit(1)
        print('Private-project source inventory is current.')
    else:
        FILE.write_text(text, encoding='utf-8')
        print('Updated private-project source inventory.')
