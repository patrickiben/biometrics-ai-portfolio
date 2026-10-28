#!/usr/bin/env python3
"""Start the local toolkit portal with Python's standard library."""
import argparse
from contextlib import contextmanager, ExitStack
import json
import os
from pathlib import Path
import secrets
import signal
import subprocess
import sys
import threading
from urllib.request import Request, build_opener, ProxyHandler
import webbrowser

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from toolkit_launcher.runtime import Workspace, InputError, atomic_json, private_base
from toolkit_launcher.server import create_server


@contextmanager
def launcher_lock(base):
    path = base / '.toolkit.lock'
    if path.is_symlink():
        raise InputError('The launcher lock must be a private regular file.')
    descriptor = os.open(path, os.O_RDWR | os.O_CREAT, 0o600)
    stream = os.fdopen(descriptor, 'r+b')
    locked = False
    try:
        if os.name == 'nt':
            import msvcrt
            if path.stat().st_size == 0:
                stream.write(b'0'); stream.flush()
            stream.seek(0)
            try:
                msvcrt.locking(stream.fileno(), msvcrt.LK_NBLCK, 1); locked = True
            except OSError:
                pass
        else:
            import fcntl
            try:
                fcntl.flock(stream.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB); locked = True
            except BlockingIOError:
                pass
        yield locked
    finally:
        if locked:
            if os.name == 'nt':
                stream.seek(0); msvcrt.locking(stream.fileno(), msvcrt.LK_UNLCK, 1)
            else:
                fcntl.flock(stream.fileno(), fcntl.LOCK_UN)
        stream.close()


def notify(message):
    try:
        if sys.platform == 'darwin':
            script = 'on run argv\ndisplay dialog (item 1 of argv) with title "Trial biostatistics toolkit" buttons {"OK"} default button "OK"\nend run'
            subprocess.run(['osascript', '-e', script, message], check=False)
        elif os.name == 'nt':
            import ctypes
            ctypes.windll.user32.MessageBoxW(0, message, 'Trial biostatistics toolkit', 0)
        else:
            print(message, file=sys.stderr)
    except OSError:
        print(message, file=sys.stderr)


def reopen(base):
    try:
        file = base / '.launcher-session.json'
        if file.is_symlink() or file.stat().st_size > 4096:
            return False
        state = json.loads(file.read_text())
        port, token = state['port'], state['token']
        if type(port) is not int or not 1 <= port <= 65535 or not isinstance(token, str) or len(token) < 32:
            return False
        url = f'http://127.0.0.1:{port}'
        request = Request(url + '/api/state', headers={'X-Toolkit-Token': token})
        with build_opener(ProxyHandler({})).open(request, timeout=15) as response:
            if response.status != 200:
                return False
        webbrowser.open(url + '/#launch-token=' + token)
        return True
    except (OSError, ValueError, KeyError):
        return False


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--workspace', default=str(Path.home() / '.biostat-toolkit'))
    parser.add_argument('--no-browser', action='store_true')
    parser.add_argument('--port', type=int, default=None)
    args = parser.parse_args(argv)
    workspace = server = None
    state_file = None
    handlers = {}
    def cleanup():
        nonlocal workspace, server, state_file
        try:
            if workspace:
                workspace.close()
        finally:
            workspace = None
            if server:
                server.server_close()
                server = None
            if state_file:
                state_file.unlink(missing_ok=True)
                state_file = None
    try:
        if sys.version_info < (3, 10):
            raise InputError('Install Python 3.10 or newer with its normal installer, then reopen Start Toolkit.')
        base = private_base(args.workspace)
        with launcher_lock(base) as locked, ExitStack() as active:
            if not locked:
                if not reopen(base):
                    notify('This toolkit workspace is opening. Return to its browser window or reopen Start Toolkit in a moment.')
                return 0
            # Cleanup runs before launcher_lock exits, so a second double-click
            # cannot start a new supervisor while the old jobs are still alive.
            active.callback(cleanup)
            workspace = Workspace(base)
            token = secrets.token_urlsafe(40)
            if args.port is not None:
                server = create_server(workspace, token, args.port)
            else:
                for port in range(8095, 8106):
                    try:
                        server = create_server(workspace, token, port)
                        break
                    except OSError:
                        continue
                if server is None:
                    server = create_server(workspace, token, 0)
            state_file = base / '.launcher-session.json'
            atomic_json(state_file, {'port': server.server_port, 'token': token})
            def stop(*_args):
                threading.Thread(target=server.shutdown, daemon=True).start()
            for name in ('SIGTERM', 'SIGINT', 'SIGHUP'):
                if hasattr(signal, name):
                    number = getattr(signal, name); handlers[number] = signal.getsignal(number); signal.signal(number, stop)
            if not args.no_browser:
                webbrowser.open(f'http://127.0.0.1:{server.server_port}/#launch-token=' + token)
            print('The toolkit is ready in your browser. Use Close toolkit to stop local tasks.', flush=True)
            server.serve_forever(poll_interval=.2)
        return 0
    except (OSError, ValueError) as error:
        notify(str(error) if isinstance(error, InputError) else 'The toolkit could not start. Check folder access and download a complete toolkit copy.')
        return 1
    finally:
        cleanup()
        for number, handler in handlers.items():
            signal.signal(number, handler)


if __name__ == '__main__':
    sys.exit(main())
