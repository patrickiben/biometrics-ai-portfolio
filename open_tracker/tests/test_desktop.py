"""Launcher isolation and browser loading-page checks, with temporary state."""
from contextlib import contextmanager
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch
from urllib.error import HTTPError
from urllib.request import Request

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import desktop


@contextmanager
def loading(state=None):
    token = secrets.token_urlsafe(40)
    state = state or {'instance': 'synthetic-instance', 'message': 'Preparing', 'failed': False}
    server = desktop.LoadingServer(('127.0.0.1', 0), desktop.handler_for(state, token))
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        yield server, token
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=3)


class DesktopTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix='tracker desktop ')
        self.workspace = Path(self.directory.name)

    def tearDown(self):
        self.directory.cleanup()

    def test_loading_html_never_exposes_the_setup_key(self):
        setup_key = secrets.token_urlsafe(40)
        state = {'instance': 'synthetic-instance', 'url': 'http://127.0.0.1:8080/setup#setup-token=' + setup_key}
        with loading(state) as (server, token):
            base = f'http://127.0.0.1:{server.server_port}'
            with desktop.opener().open(base) as response:
                page = response.read().decode()
                self.assertNotIn(setup_key, page)
                self.assertNotIn(token, page)
                self.assertEqual(response.headers['Cache-Control'], 'no-store')
                self.assertEqual(response.headers['Referrer-Policy'], 'no-referrer')
                self.assertIn("script-src 'nonce-", response.headers['Content-Security-Policy'])
                self.assertIn((desktop.HERE.parent / 'assets/theme/tokens.css').read_text(), page)
            with self.assertRaises(HTTPError) as denied:
                desktop.opener().open(base + '/status')
            self.assertEqual(denied.exception.code, 403)
            denied.exception.close()
            request = Request(base + '/status', headers={'X-Launch-Token': token})
            with desktop.opener().open(request) as response:
                self.assertEqual(json.load(response)['url'], state['url'])

    def test_loading_server_blocks_rebound_hosts_even_with_capability(self):
        with loading() as (server, token):
            request = Request(f'http://127.0.0.1:{server.server_port}/status',
                              headers={'Host': 'unrelated.test', 'X-Launch-Token': token})
            with self.assertRaises(HTTPError) as denied:
                desktop.opener().open(request)
            self.assertEqual(denied.exception.code, 400)
            denied.exception.close()

    def test_repeat_launch_uses_the_existing_verified_window(self):
        with loading() as (server, token), patch.object(desktop.webbrowser, 'open') as opened:
            desktop.private_write(self.workspace / '.desktop-state.json',
                                  {'port': server.server_port, 'token': token, 'instance': 'synthetic-instance'})
            self.assertTrue(desktop.reopen(self.workspace))
            self.assertEqual(opened.call_count, 1)
            url = opened.call_args.args[0]
            self.assertIn('#launch-token=', url)
            self.assertNotIn('?', url)

    def test_repeat_launch_rejects_a_different_process_identity(self):
        with loading() as (server, token), patch.object(desktop.webbrowser, 'open') as opened:
            desktop.private_write(self.workspace / '.desktop-state.json',
                                  {'port': server.server_port, 'token': token, 'instance': 'different-instance'})
            self.assertFalse(desktop.reopen(self.workspace))
            opened.assert_not_called()

    def test_workspace_lock_prevents_duplicate_workers_and_releases(self):
        with desktop.workspace_lock(self.workspace) as first:
            self.assertTrue(first)
            with desktop.workspace_lock(self.workspace) as second:
                self.assertFalse(second)
        with desktop.workspace_lock(self.workspace) as subsequent:
            self.assertTrue(subsequent)

    def test_private_state_does_not_follow_symlinks_or_retain_broad_modes(self):
        path = self.workspace / '.desktop-state.json'
        desktop.private_write(path, {'token': 'synthetic'})
        if os.name != 'nt':
            path.chmod(0o644)
            desktop.private_write(path, {'token': 'new-synthetic'})
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        link = self.workspace / 'link.json'
        try:
            link.symlink_to(path)
        except (OSError, NotImplementedError):
            return
        with self.assertRaises(desktop.manage.SetupError):
            desktop.private_write(link, {'token': 'overwritten'})
        self.assertNotEqual(json.loads(path.read_text())['token'], 'overwritten')

    def test_prepared_runtime_is_reused_without_package_install(self):
        python = self.workspace / '.venv' / ('Scripts/python.exe' if os.name == 'nt' else 'bin/python')
        python.parent.mkdir(parents=True)
        python.touch()
        with patch.object(desktop.manage, 'requirements_ready', return_value=False), \
             patch.object(desktop.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0)) as run:
            with open(os.devnull, 'w') as log:
                self.assertEqual(desktop.runtime(self.workspace, log), python)
            self.assertEqual(run.call_count, 1)
            self.assertNotIn('pip', run.call_args.args[0])

    def test_hosted_workspace_is_not_started_as_an_insecure_local_copy(self):
        (self.workspace / 'config.json').write_text('{}')
        with patch.object(desktop.manage, 'load_config', return_value={'public_url': 'https://tracker.example.test'}), \
             patch.object(desktop.subprocess, 'Popen') as process:
            with self.assertRaises(desktop.manage.SetupError):
                desktop.launch(self.workspace, open_browser=False)
            process.assert_not_called()


if __name__ == '__main__':
    unittest.main()
