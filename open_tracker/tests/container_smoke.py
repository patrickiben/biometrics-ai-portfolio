#!/usr/bin/env python3
"""Exercise the real team Compose recipe using disposable local TLS and data.

Run from the repository root on a Linux Docker host. No external SMTP or
certificate authority is contacted. Docker/Compose and internet access to pull
the public base images and Python packages are required.
"""
import http.client
from http.cookies import SimpleCookie
import json
import os
from pathlib import Path
import pty
import secrets
import select
import socket
import ssl
import sqlite3
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
COMPOSE = ROOT / 'open_tracker/deploy/compose.yaml'


def guided(command, replies, env, cwd, timeout=120):
    """Drive the actual password prompts through a private PTY, never argv."""
    master, slave = pty.openpty()
    process = subprocess.Popen(command, stdin=slave, stdout=slave, stderr=slave,
                               env=env, cwd=cwd, start_new_session=True)
    os.close(slave)
    transcript = b''
    cursor = 0
    deadline = time.monotonic() + timeout
    try:
        while process.poll() is None:
            if time.monotonic() > deadline:
                raise AssertionError('Guided setup timed out')
            if select.select([master], [], [], .2)[0]:
                try:
                    chunk = os.read(master, 65536)
                except OSError:
                    break
                transcript += chunk
                if cursor < len(replies) and replies[cursor][0].encode() in transcript:
                    os.write(master, (replies[cursor][1] + '\n').encode())
                    cursor += 1
                    # Each prompt is consumed, so overlapping words cannot match twice.
                    transcript = b''
        assert process.wait(timeout=10) == 0, transcript.decode(errors='replace')
        assert cursor == len(replies), 'Not all guided prompts were reached'
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
        os.close(master)


class LocalTLS(http.client.HTTPSConnection):
    def connect(self):
        context = ssl._create_unverified_context()  # disposable Caddy internal CA only
        self.sock = context.wrap_socket(socket.create_connection(('127.0.0.1', 18443), timeout=8),
                                        server_hostname='tracker.test')


class Client:
    def __init__(self):
        self.cookies = SimpleCookie()
        self.csrf = None

    def request(self, path, data=None, expected=200, origin='https://tracker.test', raw=False):
        connection = LocalTLS('tracker.test', timeout=8)
        headers = {'Host': 'tracker.test'}
        if self.cookies:
            headers['Cookie'] = '; '.join(f'{k}={v.value}' for k, v in self.cookies.items())
        body = None
        if data is not None:
            body = json.dumps(data)
            headers.update({'Content-Type': 'application/json', 'Origin': origin, 'X-CSRF-Token': self.csrf or ''})
        connection.request('POST' if data is not None else 'GET', path, body=body, headers=headers)
        response = connection.getresponse()
        content = response.read()
        assert response.status == expected, (path, response.status, content[:200])
        response_headers = dict(response.getheaders())
        for header, value in response.getheaders():
            if header.lower() == 'set-cookie':
                assert 'Secure' in value and 'HttpOnly' in value
                self.cookies.load(value)
        connection.close()
        if raw:
            return content, response_headers
        result = json.loads(content)
        self.csrf = result.get('csrf_token', self.csrf)
        return result


def main():
    output = Path(os.environ.get('QA_OUTPUT_DIR', tempfile.mkdtemp(prefix='tracker-container-'))).resolve()
    output.mkdir(parents=True, exist_ok=True)
    env = {k: v for k, v in os.environ.items() if not k.startswith('TRACKER_')}
    env['TRACKER_PUBLIC_URL'] = 'https://tracker.test'
    browser_mode = os.environ.get('TRACKER_CONTAINER_BROWSER') == '1'
    setup_key = secrets.token_urlsafe(48)
    if browser_mode:
        env['TRACKER_SETUP_TOKEN'] = setup_key
    project = 'tracker-qc-' + secrets.token_hex(4)
    override = output / 'compose-test.yaml'
    caddy = output / 'Caddyfile.test'
    caddy.write_text('https://tracker.test {\n tls internal\n reverse_proxy tracker:8080\n}\n')
    override.write_text('services:\n  proxy:\n    ports: !override\n      - "127.0.0.1:18443:443"\n'
                        '    volumes:\n      - ' + json.dumps(str(caddy) + ':/etc/caddy/Caddyfile:ro') + '\n')
    selected_compose = COMPOSE.with_name('compose.browser.yaml') if browser_mode else COMPOSE
    compose = ['docker', 'compose', '-p', project, '-f', str(selected_compose), '-f', str(override)]
    results = []
    password = secrets.token_urlsafe(24)
    complete = False

    def run(*arguments, timeout=180, check=True):
        result = subprocess.run([*compose, *arguments], env=env, cwd=ROOT, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout)
        if check and result.returncode:
            raise AssertionError(result.stdout[-6000:])
        return result

    def passed(name):
        results.append({'name': name, 'passed': True})
        print('PASS ' + name, flush=True)

    try:
        spec = json.loads(run('config', '--format', 'json').stdout)
        assert not spec['services']['tracker'].get('ports')
        assert spec['services']['tracker']['read_only']
        assert spec['services']['proxy']['depends_on']['tracker']['condition'] == 'service_healthy'
        passed('Team recipe exposes only proxy and waits for a healthy app')
        build = run('build', '--pull', timeout=600)
        (output / 'build.log').write_text(build.stdout)
        if not browser_mode:
            guided([*compose, 'run', '--rm', '--no-deps', 'tracker', 'setup', '--demo'],
                   [('Initial administrator username', 'qcadmin'), ('Password (at least', password),
                    ('Confirm password', password)], env, ROOT)
            passed('First-run wizard creates persistent private configuration and administrator')
        run('up', '-d', '--wait', '--wait-timeout', '120')
        for attempt in range(30):
            try:
                client = Client()
                client.request('/api/session')
                break
            except (OSError, http.client.HTTPException):
                if attempt == 29:
                    raise
                time.sleep(1)
        if browser_mode:
            state = client.request('/api/setup/state')
            assert state['configured'] is False and state['token_required'] is True
            assert setup_key not in json.dumps(state)
            page, _headers = client.request('/setup', raw=True)
            assert b'data-managed="true"' in page and setup_key.encode() not in page
            passed('Unconfigured HTTPS container is healthy and exposes the protected setup page')
            claim = dict(setup_token='wrong-key', username='qcadmin', password=password, password_confirm=password, demo=True)
            client.request('/api/setup', claim, expected=403)
            client.request('/api/snapshot', expected=401)
            assert client.request('/api/setup/state')['configured'] is False
            claim['setup_token'] = setup_key
            assert client.request('/api/setup', claim)['configured'] is True
            client.request('/api/setup', claim, expected=403)
            passed('Browser first-run setup requires its private key and cannot be reclaimed')
        client.request('/api/login', {'username': 'qcadmin', 'password': password})
        snap = client.request('/api/snapshot')
        assert len(snap['rows']) == 4
        assert client.request('/api/tasks', {}, expected=403, origin='https://unrelated.test')['error']
        row = dict(task_id='CONTAINER-QC', title='Synthetic container check', status='In progress',
                   owner='QC', due='', progress=10, notes='')
        client.request('/api/tasks', {'row': row, 'expected_updated_at': None})
        passed('HTTPS proxy preserves Host; secure login, CSRF and shared editing work')
        if browser_mode:
            state = client.request('/api/admin/state')
            assert state['health']['database'] == 'ok' and state['health']['dependencies'] == 'ok'
            assert 'password' not in state['email']
            people = client.request('/api/admin/users', dict(command='add-user', username='reviewer', role='viewer', password=password))
            assert any(x['username'] == 'reviewer' and x['role'] == 'viewer' for x in people['users'])
            viewer = Client()
            viewer.request('/api/session')
            viewer.request('/api/login', dict(username='reviewer', password=password))
            viewer.request('/api/snapshot')
            viewer.request('/api/admin/state', expected=403)
            viewer.request('/api/admin/backup', expected=403)
            viewer.request('/api/admin/users', dict(command='add-user', username='unauthorized', role='admin', password=password), expected=403)
            passed('Browser account administration works and viewers cannot access administrative APIs')
            preview = client.request('/api/admin/email-test', dict(send=False, to=None, confirm_send=False))
            assert 'No email was sent' in preview['preview']
            mail = {key: value for key, value in state['email'].items() if key != 'password_configured'}
            mail.update(mode='off', password=None)
            client.request('/api/admin/email', dict(email=mail, stale_hours=0, confirm_live=False))
            for _ in range(50):
                if client.request('/api/admin/state')['worker']['status'] == 'off':
                    break
                time.sleep(.2)
            else:
                raise AssertionError('Email worker did not pause after browser settings save')
            mail['mode'] = 'preview'
            client.request('/api/admin/email', dict(email=mail, stale_hours=0, confirm_live=False))
            for _ in range(50):
                if client.request('/api/admin/state')['worker']['status'] == 'running':
                    break
                time.sleep(.2)
            else:
                raise AssertionError('Email worker did not resume preview after browser settings save')
            client.request('/api/admin/stop', dict(confirm=True), expected=403)
            passed('Email preview and pause/resume apply in the browser without restarting the container')
        else:
            doctor = run('exec', '-T', 'tracker', 'python', '/app/open_tracker/manage.py', '--workspace', '/data', 'doctor')
            assert 'PASS' in doctor.stdout
            run('exec', '-T', 'tracker', 'python', '/app/open_tracker/manage.py', '--workspace', '/data', 'email-test')
            run('exec', '-T', 'tracker', 'python', '-c', 'from pathlib import Path; assert list(Path("/data/mail-preview").glob("*.eml"))')
            passed('Offline doctor and email preview work inside the running container')
        run('restart', 'tracker')
        run('up', '-d', '--wait', '--wait-timeout', '120')
        client.request('/api/session')
        # The existing login survives restart because both DB and signing key persist.
        assert any(x['task_id'] == 'CONTAINER-QC' for x in client.request('/api/snapshot')['rows'])
        passed('Restart preserves tasks, accounts and authenticated session')
        if browser_mode:
            assert any(x['username'] == 'reviewer' for x in client.request('/api/admin/state')['users'])
            backup, headers = client.request('/api/admin/backup', raw=True)
            assert backup.startswith(b'SQLite format 3') and 'attachment' in headers.get('Content-Disposition', '')
            assert password.encode() not in backup and setup_key.encode() not in backup
            descriptor, temporary = tempfile.mkstemp(prefix='tracker-backup-check-', suffix='.sqlite')
            try:
                with os.fdopen(descriptor, 'wb') as stream:
                    stream.write(backup)
                connection = sqlite3.connect(temporary)
                try:
                    assert connection.execute('PRAGMA quick_check').fetchone()[0] == 'ok'
                    assert connection.execute('SELECT COUNT(*) FROM users').fetchone()[0] == 2
                finally:
                    connection.close()
            finally:
                Path(temporary).unlink(missing_ok=True)
            passed('Authenticated browser backup downloads a consistent SQLite database without setup credentials')
        else:
            run('exec', '-T', 'tracker', 'python', '/app/open_tracker/manage.py', '--workspace', '/data', 'backup')
            run('exec', '-T', 'tracker', 'python', '-c', 'from pathlib import Path; assert list(Path("/data/backups").glob("*.sqlite"))')
            passed('Consistent backup runs against live shared storage')
        config_mode = run('exec', '-T', 'tracker', 'python', '-c',
                          'import os,stat; assert os.getuid()!=0; assert stat.S_IMODE(os.stat("/data/config.json").st_mode)==0o600')
        passed('App runs without root and configuration has owner-only permissions')
        complete = True
    finally:
        (output / 'services.log').write_text(run('logs', '--no-color', check=False).stdout)
        run('down', '--volumes', '--remove-orphans', check=False)
        (output / 'report.json').write_text(json.dumps({'scenarios': results, 'passed': complete,
                                                       'mode': 'browser' if browser_mode else 'legacy',
                                                       'external_email_sent': False, 'public_certificate_issued': False}, indent=2))
    print(f'Container smoke evidence: {output}')


if __name__ == '__main__':
    main()
