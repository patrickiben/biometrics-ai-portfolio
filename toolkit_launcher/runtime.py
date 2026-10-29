"""Private local workspaces and supervised, allowlisted toolkit jobs (stdlib only)."""
from __future__ import annotations
import base64
import binascii
import csv
from datetime import datetime, timezone
import io
import json
import mimetypes
import os
from pathlib import Path, PurePosixPath
import re
import secrets
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time
import zipfile

ROOT = Path(__file__).resolve().parent.parent
MAX_FILE = 16 * 1024 * 1024
ID = re.compile(r'^[a-f0-9]{32}$')
PROCESS_STOP_GRACE = 5.0
WINDOWS_JOB_WRAPPER = """import json,subprocess,sys
argv=json.loads(sys.argv[1])
if sys.stdin.buffer.read(1)!=b'1':sys.exit(125)
sys.exit(subprocess.call(argv,stdin=subprocess.DEVNULL))
"""

class InputError(ValueError):
    pass


def timestamp():
    return datetime.now(timezone.utc).isoformat()


def atomic_json(path, data):
    path = Path(path)
    if path.is_symlink():
        raise InputError('Settings must use regular private files.')
    fd, temp = tempfile.mkstemp(prefix='.write-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as stream:
            json.dump(data, stream, indent=2, ensure_ascii=False)
            stream.write('\n')
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temp, path)
    finally:
        Path(temp).unlink(missing_ok=True)


def safe_path(root, name, exists=True):
    if not isinstance(name, str) or not name or '\\' in name or '\x00' in name:
        raise InputError('Choose a file inside this project.')
    parts = PurePosixPath(name)
    if parts.is_absolute() or any(p in ('..', '.') for p in parts.parts) or ':' in name:
        raise InputError('Choose a file inside this project.')
    current = root
    for part in parts.parts:
        current = current / part
        if current.is_symlink():
            raise InputError('Linked files are not available through the launcher.')
    if not current.resolve().is_relative_to(root.resolve()):
        raise InputError('Choose a file inside this project.')
    if exists and not current.is_file():
        raise InputError('This output is not available yet. Run the corresponding workflow first.')
    return current


def private_base(path):
    path = Path(path).expanduser()
    if path.is_symlink():
        raise InputError('Choose a regular private workspace folder.')
    path = path.resolve()
    if path == ROOT or path.is_relative_to(ROOT):
        raise InputError('Keep private projects outside the downloaded toolkit.')
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    if os.name != 'nt':
        path.chmod(0o700)
    return path


def source_files(root=ROOT):
    manifest = root / 'toolkit_launcher/source_manifest.json'
    data = json.loads(manifest.read_text(encoding='utf-8'))
    if data.get('schema') != 1 or not isinstance(data.get('files'), list):
        raise InputError('Download a complete toolkit; its source inventory is missing.')
    files = []
    for name in data['files']:
        path = safe_path(root, name)
        # A manifest cannot opt private runtime state into project copies.
        if any(p in {'.git', '.venv', 'node_modules', '__pycache__', '.biostat-toolkit', '.open-study-tracker', 'mail-preview', 'toolkit_configuration', 'input-backups', 'template_inputs', 'template_outputs', 'template_runs'} for p in Path(name).parts):
            raise InputError('The toolkit source inventory contains runtime state.')
        if path.name in {'config.json', 'project.json', 'launcher-settings.json', '.launcher-session.json', '.desktop-state.json', '.desktop.lock', '.toolkit.lock', 'launcher.log'} or re.search(r'\.(?:sqlite3?|db|eml)(?:-(?:wal|shm|journal))?$', name, re.I):
            raise InputError('The toolkit source inventory contains private state.')
        files.append((name, path))
    return files


def open_native(path):
    path = Path(path)
    if sys.platform == 'darwin':
        subprocess.Popen(['open', str(path)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    elif os.name == 'nt':
        os.startfile(str(path))
    else:
        subprocess.Popen(['xdg-open', str(path)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def free_port():
    with socket.socket() as probe:
        probe.bind(('127.0.0.1', 0))
        return probe.getsockname()[1]


def windows_job_api():
    """Declare the small native API surface used for owned process trees."""
    import ctypes
    from ctypes import wintypes
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    declarations = {
        'CreateJobObjectW': ([ctypes.c_void_p, wintypes.LPCWSTR], wintypes.HANDLE),
        'SetInformationJobObject': ([wintypes.HANDLE, ctypes.c_int, ctypes.c_void_p, wintypes.DWORD], wintypes.BOOL),
        'AssignProcessToJobObject': ([wintypes.HANDLE, wintypes.HANDLE], wintypes.BOOL),
        'TerminateJobObject': ([wintypes.HANDLE, wintypes.UINT], wintypes.BOOL),
        'QueryInformationJobObject': ([wintypes.HANDLE, ctypes.c_int, ctypes.c_void_p, wintypes.DWORD, ctypes.c_void_p], wintypes.BOOL),
        'CloseHandle': ([wintypes.HANDLE], wintypes.BOOL),
    }
    for name, (arguments, result) in declarations.items():
        getattr(kernel, name).argtypes = arguments
        getattr(kernel, name).restype = result
    return ctypes, wintypes, kernel


def assign_windows_job(process):
    ctypes, wintypes, kernel = windows_job_api()
    class BasicLimits(ctypes.Structure):
        _fields_ = [('ProcessTime', ctypes.c_int64), ('JobTime', ctypes.c_int64),
                    ('LimitFlags', wintypes.DWORD), ('MinWorkingSet', ctypes.c_size_t),
                    ('MaxWorkingSet', ctypes.c_size_t), ('ActiveProcessLimit', wintypes.DWORD),
                    ('Affinity', ctypes.c_size_t), ('PriorityClass', wintypes.DWORD), ('SchedulingClass', wintypes.DWORD)]
    class IOCounters(ctypes.Structure):
        _fields_ = [(name, ctypes.c_uint64) for name in ('ReadOperations', 'WriteOperations', 'OtherOperations', 'ReadBytes', 'WriteBytes', 'OtherBytes')]
    class ExtendedLimits(ctypes.Structure):
        _fields_ = [('Basic', BasicLimits), ('IO', IOCounters), ('ProcessMemory', ctypes.c_size_t),
                    ('JobMemory', ctypes.c_size_t), ('PeakProcessMemory', ctypes.c_size_t), ('PeakJobMemory', ctypes.c_size_t)]
    handle = kernel.CreateJobObjectW(None, None)
    if not handle:
        raise ctypes.WinError(ctypes.get_last_error())
    try:
        limits = ExtendedLimits()
        limits.Basic.LimitFlags = 0x00002000  # JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
        if not kernel.SetInformationJobObject(handle, 9, ctypes.byref(limits), ctypes.sizeof(limits)):
            raise ctypes.WinError(ctypes.get_last_error())
        if not kernel.AssignProcessToJobObject(handle, int(process._handle)):
            raise ctypes.WinError(ctypes.get_last_error())
        return handle
    except BaseException:
        kernel.CloseHandle(handle)
        raise


def terminate_windows_job(handle):
    ctypes, wintypes, kernel = windows_job_api()
    class Accounting(ctypes.Structure):
        _fields_ = [(name, ctypes.c_int64) for name in ('UserTime', 'KernelTime', 'PeriodUserTime', 'PeriodKernelTime')]
        _fields_ += [(name, wintypes.DWORD) for name in ('PageFaults', 'TotalProcesses', 'ActiveProcesses', 'TerminatedProcesses')]
    try:
        if not kernel.TerminateJobObject(handle, 1):
            raise ctypes.WinError(ctypes.get_last_error())
        deadline = time.monotonic() + 5
        while True:
            accounting = Accounting()
            if not kernel.QueryInformationJobObject(handle, 1, ctypes.byref(accounting), ctypes.sizeof(accounting), None):
                raise ctypes.WinError(ctypes.get_last_error())
            if accounting.ActiveProcesses == 0:
                return
            if time.monotonic() >= deadline:
                raise InputError('Windows could not finish stopping the task process tree.')
            time.sleep(.02)
    finally:
        # The handle is not inherited. Closing it also kills remaining members
        # if an API query fails, or if the supervisor itself exits unexpectedly.
        kernel.CloseHandle(handle)


def spawn_owned_process(argv, cwd, env, log):
    if os.name != 'nt':
        return subprocess.Popen(argv, cwd=cwd, env=env, stdin=subprocess.DEVNULL,
                                stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
    # The fixed wrapper cannot spawn the requested command before it receives
    # this supervisor's handshake. Assign it to a non-breakaway Job Object first.
    process = subprocess.Popen([sys.executable, '-c', WINDOWS_JOB_WRAPPER, json.dumps(argv)],
                               cwd=cwd, env=env, stdin=subprocess.PIPE, stdout=log,
                               stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NEW_PROCESS_GROUP)
    handle = None
    try:
        handle = assign_windows_job(process)
        process._toolkit_windows_job = handle
        process.stdin.write(b'1')
        process.stdin.flush()
        process.stdin.close()
        return process
    except BaseException:
        if process.stdin and not process.stdin.closed:
            process.stdin.close()
        try:
            if handle:
                terminate_windows_job(handle)
        finally:
            if process.poll() is None:
                process.kill()
            process.wait(timeout=5)
        raise InputError('Windows could not establish the private process tree; the task was stopped.') from None


class Workspace:
    def __init__(self, base, source=ROOT):
        self.base = private_base(base)
        self.source = source
        self.projects_dir = self.base / 'projects'
        self.projects_dir.mkdir(mode=0o700, exist_ok=True)
        self.job_dir = self.base / 'jobs'
        self.job_dir.mkdir(mode=0o700, exist_ok=True)
        for directory in (self.projects_dir, self.job_dir):
            if directory.is_symlink():
                raise InputError('Private workspace folders must not be symbolic links.')
        self.catalog = json.loads((source / 'toolkit_launcher/catalog.json').read_text(encoding='utf-8'))
        self.lock = threading.RLock()
        self.jobs = {}
        self.processes = {}
        self.threads = {}
        self.stops = {}
        self.closed = False
        self.runtime_cache = None
        self.runtime_checked = 0
        self.settings = {'r_path': '', 'quarto_path': ''}
        settings_file = self.base / 'launcher-settings.json'
        if settings_file.is_file():
            if settings_file.is_symlink():
                raise InputError('Settings must use regular private files.')
            self.settings.update(json.loads(settings_file.read_text(encoding='utf-8')))
        self._reload_jobs()

    def _reload_jobs(self):
        """Restore a bounded history; stale process IDs are never trusted or killed."""
        files = [p for p in self.job_dir.glob('*.json') if not p.is_symlink() and ID.fullmatch(p.stem)]
        for file in sorted(files, key=lambda p: p.stat().st_mtime, reverse=True)[:100]:
            try:
                if file.stat().st_size > 1024 * 1024:
                    continue
                record = json.loads(file.read_text(encoding='utf-8'))
                if not isinstance(record, dict) or record.get('id') != file.stem:
                    continue
                root = self.project(record.get('project_id'))
                required = ('id', 'project_id', 'action_id', 'module_id', 'label', 'status', 'started_at')
                if any(not isinstance(record.get(key), str) for key in required):
                    continue
                if record['status'] not in {'running', 'failed', 'succeeded', 'stopped'}:
                    continue
                outputs = []
                for output in record.get('outputs', [])[:2000]:
                    if not isinstance(output, dict) or not isinstance(output.get('path'), str):
                        continue
                    path = safe_path(root, output['path'], exists=False)
                    if path.is_file():
                        outputs.append({'path': output['path'], 'label': str(output.get('label', output['path']))[:300]})
                clean = {key: record[key] for key in required}
                clean.update(outputs=outputs, finished_at=record.get('finished_at'), error=record.get('error'),
                             long_running=bool(record.get('long_running')), url=None)
                if isinstance(record.get('analysis'), dict) and all(isinstance(record['analysis'].get(key), str) for key in ('module_id', 'build_id', 'run_id')):
                    clean['analysis'] = {key: record['analysis'][key] for key in ('module_id', 'build_id', 'run_id')}
                if clean['status'] == 'running':
                    clean.update(status='failed', finished_at=timestamp(),
                                 error='The launcher stopped before this task finished. Review its log, then run the action again when ready.')
                    atomic_json(file, clean)
                self.jobs[clean['id']] = clean
            except (ValueError, TypeError, KeyError, OSError):
                continue

    def adapter(self):
        from . import jobs
        return jobs

    def projects(self):
        result = []
        for directory in self.projects_dir.iterdir():
            if not ID.fullmatch(directory.name) or directory.is_symlink():
                continue
            file = directory / 'project.json'
            if file.is_file() and not file.is_symlink():
                try:
                    data = json.loads(file.read_text(encoding='utf-8'))
                    if data.get('id') == directory.name:
                        result.append({key: data[key] for key in ('id', 'name', 'created_at')})
                except (ValueError, KeyError, OSError):
                    continue
        return sorted(result, key=lambda item: item['created_at'], reverse=True)

    def project(self, ident):
        if not isinstance(ident, str) or not ID.fullmatch(ident):
            raise InputError('Choose a private project first.')
        parent = self.projects_dir / ident
        if parent.is_symlink() or (parent / 'workspace').is_symlink() or (parent / 'project.json').is_symlink() or not (parent / 'project.json').is_file():
            raise InputError('This project is unavailable.')
        try:
            metadata = parent / 'project.json'
            if metadata.stat().st_size > 16384 or json.loads(metadata.read_text(encoding='utf-8')).get('id') != ident:
                raise ValueError()
        except (ValueError, OSError, AttributeError):
            raise InputError('This project record does not match its folder.') from None
        root = parent / 'workspace'
        if not root.is_dir():
            raise InputError('This project is unavailable.')
        return root

    def create_project(self, name):
        if not isinstance(name, str) or not name.strip() or len(name.strip()) > 80 or any(ord(c) < 32 for c in name):
            raise InputError('Enter a project name of 1–80 characters.')
        files = source_files(self.source)
        ident = secrets.token_hex(16)
        parent = self.projects_dir / ident
        parent.mkdir(mode=0o700)
        root = parent / 'workspace'
        root.mkdir(mode=0o700)
        try:
            for relative, source in files:
                target = root / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(source, target)
                if source.stat().st_mode & 0o111:
                    target.chmod(0o700)
                else:
                    target.chmod(0o600)
            data = {'id': ident, 'name': name.strip(), 'created_at': timestamp(), 'source': 'Toolkit fictional examples; replace inputs for your intended use.'}
            atomic_json(parent / 'project.json', data)
            return data
        except BaseException:
            shutil.rmtree(parent)
            raise

    def runtime(self):
        with self.lock:
            if self.runtime_cache is None or time.monotonic() - self.runtime_checked > 30:
                self.runtime_cache = self.adapter().detect_runtimes(self.settings)
                self.runtime_checked = time.monotonic()
            return self.runtime_cache

    def state(self):
        with self.lock:
            records = [self.job_state(ident) for ident in self.jobs]
        return {'catalog': self.catalog, 'projects': self.projects(), 'projects_root': str(self.projects_dir),
                'runtime': self.runtime(), 'jobs': records, 'settings': self.settings,
                'actions': self.adapter().action_catalog(),
                'configuration': self.adapter().configuration_catalog()}

    def set_settings(self, data):
        if set(data) != {'r_path', 'quarto_path'} or any(not isinstance(v, str) or len(v) > 2048 for v in data.values()):
            raise InputError('Choose valid R and Quarto application paths.')
        for value in data.values():
            if value and (not Path(value).expanduser().is_file() or '\x00' in value):
                raise InputError('Choose an existing runtime executable.')
        with self.lock:
            self.settings = data
            atomic_json(self.base / 'launcher-settings.json', data)
            self.runtime_cache = None
        return {'saved': True}

    def upload(self, ident, name, encoded):
        root = self.project(ident)
        allowed = {item['path'] for module in self.catalog['modules'] for item in module.get('inputs', [])}
        if name not in allowed:
            raise InputError('Choose one of the module input files shown in the launcher.')
        target = safe_path(root, name)
        if not isinstance(encoded, str) or len(encoded) > MAX_FILE * 1.4:
            raise InputError('Choose an input file smaller than 16 MB.')
        try:
            content = base64.b64decode(encoded, validate=True)
            if not content or len(content) > MAX_FILE or b'\x00' in content:
                raise ValueError()
            text = content.decode('utf-8-sig')
            if target.suffix.lower() == '.csv':
                incoming = list(csv.reader(io.StringIO(text), strict=True))
                # Compare to the shipped contract. An optional column uploaded
                # yesterday must not become mandatory for tomorrow's file.
                with safe_path(self.source, name).open(encoding='utf-8-sig', newline='') as stream:
                    required = next(csv.reader(stream))
                if not incoming or len(incoming[0]) != len(set(incoming[0])) or not set(required) <= set(incoming[0]):
                    raise InputError('Keep the starter CSV column names. Download its template to compare.')
                if any(len(row) != len(incoming[0]) for row in incoming[1:]):
                    raise InputError('Every CSV row must have the same number of columns as its header.')
            elif target.suffix.lower() == '.json':
                json.loads(text, parse_constant=lambda _: (_ for _ in ()).throw(ValueError()))
            else:
                raise InputError('This input format is not supported by the uploader.')
        except (ValueError, UnicodeError, csv.Error, binascii.Error) as error:
            if isinstance(error, InputError):
                raise
            raise InputError('Choose a valid UTF-8 CSV or JSON input file.') from None
        with self.lock:
            if any(j['project_id'] == ident and j['status'] == 'running' for j in self.jobs.values()):
                raise InputError('Stop or finish this project’s current task before replacing inputs.')
            backup = root.parent / 'input-backups' / (secrets.token_hex(8) + '-' + target.name)
            if backup.parent.is_symlink():
                raise InputError('Input backups must stay in the private project folder.')
            backup.parent.mkdir(mode=0o700, exist_ok=True)
            shutil.copyfile(target, backup)
            backup.chmod(0o600)
            fd, temporary = tempfile.mkstemp(prefix='.input-', dir=target.parent)
            try:
                with os.fdopen(fd, 'wb') as stream:
                    stream.write(content)
                os.replace(temporary, target)
            finally:
                Path(temporary).unlink(missing_ok=True)
        return {'saved': True, 'path': name, 'backup': backup.name}

    def export_project(self, ident):
        root = self.project(ident)
        with self.lock:
            if any(j['project_id'] == ident and j['status'] == 'running' for j in self.jobs.values()):
                raise InputError('Stop or finish the current task before exporting a consistent project copy.')
            # Keep the lock through snapshot construction. Streaming the
            # completed ZIP can happen after the project is unlocked.
            file = tempfile.NamedTemporaryFile(prefix='toolkit-export-', suffix='.zip', dir=self.base, delete=False)
            file.close()
            try:
                with zipfile.ZipFile(file.name, 'w', zipfile.ZIP_DEFLATED) as archive:
                    for directory, dirs, names in os.walk(root, followlinks=False):
                        dirs[:] = [d for d in dirs if not (Path(directory) / d).is_symlink() and d not in {'.git', '.venv', 'node_modules', '__pycache__'}]
                        for name in names:
                            source = Path(directory) / name
                            if source.is_file() and not source.is_symlink():
                                archive.write(source, source.relative_to(root).as_posix())
                return Path(file.name)
            except BaseException:
                Path(file.name).unlink(missing_ok=True)
                raise

    def start(self, ident, action_id, options):
        root = self.project(ident)
        if not isinstance(action_id, str) or not isinstance(options, dict):
            raise InputError('Choose a supported module action.')
        with self.lock:
            if self.closed:
                raise InputError('This launcher is closing. Reopen Start Toolkit.')
            if any(j['project_id'] == ident and j['status'] == 'running' for j in self.jobs.values()):
                raise InputError('This project already has an active task. Stop it first, or use another project.')
            options = dict(options)
            if action_id.endswith('.run') and action_id.startswith('shiny.'):
                if 'port' in options:
                    raise InputError('The launcher chooses a private application port automatically.')
                options['port'] = free_port()
            if action_id in ('tracker.start', 'tracker.setup'):
                plan = {'commands': [{'argv': [sys.executable, str(root / 'open_tracker/desktop.py'), '--workspace', str(root.parent / 'tracker-data')], 'cwd': str(root), 'env': {}}], 'long_running': True, 'outputs': []}
                definition = {'module_id': 'tracker', 'label': 'Open shared tracker setup'}
            else:
                definition = self.adapter().action_catalog().get(action_id)
                if definition is None:
                    raise InputError('Choose a supported module action.')
                plan = self.adapter().build_plan(action_id, root, options=options, settings=self.settings)
            job_id = secrets.token_hex(16)
            record = {'id': job_id, 'action_id': action_id, 'module_id': definition.get('module_id', ''), 'project_id': ident,
                      'label': definition.get('label', action_id), 'status': 'running', 'started_at': timestamp(), 'finished_at': None,
                      'url': None, 'outputs': [], 'error': None, 'long_running': bool(plan.get('long_running'))}
            if plan.get('analysis'):
                record['analysis'] = dict(plan['analysis'])
            self.jobs[job_id] = record
            self.stops[job_id] = threading.Event()
            atomic_json(self.job_dir / (job_id + '.json'), record)
            thread = threading.Thread(target=self._run, args=(job_id, root, plan), daemon=True)
            self.threads[job_id] = thread
            thread.start()
            return dict(record, log='Starting…')

    def _run(self, ident, root, plan):
        record = self.jobs[ident]
        logfile = self.job_dir / (ident + '.log')
        error = None
        try:
            fd = os.open(logfile, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
            with os.fdopen(fd, 'w', encoding='utf-8') as log:
                for command in plan['commands']:
                    if self.stops[ident].is_set():
                        break
                    env = {k: v for k, v in os.environ.items() if not k.startswith(('TRACKER_', 'TOOLKIT_')) and k not in {'RENDER_EXTERNAL_URL', 'PORT'}}
                    env.update(command.get('env', {}))
                    env['PYTHONUNBUFFERED'] = '1'
                    env['PYTHONIOENCODING'] = 'utf-8'
                    env['PYTHONUTF8'] = '1'
                    process = spawn_owned_process(command['argv'], command['cwd'], env, log)
                    process._toolkit_stop_lock = threading.Lock()
                    process._toolkit_stopped = False
                    with self.lock:
                        self.processes[ident] = process
                    if self.stops[ident].is_set():
                        self._terminate(process)
                    if plan.get('url'):
                        # Do not present a URL as ready before the app accepts a connection.
                        from urllib.parse import urlsplit
                        target = urlsplit(plan['url'])
                        if target.scheme != 'http' or target.hostname != '127.0.0.1' or not target.port:
                            raise InputError('The module returned an invalid local address.')
                        while process.poll() is None and not self.stops[ident].is_set():
                            try:
                                with socket.create_connection(('127.0.0.1', target.port), timeout=.2):
                                    record['url'] = plan['url']
                                break
                            except OSError:
                                self.stops[ident].wait(.2)
                    code = process.wait()
                    # A completed leader can leave children behind. Reclaim this
                    # command's owned process group before the next command starts.
                    self._terminate(process)
                    if code and not self.stops[ident].is_set():
                        error = 'This task could not finish. Review its log and runtime checks.'
                        break
                if (not error and not self.stops[ident].is_set()) or plan.get('failure_outputs'):
                    diagnostic = bool(error or self.stops[ident].is_set())
                    for name in plan.get('failure_outputs' if diagnostic else 'outputs', []):
                        try:
                            path = safe_path(root, name, exists=False)
                        except InputError:
                            continue
                        paths = [path] if path.is_file() else sorted(path.rglob('*')) if path.is_dir() else []
                        for output in paths:
                            try:
                                relative = output.relative_to(root).as_posix()
                                safe_path(root, relative)
                            except (InputError, ValueError):
                                continue
                            if not any(item['path'] == relative for item in record['outputs']):
                                label = plan.get('output_labels', {}).get(relative, relative)
                                record['outputs'].append({'path': relative, 'label': ('Diagnostic: ' if diagnostic else '') + label})
                            if len(record['outputs']) >= 2000:
                                break
                        if len(record['outputs']) >= 2000:
                            break
        except Exception as exc:
            error = str(exc) if isinstance(exc, (InputError, ValueError)) else 'The runtime could not be started. Check its installation and the selected paths.'
        finally:
            with self.lock:
                process = self.processes.pop(ident, None)
            if process:
                try:
                    self._terminate(process)
                except Exception:
                    error = 'The launcher could not finish stopping this task. Review its local processes before running it again.'
            with self.lock:
                record.update(status='failed' if error else 'stopped' if self.stops[ident].is_set() else 'succeeded', error=error, finished_at=timestamp(), url=None)
                atomic_json(self.job_dir / (ident + '.json'), record)

    def job_state(self, ident):
        # A terminal state is visible only after its durable record is written.
        # The worker holds this same lock through record.update + atomic_json.
        with self.lock:
            if ident not in self.jobs:
                raise InputError('This task is unavailable.')
            record = dict(self.jobs[ident])
        file = self.job_dir / (ident + '.log')
        if file.is_symlink():
            raise InputError('Linked logs are not available through the launcher.')
        if file.is_file():
            with file.open('rb') as stream:
                stream.seek(max(0, file.stat().st_size - 60000))
                record['log'] = stream.read().decode('utf-8', errors='replace')
        else:
            record['log'] = 'Starting…'
        return record

    @staticmethod
    def _terminate(process):
        # Stop can race the worker's normal-exit/finally path. Only one caller
        # may clean a live-owned group; never signal the same PID again later.
        lock = getattr(process, '_toolkit_stop_lock', None)
        if lock is None:
            lock = process._toolkit_stop_lock = threading.Lock()
        with lock:
            if getattr(process, '_toolkit_stopped', False):
                return
            wait_deadline = None
            if os.name == 'nt':
                handle = getattr(process, '_toolkit_windows_job', None)
                if handle:
                    process._toolkit_windows_job = None
                    terminate_windows_job(handle)
                elif process.poll() is None:
                    process.kill()
            else:
                # All commands start a new session, making the leader PID the
                # owned group ID. A dead/reaped leader does not imply an empty
                # group, so use group existence through the whole grace period.
                def signal_group(sig, deadline):
                    while True:
                        try:
                            os.killpg(process.pid, sig)
                            return True
                        except ProcessLookupError:
                            return False
                        except PermissionError:
                            # XNU killpg1 can find a group while skipping its
                            # exiting/zombie members and return EPERM. Retry
                            # only on Darwin, requiring success or ESRCH; a
                            # persistent permission failure still propagates.
                            if sys.platform != 'darwin' or time.monotonic() >= deadline:
                                raise
                            process.poll()
                            time.sleep(min(.05, max(0, deadline - time.monotonic())))
                deadline = time.monotonic() + PROCESS_STOP_GRACE
                if signal_group(signal.SIGTERM, deadline):
                    while time.monotonic() < deadline:
                        process.poll()
                        if not signal_group(0, deadline):
                            break
                        time.sleep(min(.05, max(0, deadline - time.monotonic())))
                    else:
                        # A final-signal race uses the existing reap budget,
                        # rather than adding another termination grace period.
                        wait_deadline = time.monotonic() + 5
                        signal_group(signal.SIGKILL, wait_deadline)
            try:
                process.wait(timeout=5 if wait_deadline is None else max(0, wait_deadline - time.monotonic()))
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)
            process._toolkit_stopped = True

    def stop_job(self, ident):
        with self.lock:
            if ident not in self.jobs:
                raise InputError('This task is unavailable.')
            if self.jobs[ident]['status'] != 'running':
                return {'stopping': False, 'status': self.jobs[ident]['status']}
            self.stops[ident].set()
            process = self.processes.get(ident)
        if process:
            self._terminate(process)
        return {'stopping': True}

    def close(self):
        with self.lock:
            self.closed = True
            active = [ident for ident, job in self.jobs.items() if job['status'] == 'running']
            threads = list(self.threads.values())
        for ident in active:
            self.stop_job(ident)
        for thread in threads:
            thread.join(timeout=7)
