#!/usr/bin/env python3
"""Run the client-neutral browser setup and shared tracker with a live worker."""
import argparse
from contextlib import closing
from datetime import datetime, timezone
import os
from pathlib import Path
import secrets
import signal
import sqlite3
import sys
import threading
import time
from urllib.parse import urlsplit

try:
    from . import manage, notifications, server, tracker
except ImportError:
    import manage, notifications, server, tracker


def create_web_app(workspace, public_url=None, setup_token=None, env=None):
    env = os.environ if env is None else env
    workspace = manage.prepare_workspace(workspace)
    configured = (workspace / "config.json").is_file()
    if configured:
        config = manage.load_config(workspace)
        manage.runtime_environment(workspace, config)  # fail closed on missing/symlink DB
        if public_url is not None and manage.public_url(public_url) != config["public_url"]:
            raise manage.SetupError("Hosting URL differs from this workspace. Use its existing address or a separate workspace.")
        url = config["public_url"]
        secret = config["secret_key"]
        token = None
    else:
        url = manage.public_url(public_url or "")
        database = workspace / "tracker.sqlite"
        if database.is_symlink() or (workspace / "config.json").is_symlink():
            raise manage.SetupError("Workspace storage must use regular private files.")
        if database.exists():
            with closing(sqlite3.connect(database.as_uri() + "?mode=ro", uri=True)) as db:
                tables = {row[0] for row in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
                if "users" in tables and db.execute("SELECT 1 FROM users LIMIT 1").fetchone():
                    raise manage.SetupError("Existing accounts have no matching config.json. Restore that private configuration; setup cannot reclaim this workspace.")
        token = setup_token if setup_token is not None else env.get("TRACKER_SETUP_TOKEN")
        if not isinstance(token, str) or not 32 <= len(token) <= 512 or not token.isascii() or any(ord(c) < 33 or ord(c) == 127 for c in token):
            raise manage.SetupError("First-time browser setup requires a private TRACKER_SETUP_TOKEN of at least 32 characters. Use the desktop launcher or hosting dashboard.")
        secret = secrets.token_urlsafe(48)
    manage.check_expected_url({"public_url": url})
    host = urlsplit(url).hostname if url else None
    hosts = (["[" + host + "]" if ":" in host else host] if host else ["localhost", "127.0.0.1", "[::1]"])
    app = server.create_app({"DATABASE": str(workspace / "tracker.sqlite"), "SECRET_KEY": secret,
                             "COOKIE_SECURE": bool(url), "TRUSTED_HOSTS": hosts, "WORKSPACE": str(workspace),
                             "PUBLIC_URL": url, "SETUP_TOKEN": token,
                             "DESKTOP_INSTANCE": env.get("TRACKER_DESKTOP_INSTANCE", "") if not url else ""})
    if os.name != "nt":
        (workspace / "tracker.sqlite").chmod(0o600)
    return app


class NotificationWorker:
    """One worker; reload atomic private settings without a server restart."""
    def __init__(self, app, stop_event=None):
        self.app = app
        self.workspace = Path(app.config["WORKSPACE"])
        self.stop_event = stop_event or threading.Event()
        self.status = {"status": "starting", "last_poll": None, "error": None, "counts": {}}
        app.extensions["tracker_worker"] = self.status
        self.thread = threading.Thread(target=self.run, name="tracker-notifications", daemon=True)

    def start(self):
        self.thread.start()

    def stop(self):
        self.stop_event.set()
        if self.thread.is_alive():
            self.thread.join(timeout=20)

    def run(self):
        previous = None
        next_poll = 0
        while not self.stop_event.is_set():
            try:
                if not (self.workspace / "config.json").is_file():
                    self.status.update(status="starting", error=None)
                    self.stop_event.wait(.5)
                    continue
                config = manage.load_config(self.workspace)
                # Signing/hosting settings cannot be hot-reconfigured behind
                # an existing listener. Email changes are applied automatically.
                if config["secret_key"] != self.app.config["SECRET_KEY"] or config["public_url"] != self.app.config["PUBLIC_URL"]:
                    raise manage.SetupError("The hosting configuration changed; restart the service.")
                signature = (config["email"], config["stale_hours"], config["interval"])
                changed = signature != previous
                previous = signature
                if config["email"]["mode"] == "off":
                    self.status.update(status="off", error=None)
                elif changed or time.monotonic() >= next_poll:
                    preview = self.workspace / "mail-preview" if config["email"]["mode"] == "preview" else None
                    if preview and preview.is_symlink():
                        raise manage.SetupError("Preview directory must not be a symbolic link.")
                    transport = notifications.Config.from_env(manage.email_environment(config), preview=preview is not None)
                    counts = notifications.run_once(self.workspace / "tracker.sqlite", transport, preview, config["stale_hours"])
                    self.status.update(status="error" if counts["failed"] else "running", error="DeliveryFailed" if counts["failed"] else None,
                                       counts=counts, last_poll=datetime.now(timezone.utc).isoformat())
                    next_poll = time.monotonic() + config["interval"]
                else:
                    self.status["status"] = "error" if self.status["error"] else "running"
            except Exception as error:
                self.status.update(status="error", error=type(error).__name__)
                # Errors remain redacted; a corrected atomic config is retried.
            self.stop_event.wait(1)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workspace", default=str(manage.DEFAULT_WORKSPACE))
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=os.environ.get("PORT", "8080"))
    args = parser.parse_args(argv)
    worker = None
    httpd = None
    try:
        url = os.environ.get("TRACKER_SETUP_PUBLIC_URL") or os.environ.get("RENDER_EXTERNAL_URL")
        app = create_web_app(args.workspace, url)
        manage.bind_address(args.host, args.port, {"public_url": app.config["PUBLIC_URL"]})
        from waitress.server import create_server
        httpd = create_server(app, host=args.host, port=args.port, clear_untrusted_proxy_headers=True)
        # "localhost" can create IPv4 and IPv6 listeners behind Waitress's
        # MultiSocketServer. They share one socket map and each has a trigger.
        listener = httpd if hasattr(httpd, "trigger") else next(
            channel for channel in httpd.map.values()
            if hasattr(getattr(channel, "trigger", None), "pull_trigger"))
        stopped = threading.Event()
        worker = NotificationWorker(app, stopped)

        def stop():
            if stopped.is_set():
                return
            stopped.set()
            # The browser invokes this from a timer thread. Closing descriptors
            # there races Waitress's select loop; closing only the listener also
            # leaves keep-alive channels running. Its trigger executes callbacks
            # on the I/O thread, where the complete socket map can close safely.
            listener.trigger.pull_trigger(lambda: httpd.asyncore.close_all(map=listener._map))

        app.extensions["tracker_stop"] = stop
        worker.start()
        for name in ("SIGTERM", "SIGINT"):
            if hasattr(signal, name):
                signal.signal(getattr(signal, name), lambda _s, _f: stop())
        # Never print a setup key or a fragment-bearing URL.
        print("Open Study Tracker browser setup is ready.", flush=True)
        httpd.run()
        return 0
    except (manage.SetupError, tracker.TrackerError) as error:
        print(f"Open Study Tracker: {error}", file=sys.stderr)
        return 1
    except (OSError, sqlite3.Error, ValueError) as error:
        print(f"Open Study Tracker: {type(error).__name__}. Check the workspace and listening port.", file=sys.stderr)
        return 1
    finally:
        if worker:
            worker.stop()
        if httpd:
            httpd.close()
            httpd.task_dispatcher.shutdown()


if __name__ == "__main__":
    sys.exit(main())
