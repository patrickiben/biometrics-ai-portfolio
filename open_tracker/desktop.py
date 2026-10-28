#!/usr/bin/env python3
"""Double-click launcher: prepare dependencies and open the local browser UI.

The loading page uses only Python's standard library. Secrets stay in private
workspace state, the child environment and URL fragments, never command lines.
"""
import argparse
from contextlib import contextmanager
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import re
import secrets
import signal
import socket
import subprocess
import sys
import threading
import time
from urllib.request import Request, ProxyHandler, build_opener
import webbrowser

import manage

HERE = Path(__file__).resolve().parent

LOADING_PAGE = r'''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Open Study Tracker · Start</title>
<style>:root{color-scheme:light;--bg:#f3f6fa;--card:#fff;--ink:#14202c;--muted:#46566b;--line:#ccd7e3;--accent:#087d77}html[data-theme=dark]{color-scheme:dark;--bg:#101b29;--card:#172638;--ink:#edf3fa;--muted:#b4c4d5;--line:#3e526a;--accent:#57d9c4}*{box-sizing:border-box}[hidden]{display:none!important}body{margin:0;background:var(--bg);color:var(--ink);font:16px/1.55 system-ui,sans-serif}header{display:flex;justify-content:space-between;align-items:center;padding:20px;border-bottom:1px solid var(--line);gap:20px}.brand{font:700 13px ui-monospace,monospace;letter-spacing:1px}main{max-width:700px;margin:9vh auto;padding:28px;background:var(--card);border:1px solid var(--line);border-radius:12px}h1{font-size:32px;line-height:1.15}p{color:var(--muted)}button,a{font:inherit}button,.button{display:inline-block;padding:9px 15px;border:1px solid var(--line);border-radius:6px;background:var(--card);color:var(--ink);cursor:pointer;text-decoration:none}.button{background:var(--accent);color:var(--bg);font-weight:700}code{overflow-wrap:anywhere}#status{border-left:3px solid var(--accent);padding:12px 16px;background:var(--bg)}@media(max-width:720px){main{margin:30px 12px;padding:22px}h1{font-size:27px}}</style></head><body><header><span class="brand">OPEN STUDY TRACKER</span><button id="theme" type="button" aria-label="Switch light and dark appearance">◐ Theme</button></header><main><p class="brand">YOUR WORKSPACE</p><h1>Getting things ready.</h1><p>Setup opens in your browser. Your accounts, settings and data stay in your private workspace.</p><p id="status" role="status" aria-live="polite">Checking the local launcher…</p><p id="detail"></p><a id="open" class="button" hidden>Open workspace</a></main>
<script>
(()=>{const root=document.documentElement;let theme;try{theme=localStorage.getItem('bp-theme')}catch{}root.dataset.theme=theme==='light'||theme==='dark'?theme:matchMedia('(prefers-color-scheme: dark)').matches?'dark':'light';document.getElementById('theme').onclick=()=>{root.dataset.theme=root.dataset.theme==='dark'?'light':'dark';try{localStorage.setItem('bp-theme',root.dataset.theme)}catch{}};
const token=new URLSearchParams(location.hash.slice(1)).get('launch-token');history.replaceState(null,'',location.pathname);const status=document.getElementById('status'),detail=document.getElementById('detail'),link=document.getElementById('open');let stopped=false;
async function poll(){try{if(!token)throw Error('Reopen Start Tracker to return to your workspace.');const r=await fetch('/status',{headers:{'X-Launch-Token':token},cache:'no-store'});if(!r.ok)throw Error('Reopen Start Tracker to reconnect.');const s=await r.json();status.textContent=s.message;detail.textContent=s.detail||'';if(s.url){const u=new URL(s.url);if(u.hostname!=='127.0.0.1'||u.protocol!=='http:')throw Error('Unexpected local address. Close this page and reopen Start Tracker.');link.href=u.href;link.hidden=false;stopped=true;location.replace(u.href)}else if(s.failed)stopped=true}catch(e){status.textContent=e.message;stopped=true}if(!stopped)setTimeout(poll,700)}poll()})();
</script></body></html>'''


def loading_page(nonce):
    try:
        tokens = (HERE.parent / 'assets/theme/tokens.css').read_text()
    except OSError:
        # The self-contained tracker also carries the exact generated tokens.
        template = (HERE / 'index.html').read_text()
        match = re.search(r'<style id="tracker-theme-tokens">(.*?)</style>', template, re.S)
        if not match:
            raise manage.SetupError('The toolkit theme files are missing. Download a complete checkout and try again.')
        tokens = match[1]
    page = re.sub(r':root\{color-scheme:light;.*?\}\*\{', lambda _m: tokens + '\n*{', LOADING_PAGE, count=1, flags=re.S)
    return (page.replace('var(--card)', 'var(--surface)')
            .replace('16px/1.55 system-ui,sans-serif', '16px/1.55 var(--sans)')
            .replace('13px ui-monospace,monospace', '13px var(--mono)')
            .replace('color:var(--bg);font-weight:700', 'color:var(--on-accent);font-weight:700')
            .replace('<script>', '<script nonce="' + nonce + '">'))


def notify(message):
    """Display an actionable native error; never include child output or secrets."""
    try:
        if sys.platform == 'darwin':
            script = 'on run argv\ndisplay dialog (item 1 of argv) with title "Open Study Tracker" buttons {"OK"} default button "OK"\nend run'
            subprocess.run(['osascript', '-e', script, message], check=False)
        elif os.name == 'nt':
            import ctypes
            ctypes.windll.user32.MessageBoxW(0, message, 'Open Study Tracker', 0)
        else:
            print(message, file=sys.stderr)
    except OSError:
        print(message, file=sys.stderr)


@contextmanager
def workspace_lock(workspace):
    path = workspace / '.desktop.lock'
    if path.is_symlink():
        raise manage.SetupError('The launcher lock must be a regular private file.')
    descriptor = os.open(path, os.O_RDWR | os.O_CREAT, 0o600)
    stream = os.fdopen(descriptor, 'r+b')
    locked = False
    try:
        if os.name == 'nt':
            import msvcrt
            if path.stat().st_size == 0:
                stream.write(b'0')
                stream.flush()
            stream.seek(0)
            try:
                msvcrt.locking(stream.fileno(), msvcrt.LK_NBLCK, 1)
                locked = True
            except OSError:
                pass
        else:
            import fcntl
            try:
                fcntl.flock(stream.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                locked = True
            except BlockingIOError:
                pass
        yield locked
    finally:
        if locked:
            if os.name == 'nt':
                stream.seek(0)
                msvcrt.locking(stream.fileno(), msvcrt.LK_UNLCK, 1)
            else:
                fcntl.flock(stream.fileno(), fcntl.LOCK_UN)
        stream.close()


def private_write(path, value):
    if path.is_symlink():
        raise manage.SetupError('The launcher state must be a regular private file.')
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    if os.name != 'nt':
        os.fchmod(descriptor, 0o600)
    with os.fdopen(descriptor, 'w') as stream:
        json.dump(value, stream)


def opener():
    return build_opener(ProxyHandler({}))


def reopen(workspace):
    """Reopen the live launcher's authenticated loading page, not another worker."""
    try:
        path = workspace / '.desktop-state.json'
        if path.is_symlink() or path.stat().st_size > 4096:
            return False
        state = json.loads(path.read_text())
        port, token = state['port'], state['token']
        if type(port) is not int or not 1 <= port <= 65535 or not isinstance(token, str) or len(token) < 32:
            return False
        url = f'http://127.0.0.1:{port}'
        request = Request(url + '/status', headers={'X-Launch-Token': token})
        with opener().open(request, timeout=3) as response:
            result = json.load(response)
        if result.get('instance') != state['instance']:
            return False
        webbrowser.open(url + '/#launch-token=' + token)
        return True
    except (OSError, ValueError, KeyError):
        return False


def available_port():
    for port in range(8080, 8091):
        try:
            with socket.socket() as probe:
                if os.name != 'nt':
                    probe.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                probe.bind(('127.0.0.1', port))
            return port
        except OSError:
            continue
    raise manage.SetupError('Ports 8080–8090 are in use. Close another local tracker window and try again.')


def runtime(workspace, log):
    if manage.requirements_ready():
        return Path(sys.executable)
    environment = workspace / '.venv'
    python = environment / ('Scripts/python.exe' if os.name == 'nt' else 'bin/python')
    if python.is_file():
        check = subprocess.run([str(python), '-c', 'import sys;sys.path.insert(0,sys.argv[1]);import manage;sys.exit(0 if manage.requirements_ready() else 1)', str(HERE)], stdout=log, stderr=log)
        if check.returncode == 0:
            return python
    if not python.is_file():
        subprocess.run([sys.executable, '-m', 'venv', str(environment)], stdout=log, stderr=log, check=True)
    subprocess.run([str(python), '-m', 'pip', 'install', '--disable-pip-version-check', '-r', str(HERE / 'requirements-shared.txt')], stdout=log, stderr=log, check=True)
    return python


class LoadingServer(ThreadingHTTPServer):
    daemon_threads = True


def handler_for(state, token):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_args):
            pass

        def do_GET(self):
            if self.headers.get('Host') != f'127.0.0.1:{self.server.server_port}':
                self.send_error(400)
                return
            if self.path == '/':
                nonce = secrets.token_urlsafe(24)
                body, mime = loading_page(nonce).encode(), 'text/html; charset=utf-8'
            elif self.path == '/status':
                provided = self.headers.get('X-Launch-Token', '')
                if not secrets.compare_digest(provided.encode('utf-8'), token.encode('utf-8')):
                    self.send_error(403)
                    return
                body, mime = json.dumps(state).encode(), 'application/json'
                nonce = None
            elif self.path == '/favicon.ico':
                self.send_response(204)
                self.end_headers()
                return
            else:
                self.send_error(404)
                return
            self.send_response(200)
            self.send_header('Content-Type', mime)
            self.send_header('Cache-Control', 'no-store')
            self.send_header('Referrer-Policy', 'no-referrer')
            self.send_header('X-Frame-Options', 'DENY')
            self.send_header('X-Content-Type-Options', 'nosniff')
            scripts = "'nonce-" + nonce + "'" if nonce else "'none'"
            self.send_header('Content-Security-Policy', "default-src 'none'; script-src " + scripts + "; style-src 'unsafe-inline'; connect-src 'self'; img-src data:; base-uri 'none'; frame-ancestors 'none'; form-action 'self'")
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
    return Handler


def launch(workspace, open_browser=True):
    if (workspace / 'config.json').exists() and manage.load_config(workspace)['public_url']:
        raise manage.SetupError('This workspace is configured for hosted HTTPS access. Open its public URL, or choose a separate local workspace.')
    token, instance = secrets.token_urlsafe(40), secrets.token_hex(24)
    state = dict(instance=instance, message='Preparing the local workspace…', detail='The first start installs the required Python packages. No commands are needed.', failed=False)
    loading = LoadingServer(('127.0.0.1', 0), handler_for(state, token))
    thread = threading.Thread(target=loading.serve_forever, daemon=True)
    thread.start()
    state_file = workspace / '.desktop-state.json'
    private_write(state_file, {'port': loading.server_port, 'token': token, 'instance': instance})
    if open_browser:
        webbrowser.open(f'http://127.0.0.1:{loading.server_port}/#launch-token={token}')
    process = None
    log_path = workspace / 'launcher.log'
    try:
        if log_path.is_symlink():
            raise manage.SetupError('The launcher log must be a regular private file.')
        descriptor = os.open(log_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        if os.name != 'nt':
            os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, 'w') as log:
            python = runtime(workspace, log)
            port = available_port()
            env = {k: v for k, v in os.environ.items() if not k.startswith('TRACKER_') and k not in ('RENDER_EXTERNAL_URL', 'PORT')}
            setup_token = secrets.token_urlsafe(40)
            env.update(TRACKER_SETUP_TOKEN=setup_token, TRACKER_DESKTOP_INSTANCE=instance, PYTHONUNBUFFERED='1')
            process = subprocess.Popen([str(python), str(HERE / 'web_setup.py'), '--workspace', str(workspace), '--host', '127.0.0.1', '--port', str(port)], env=env, stdout=log, stderr=log)
            deadline = time.monotonic() + 45
            while time.monotonic() < deadline:
                if process.poll() is not None:
                    raise manage.SetupError('The local workspace could not start. Reopen Start Tracker to retry. Details are in your private launcher.log.')
                try:
                    with opener().open(f'http://127.0.0.1:{port}/healthz', timeout=.5) as response:
                        if response.status == 200 and json.load(response).get('desktop_instance') == instance:
                            break
                except OSError:
                    time.sleep(.2)
            else:
                raise manage.SetupError('The local workspace did not become ready. Reopen Start Tracker to retry.')
            configured = (workspace / 'config.json').is_file()
            state.update(message='Your workspace is ready.', detail='Opening the browser setup.' if not configured else 'Opening administration.',
                         url=f'http://127.0.0.1:{port}' + ('/admin' if configured else '/setup#setup-token=' + setup_token))
            process.wait()
            if process.returncode:
                raise manage.SetupError('The local workspace stopped unexpectedly. Reopen Start Tracker; details are in your private launcher.log.')
    except (manage.SetupError, OSError, subprocess.SubprocessError) as error:
        state.update(message='Setup needs attention.', detail=str(error) if isinstance(error, manage.SetupError) else 'Dependency setup failed. Check internet access and install Python 3.10 or newer from python.org, then reopen Start Tracker.', failed=True)
        notify(state['detail'] + '\n\nPrivate log: ' + str(log_path))
        return 1
    except KeyboardInterrupt:
        return 0
    finally:
        if process and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=8)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
        loading.shutdown()
        loading.server_close()
        state_file.unlink(missing_ok=True)
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--workspace', default=str(manage.DEFAULT_WORKSPACE))
    parser.add_argument('--no-browser', action='store_true', help=argparse.SUPPRESS)
    args = parser.parse_args(argv)
    handlers = {}
    def interrupted(_signum, _frame):
        raise KeyboardInterrupt
    for name in ('SIGTERM', 'SIGHUP'):
        if hasattr(signal, name):
            number = getattr(signal, name)
            handlers[number] = signal.getsignal(number)
            signal.signal(number, interrupted)
    try:
        if sys.version_info < (3, 10):
            raise manage.SetupError('Install Python 3.10 or newer from python.org, then reopen Start Tracker.')
        workspace = manage.prepare_workspace(manage.workspace_path(args.workspace))
        with workspace_lock(workspace) as locked:
            if not locked:
                if not reopen(workspace):
                    notify('This workspace is already opening or running. Return to its browser window, or wait a moment and reopen Start Tracker.')
                return 0
            return launch(workspace, not args.no_browser)
    except (manage.SetupError, OSError) as error:
        notify(str(error) if isinstance(error, manage.SetupError) else 'Could not open the private workspace. Check folder access and available disk space.')
        return 1
    except KeyboardInterrupt:
        return 0
    finally:
        for number, handler in handlers.items():
            signal.signal(number, handler)


if __name__ == '__main__':
    sys.exit(main())
