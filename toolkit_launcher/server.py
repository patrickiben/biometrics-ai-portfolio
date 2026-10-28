"""Loopback-only browser API. No workspace file or API is publicly served."""
import base64
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import mimetypes
import os
from pathlib import Path
import re
import secrets
import subprocess
import sys
import threading
from urllib.parse import parse_qs, urlsplit
from .runtime import Workspace, InputError, ROOT, MAX_FILE, safe_path, open_native

PUBLIC = 'https://patrickiben.github.io/biometrics-ai-portfolio/'


def picker(kind):
    if kind not in {'r', 'quarto'}:
        raise InputError('Choose R or Quarto.')
    # Tk must own its process's main thread, including on macOS. No user text
    # enters the program or a shell; the dialog returns a local path only.
    program = "import tkinter as t;from tkinter import filedialog as f;r=t.Tk();r.withdraw();r.attributes('-topmost',True);p=f.askopenfilename(title='Choose the installed runtime executable');print(p);r.destroy()"
    try:
        result = subprocess.run([sys.executable, '-c', program], capture_output=True, text=True, timeout=300)
        if result.returncode:
            raise InputError('This Python installation has no file picker. Paste the executable path in the settings field instead.')
        return result.stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        raise InputError('The file picker could not open. Paste the executable path in the settings field instead.') from None


class PortalServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = False


def create_server(workspace, token=None, port=0):
    token = token or secrets.token_urlsafe(40)
    if not isinstance(token, str) or len(token) < 32:
        raise ValueError('A strong private session token is required.')
    server = PortalServer(('127.0.0.1', port), handler_for(workspace, token))
    server.token = token
    server.workspace = workspace
    return server


def handler_for(workspace, token):
    class Handler(BaseHTTPRequestHandler):
        server_version = 'Toolkit'

        def log_message(self, *_args):
            pass

        def guard(self, auth=False):
            if self.headers.get('Host') != f'127.0.0.1:{self.server.server_port}':
                raise PermissionError('This address is not allowed.')
            origin = self.headers.get('Origin')
            if origin is not None and origin != f'http://127.0.0.1:{self.server.server_port}':
                raise PermissionError('Open this action from your local toolkit window.')
            if auth:
                supplied = self.headers.get('X-Toolkit-Token', '')
                if len(supplied) > 200 or not secrets.compare_digest(supplied.encode(), token.encode()):
                    raise PermissionError('This launcher session ended. Reopen Start Toolkit.')

        def send(self, content, status=200, content_type='application/json; charset=utf-8', filename=None, nonce=None):
            if isinstance(content, (dict, list)):
                content = json.dumps(content, ensure_ascii=False).encode()
            elif isinstance(content, str):
                content = content.encode()
            self.send_response(status)
            self.send_header('Content-Type', content_type)
            self.send_header('Cache-Control', 'no-store')
            self.send_header('Referrer-Policy', 'no-referrer')
            self.send_header('X-Content-Type-Options', 'nosniff')
            self.send_header('X-Frame-Options', 'DENY')
            scripts = "'self'" + (" 'nonce-" + nonce + "'" if nonce else '')
            self.send_header('Content-Security-Policy', "default-src 'none'; script-src " + scripts + "; style-src 'self' 'unsafe-inline'; connect-src 'self'; img-src 'self' data:; font-src 'self'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'")
            if filename:
                name = re.sub(r'[^a-zA-Z0-9_. -]', '_', filename)[:180]
                self.send_header('Content-Disposition', 'attachment; filename="' + name + '"')
            self.send_header('Content-Length', str(len(content)))
            self.end_headers()
            self.wfile.write(content)

        def send_file(self, path, filename=None, remove=False):
            try:
                with path.open('rb') as stream:
                    self.send_response(200)
                    self.send_header('Content-Type', mimetypes.guess_type(path.name)[0] or 'application/octet-stream')
                    self.send_header('Cache-Control', 'no-store')
                    self.send_header('X-Content-Type-Options', 'nosniff')
                    self.send_header('Content-Security-Policy', "default-src 'none'; sandbox")
                    name = re.sub(r'[^a-zA-Z0-9_. -]', '_', filename or path.name)[:180]
                    self.send_header('Content-Disposition', 'attachment; filename="' + name + '"')
                    self.send_header('Content-Length', str(path.stat().st_size))
                    self.end_headers()
                    while chunk := stream.read(65536):
                        self.wfile.write(chunk)
            finally:
                if remove:
                    path.unlink(missing_ok=True)

        def body(self, fields):
            if self.headers.get('Content-Type', '').split(';')[0] != 'application/json' or self.headers.get('Transfer-Encoding'):
                raise InputError('Use a JSON request from the toolkit form.')
            try:
                length = int(self.headers.get('Content-Length', '-1'))
            except ValueError:
                raise InputError('The request length is invalid.') from None
            if not 0 <= length <= MAX_FILE * 1.4 + 8192:
                raise InputError('This request is too large.')
            try:
                def unique(pairs):
                    result = {}
                    for key, value in pairs:
                        if key in result:
                            raise ValueError()
                        result[key] = value
                    return result
                data = json.loads(self.rfile.read(length).decode('utf-8'), object_pairs_hook=unique, parse_constant=lambda _: (_ for _ in ()).throw(ValueError()))
            except (ValueError, UnicodeError, RecursionError):
                raise InputError('The request is not valid JSON.') from None
            if not isinstance(data, dict) or set(data) != set(fields):
                raise InputError('The request contains missing or unknown fields.')
            return data

        def query(self, fields):
            values = parse_qs(urlsplit(self.path).query, keep_blank_values=True)
            if set(values) != set(fields) or any(len(v) != 1 for v in values.values()):
                raise InputError('The request contains missing or duplicate fields.')
            return {key: value[0] for key, value in values.items()}

        def route(self):
            path = urlsplit(self.path).path
            self.guard(auth=path.startswith('/api/'))
            if self.command == 'GET':
                if path in ('/', '/index.html', '/toolkit_launcher/index.html'):
                    nonce = secrets.token_urlsafe(24)
                    page = (ROOT / 'toolkit_launcher/index.html').read_text(encoding='utf-8')
                    page = re.sub(r'<html\b', '<html data-managed="true"', page, count=1)
                    page = re.sub(r'<script\b', lambda _: '<script nonce="' + nonce + '"', page)
                    page = page.replace('../GET_STARTED.html', PUBLIC + 'GET_STARTED.html').replace('../TOOLKIT_SETUP.html', PUBLIC + 'TOOLKIT_SETUP.html').replace('../START_HERE.html', PUBLIC + 'START_HERE.html')
                    self.send(page, content_type='text/html; charset=utf-8', nonce=nonce)
                elif path in ('/portal.js', '/catalog.js', '/toolkit_launcher/portal.js', '/toolkit_launcher/catalog.js', '/assets/theme/tokens.css'):
                    relative = 'assets/theme/tokens.css' if path.endswith('tokens.css') else 'toolkit_launcher/' + path.rsplit('/', 1)[1]
                    file = ROOT / relative
                    self.send(file.read_bytes(), content_type='text/css; charset=utf-8' if relative.endswith('.css') else 'text/javascript; charset=utf-8')
                elif path == '/favicon.ico':
                    self.send(b'', status=204)
                elif path == '/api/state':
                    if urlsplit(self.path).query:
                        values = self.query(('refresh',))
                        if values['refresh'] != '1':
                            raise InputError('Choose the refresh control in the toolkit.')
                        with workspace.lock:
                            workspace.runtime_cache = None
                    self.send(workspace.state())
                elif path == '/api/template-setup':
                    from . import guided_setup
                    query = self.query(('project_id', 'module_id'))
                    with workspace.lock:
                        self.send(guided_setup.state(workspace.project(query['project_id']), query['module_id']))
                elif path == '/api/configure':
                    query = self.query(('project_id', 'module_id'))
                    self.send(workspace.adapter().read_configuration(query['module_id'], workspace.project(query['project_id'])))
                elif path == '/api/files':
                    query = self.query(('project_id', 'path'))
                    self.send_file(safe_path(workspace.project(query['project_id']), query['path']))
                elif re.fullmatch(r'/api/projects/[a-f0-9]{32}/export', path):
                    ident = path.split('/')[3]
                    self.send_file(workspace.export_project(ident), filename='toolkit-project.zip', remove=True)
                elif re.fullmatch(r'/api/jobs/[a-f0-9]{32}', path):
                    self.send(workspace.job_state(path.rsplit('/', 1)[1]))
                else:
                    self.send({'error': 'This page is unavailable.'}, 404)
            elif self.command == 'POST':
                if path == '/api/projects':
                    data = self.body(('name',))
                    self.send(workspace.create_project(data['name']))
                elif path == '/api/actions':
                    data = self.body(('project_id', 'action_id', 'options'))
                    self.send(workspace.start(data['project_id'], data['action_id'], data['options']))
                elif path == '/api/settings':
                    self.send(workspace.set_settings(self.body(('r_path', 'quarto_path'))))
                elif path == '/api/pick-file':
                    self.send({'path': picker(self.body(('kind',))['kind'])})
                elif path == '/api/files':
                    data = self.body(('project_id', 'path', 'content_base64'))
                    self.send(workspace.upload(data['project_id'], data['path'], data['content_base64']))
                elif path == '/api/files/open':
                    data = self.body(('project_id', 'path'))
                    file = safe_path(workspace.project(data['project_id']), data['path'])
                    if file.suffix.lower() not in {'.html', '.pdf', '.csv', '.xlsx', '.docx', '.pptx', '.md', '.txt', '.json', '.r', '.sas', '.qmd', '.png', '.svg', '.rtf', '.rproj'}:
                        raise InputError('Download this file to choose how to open it.')
                    open_native(file)
                    self.send({'opened': True})
                elif path in ('/api/template-setup', '/api/template-input', '/api/template-profile'):
                    from . import guided_setup
                    fields = {'/api/template-setup': ('project_id', 'module_id', 'action', 'values'),
                              '/api/template-input': ('project_id', 'module_id', 'slot', 'filename', 'content_base64'),
                              '/api/template-profile': ('project_id', 'module_id', 'profile')}
                    data = self.body(fields[path])
                    with workspace.lock:
                        if workspace.closed:
                            raise InputError('This launcher is closing. Reopen Start Toolkit.')
                        root = workspace.project(data['project_id'])
                        if any(j['project_id'] == data['project_id'] and j['status'] == 'running' for j in workspace.jobs.values()):
                            raise InputError('Stop the project’s active task before changing its study setup.')
                        if path == '/api/template-setup':
                            result = guided_setup.act(root, data['module_id'], data['action'], data['values'])
                        elif path == '/api/template-input':
                            result = guided_setup.upload(root, data['module_id'], data['slot'], data['filename'], data['content_base64'])
                        else:
                            result = guided_setup.import_profile(root, data['module_id'], data['profile'])
                        self.send(result)
                elif path == '/api/configure':
                    data = self.body(('project_id', 'module_id', 'values'))
                    with workspace.lock:
                        if any(j['project_id'] == data['project_id'] and j['status'] == 'running' for j in workspace.jobs.values()):
                            raise InputError('Stop the project’s active task before changing its configuration.')
                        self.send(workspace.adapter().configure_project(data['module_id'], workspace.project(data['project_id']), data['values']))
                elif re.fullmatch(r'/api/projects/[a-f0-9]{32}/open', path):
                    self.body(())
                    open_native(workspace.project(path.split('/')[3]))
                    self.send({'opened': True})
                elif re.fullmatch(r'/api/jobs/[a-f0-9]{32}/stop', path):
                    self.body(())
                    self.send(workspace.stop_job(path.split('/')[3]))
                elif path == '/api/stop':
                    self.body(())
                    self.send({'stopping': True})
                    threading.Timer(.3, self.server.shutdown).start()
                else:
                    self.send({'error': 'This action is unavailable.'}, 404)
            else:
                self.send({'error': 'This method is not supported.'}, 405)

        def dispatch(self):
            try:
                self.route()
            except PermissionError as error:
                self.send({'error': str(error)}, 403)
            except (InputError, ValueError, KeyError, TypeError) as error:
                self.send({'error': str(error) if isinstance(error, (InputError, ValueError)) else 'Check the fields in this form.'}, 400)
            except (BrokenPipeError, ConnectionResetError):
                pass
            except Exception:
                self.send({'error': 'This action could not finish. Check folder access, installed runtimes and free disk space.'}, 500)

        do_GET = dispatch
        do_POST = dispatch
        do_OPTIONS = dispatch
        do_PUT = dispatch
        do_DELETE = dispatch
    return Handler
