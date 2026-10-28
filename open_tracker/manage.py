#!/usr/bin/env python3
"""Guided, portable setup for Open Study Tracker. No command means start."""

import argparse
from contextlib import closing
from datetime import datetime, timezone
import getpass
from email.message import EmailMessage
from email.policy import SMTP as SMTP_POLICY
import importlib.metadata
import ipaddress
import json
import math
import os
from pathlib import Path
import re
import secrets
import signal
import socket
import sqlite3
import subprocess
import sys
import tempfile
import time
from urllib.parse import urlsplit

HERE = Path(__file__).resolve().parent
REPOSITORY = HERE.parent
DEFAULT_WORKSPACE = Path.home() / ".open-study-tracker"
ACCOUNT_COMMANDS = ("add-user", "set-password", "set-role", "disable-user", "enable-user", "list-users")


class SetupError(ValueError):
    """A configuration error whose message contains no secret values."""


def workspace_path(value):
    path = Path(value).expanduser().resolve()
    if path == Path.home().resolve() or path == Path(path.anchor) or path == REPOSITORY or REPOSITORY in path.parents or path in REPOSITORY.parents:
        raise SetupError("Choose a dedicated workspace outside the repository and outside its parent directories.")
    return path


def prepare_workspace(path):
    path = workspace_path(path)
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    if os.name != "nt":
        path.chmod(0o700)
    return path


def public_url(value):
    if not isinstance(value, str):
        raise SetupError("Public URL must be a string.")
    if not value:
        return ""
    try:
        parsed = urlsplit(value)
        if (parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password
                or parsed.query or parsed.fragment or parsed.path not in ("", "/")
                or any(c.isspace() or ord(c) < 32 for c in value)
                or parsed.port is not None and not 1 <= parsed.port <= 65535):
            raise ValueError()
        hostname = parsed.hostname.encode("idna").decode("ascii").lower()
        if len(hostname) > 253 or "%" in hostname:
            raise ValueError()
        try:
            ipaddress.ip_address(hostname)
        except ValueError:
            if ":" in hostname or not all(re.fullmatch(r"[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?", part) for part in hostname.split(".")):
                raise ValueError()
        host = "[" + hostname + "]" if ":" in hostname else hostname
        return "https://" + host + (":" + str(parsed.port) if parsed.port not in (None, 443) else "")
    except (ValueError, UnicodeError):
        raise SetupError("Team URL must be an HTTPS origin, for example https://tracker.example.org, without credentials or a path.") from None


def new_config(url=""):
    return {"version": 1, "secret_key": secrets.token_urlsafe(48), "public_url": public_url(url),
            "email": {"mode": "preview", "recipients": "reviewer@example.test", "host": "", "port": 587,
                      "security": "starttls", "sender": "", "username": "", "password": ""},
            "stale_hours": 0, "interval": 60}


def email_environment(config):
    mail = config["email"]
    result = {"TRACKER_ALERT_TO": mail["recipients"] if mail["mode"] != "off" else "",
              "TRACKER_SMTP_HOST": mail["host"], "TRACKER_SMTP_PORT": str(mail["port"]),
              "TRACKER_SMTP_SECURITY": mail["security"], "TRACKER_SMTP_FROM": mail["sender"],
              "TRACKER_SMTP_USERNAME": mail["username"], "TRACKER_SMTP_PASSWORD": mail["password"],
              "TRACKER_PUBLIC_URL": config["public_url"]}
    return result


def validate_config(config):
    expected = {"version", "secret_key", "public_url", "email", "stale_hours", "interval"}
    if not isinstance(config, dict) or set(config) != expected or type(config["version"]) is not int or config["version"] != 1:
        raise SetupError("Unsupported workspace configuration. Expected version 1 and the documented fields.")
    secret = config["secret_key"]
    if not isinstance(secret, str) or not 32 <= len(secret) <= 512 or any(ord(c) < 32 for c in secret):
        raise SetupError("The workspace signing key is missing or invalid.")
    if config["public_url"] != public_url(config["public_url"]):
        raise SetupError("Public URL must use its normalized HTTPS origin without a trailing slash.")
    for key, low in (("stale_hours", 0), ("interval", 1)):
        value = config[key]
        if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or value < low:
            raise SetupError(f"{key} must be a finite number of at least {low}.")
    mail = config["email"]
    fields = {"mode", "recipients", "host", "port", "security", "sender", "username", "password"}
    if not isinstance(mail, dict) or set(mail) != fields or mail["mode"] not in ("off", "preview", "smtp"):
        raise SetupError("Email configuration must use off, preview or smtp mode and documented fields.")
    if any(not isinstance(mail[k], str) or len(mail[k]) > (13000 if k == "recipients" else 4096) for k in fields - {"port"}):
        raise SetupError("Email settings must contain bounded text values.")
    if isinstance(mail["port"], bool) or not isinstance(mail["port"], int):
        raise SetupError("SMTP port must be an integer.")
    try:
        from . import notifications
    except ImportError:
        import notifications
    try:
        notifications.Config.from_env(email_environment(config), preview=mail["mode"] != "smtp")
    except notifications.ConfigError as error:
        raise SetupError(str(error)) from None
    if mail["mode"] in ("preview", "smtp") and not mail["recipients"].strip():
        raise SetupError("Choose at least one recipient, or use email mode off.")
    return config


def check_expected_url(config):
    if os.environ.get("TRACKER_CONTAINER") == "1" and (not config["public_url"] or urlsplit(config["public_url"]).port not in (None, 443)):
        raise SetupError("The packaged team container requires an HTTPS public URL on standard port 443.")
    expected = os.environ.get("TRACKER_EXPECTED_PUBLIC_URL")
    if expected is not None and public_url(expected) != config["public_url"]:
        raise SetupError("Configured public URL differs from the hosting URL. Update the workspace with setup --public-url and restart the services.")


def load_config(workspace):
    file = Path(workspace) / "config.json"
    if file.is_symlink():
        raise SetupError("Workspace config.json must be a regular private file, not a symbolic link.")
    if not file.is_file():
        raise SetupError("Workspace is not configured. Run setup, or start interactively for guided setup.")
    if os.name != "nt" and file.stat().st_mode & 0o077:
        raise SetupError("Workspace config.json must be private: run chmod 600 on that file.")
    try:
        if file.stat().st_size > 32768:
            raise ValueError()
        return validate_config(json.loads(file.read_text(encoding="utf-8")))
    except (ValueError, UnicodeError) as error:
        if isinstance(error, SetupError):
            raise
        raise SetupError("Workspace config.json is not valid bounded JSON.") from None


def save_config(workspace, config):
    validate_config(config)
    workspace = prepare_workspace(workspace)
    if (workspace / "config.json").is_symlink():
        raise SetupError("Refusing to replace a symbolic-link configuration.")
    descriptor, temporary = tempfile.mkstemp(prefix=".config-", dir=workspace)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            json.dump(config, stream, indent=2, ensure_ascii=True)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, workspace / "config.json")
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def runtime_environment(workspace, config):
    validate_config(config)
    # Persisted settings are authoritative; unrelated shell/service settings
    # must never activate mail or weaken cookies in a different workspace.
    database = Path(workspace) / "tracker.sqlite"
    if not database.is_file() or database.is_symlink():
        raise SetupError("Workspace tracker.sqlite is missing or is not a regular file. Restore a matching backup or use a new workspace.")
    env = {k: v for k, v in os.environ.items() if not k.startswith("TRACKER_")}
    env.update(email_environment(config))
    env["TRACKER_DB"] = str(Path(workspace) / "tracker.sqlite")
    env["TRACKER_SECRET_KEY"] = config["secret_key"]
    if config["public_url"]:
        hostname = urlsplit(config["public_url"]).hostname
        env["TRACKER_ALLOWED_HOSTS"] = "[" + hostname + "]" if ":" in hostname else hostname
    else:
        env["TRACKER_INSECURE_LOCAL"] = "1"
        env["TRACKER_ALLOWED_HOSTS"] = "localhost,127.0.0.1,[::1]"
    env["PYTHONUNBUFFERED"] = "1"
    return env


def requirements_ready():
    for line in (HERE / "requirements-shared.txt").read_text().splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        name, version = line.strip().split("==", 1)
        try:
            if importlib.metadata.version(name) != version:
                return False
        except importlib.metadata.PackageNotFoundError:
            return False
    return True


def ensure_runtime(workspace, argv, install=True):
    if requirements_ready():
        return
    if os.environ.get("OPEN_TRACKER_BOOTSTRAPPED") == "1":
        raise SetupError("The isolated environment does not match requirements-shared.txt. Remove its .venv and retry.")
    venv = workspace / ".venv"
    python = venv / ("Scripts/python.exe" if os.name == "nt" else "bin/python")
    if python.is_file():
        probe = subprocess.run([str(python), "-c", "import sys; sys.path.insert(0,sys.argv[1]); import manage; sys.exit(0 if manage.requirements_ready() else 1)", str(HERE)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if probe.returncode == 0:
            os.execve(str(python), [str(python), str(Path(__file__).resolve()), *argv], dict(os.environ, OPEN_TRACKER_BOOTSTRAPPED="1"))
    if not install:
        raise SetupError("Pinned dependencies are missing. Run start to prepare the isolated environment.")
    prepare_workspace(workspace)
    print("Preparing the isolated Python environment (first start needs package-download access).", flush=True)
    try:
        if not python.is_file():
            subprocess.run([sys.executable, "-m", "venv", str(venv)], check=True)
        subprocess.run([str(python), "-m", "pip", "install", "--disable-pip-version-check", "-r", str(HERE / "requirements-shared.txt")], check=True)
    except subprocess.CalledProcessError:
        raise SetupError("Dependency setup failed. Check internet access and Python venv support, then retry the same command.") from None
    env = dict(os.environ, OPEN_TRACKER_BOOTSTRAPPED="1")
    os.execve(str(python), [str(python), str(Path(__file__).resolve()), *argv], env)


def prompt(label, default=None, secret=False):
    suffix = f" [{default}]" if default is not None and not secret else ""
    value = (getpass.getpass if secret else input)(label + suffix + ": ")
    return default if not value and default is not None else value


def require_terminal():
    if not sys.stdin.isatty():
        raise SetupError("Guided setup needs an interactive terminal. Use an interactive shell, or docker compose run --rm tracker setup.")


def setup(workspace, url=None, demo=False):
    require_terminal()
    try:
        from . import server, tracker
    except ImportError:
        import server, tracker
    if (workspace / "config.json").exists():
        config = load_config(workspace)
        if url is not None:
            config["public_url"] = public_url(url)
            check_expected_url(config)
            save_config(workspace, config)
            print("Hosting URL updated. Restart services to use it.")
        else:
            print("Workspace already configured; signing key, accounts and tasks were preserved.")
        return config
    url = public_url(url or "")
    check_expected_url(new_config(url))
    try:
        username = server.username_value(prompt("Initial administrator username", "admin").strip())
    except tracker.TrackerError as error:
        raise SetupError(str(error)) from None
    first = prompt("Password (at least 12 characters)", secret=True)
    second = prompt("Confirm password", secret=True)
    if first != second:
        raise SetupError("Passwords do not match. Run setup again.")
    try:
        server.password_value(first)
    except tracker.TrackerError as error:
        raise SetupError(str(error)) from None
    demo = demo or prompt("Load fictional example tasks? (yes/no)", "no").strip().lower() == "yes"
    config = new_config(url)
    workspace = prepare_workspace(workspace)
    database = workspace / "tracker.sqlite"
    if database.exists():
        raise SetupError("An unconfigured workspace already contains tracker.sqlite. Choose a new workspace or restore its matching config.json.")
    server.manage_user(str(database), "add-user", username, first, "admin")
    if demo:
        tracker.upsert(database, tracker.read_input(HERE / "examples/status.csv", "csv"), "synthetic-demo")
    if os.name != "nt":
        database.chmod(0o600)
    save_config(workspace, config)
    print("Workspace configured. Email preview is enabled; messages stay in mail-preview. No SMTP delivery is enabled.")
    print(f"Workspace: {workspace}")
    return config


def configure_email(workspace, config):
    require_terminal()
    mode = prompt("Email mode: off, preview, smtp", config["email"]["mode"]).strip().lower()
    if mode not in ("off", "preview", "smtp"):
        raise SetupError("Choose off, preview or smtp.")
    candidate = json.loads(json.dumps(config))
    mail = candidate["email"]
    mail["mode"] = mode
    if mode == "off":
        mail.update(recipients="", host="", sender="", username="", password="", port=587, security="starttls")
    elif mode == "preview":
        mail.update(recipients=prompt("Preview recipients (comma-separated)", "reviewer@example.test").strip(),
                    host="", sender="", username="", password="", port=587, security="starttls")
    else:
        mail["recipients"] = prompt("Intended recipients (comma-separated)", mail["recipients"] if mail["mode"] == config["email"]["mode"] else "").strip()
        mail["host"] = prompt("SMTP hostname", mail["host"]).strip()
        mail["security"] = prompt("SMTP security: starttls or ssl", "starttls").strip().lower()
        if mail["security"] not in ("starttls", "ssl"):
            raise SetupError("Guided SMTP setup requires starttls or ssl.")
        try:
            mail["port"] = int(prompt("SMTP port", "465" if mail["security"] == "ssl" else "587"))
        except ValueError:
            raise SetupError("SMTP port must be an integer.") from None
        mail["sender"] = prompt("Authorized sender address", mail["sender"]).strip()
        mail["username"] = prompt("SMTP username (empty for an unauthenticated relay)").strip()
        mail["password"] = prompt("SMTP password", secret=True) if mail["username"] else ""
    candidate["stale_hours"] = 24 if prompt("Send stale scheduled-import alerts after 24 hours? (yes/no)", "yes" if config["stale_hours"] else "no").strip().lower() == "yes" else 0
    validate_config(candidate)
    if mode == "smtp":
        print("Automatic delivery will send current eligible alerts and future changes to the configured recipients when start runs.")
        if prompt("Type ENABLE to allow real email delivery") != "ENABLE":
            print("No changes saved. Email delivery remains in its previous mode.")
            return
    save_config(workspace, candidate)
    print(f"Email mode saved: {mode}. Restart a running tracker to apply it.")
    if mode == "preview":
        print(f"Preview files: {workspace / 'mail-preview'}")


def email_test(workspace, config, send=False, recipient=None):
    """Test one generic message; never queue, consume or flush operational alerts."""
    try:
        from . import notifications
    except ImportError:
        import notifications
    if send and (config["email"]["mode"] != "smtp" or not recipient):
        raise SetupError("A send test requires configured SMTP mode and one explicit --to address.")
    if recipient is not None and not send:
        raise SetupError("--to requires --send; the default preview uses a reserved example address.")
    transport = notifications.Config.from_env(email_environment(config)) if send else None
    try:
        recipient = notifications.address(recipient, "--to") if send else "reviewer@example.test"
    except notifications.ConfigError as error:
        raise SetupError(str(error)) from None
    message = EmailMessage(policy=SMTP_POLICY)
    message["From"] = transport.sender if send else "tracker-preview@localhost"
    message["To"] = recipient
    message["Subject"] = "Open Study Tracker: email setup test"
    message.set_content(("This is an explicitly requested setup test from Open Study Tracker.\n" if send else "This is a local preview from Open Study Tracker. No email was sent.\n")
                        + "Configured notification mode: " + config["email"]["mode"] + "\n"
                        "Real status alerts contain operational task IDs and status, without task notes.\n")
    if send:
        try:
            notifications.smtp_send(message, transport, recipient)
        except Exception as error:
            raise SetupError(f"SMTP test failed ({type(error).__name__}). Check hostname, TLS, credentials and sender authorization.") from None
        print("SMTP accepted the test message. Check the recipient inbox; acceptance does not prove inbox delivery.")
        return
    directory = workspace / "mail-preview"
    if directory.is_symlink():
        raise SetupError("The email preview directory must not be a symbolic link.")
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    descriptor, name = tempfile.mkstemp(prefix="setup-preview-", suffix=".eml", dir=directory)
    with os.fdopen(descriptor, "wb") as stream:
        stream.write(message.as_bytes())
    print(f"Local preview saved: {name}")
    print("No SMTP connection or delivery was attempted. This confirms the preview workflow, not SMTP connectivity.")


def bind_address(host, port, config):
    if not 1 <= port <= 65535:
        raise SetupError("Port must be between 1 and 65535.")
    try:
        loopback = host == "localhost" or ipaddress.ip_address(host).is_loopback
    except ValueError:
        raise SetupError("Bind host must be localhost or an IP address.") from None
    if not config["public_url"] and not loopback:
        raise SetupError("Local HTTP mode may bind only to loopback. Configure an HTTPS public URL for team hosting.")
    return socket.AF_INET6 if ":" in host else socket.AF_INET


def start(workspace, config, host="127.0.0.1", port=8080):
    check_expected_url(config)
    family = bind_address(host, port, config)
    # Catch occupied ports before starting an email worker.
    try:
        with socket.socket(family, socket.SOCK_STREAM) as probe:
            if os.name != "nt":
                probe.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            probe.bind((host, port))
    except OSError:
        raise SetupError("The requested listening address is unavailable. Stop the other service or choose another --port.") from None
    env = runtime_environment(workspace, config)
    if (workspace / "mail-preview").is_symlink():
        raise SetupError("The email preview directory must not be a symbolic link.")
    children = []
    old_handler = signal.getsignal(signal.SIGTERM)
    def stop(_signum, _frame):
        raise KeyboardInterrupt
    signal.signal(signal.SIGTERM, stop)
    try:
        web = subprocess.Popen([sys.executable, str(HERE / "server.py"), "--db", env["TRACKER_DB"], "serve", "--host", host, "--port", str(port)], env=env)
        children.append(web)
        connect_host = "::1" if host == "::" else "127.0.0.1" if host in ("0.0.0.0", "localhost") else host
        deadline = time.monotonic() + 30
        while True:
            if web.poll() is not None:
                raise SetupError("The web service stopped during startup. Review its diagnostic above.")
            try:
                with socket.create_connection((connect_host, port), timeout=0.25):
                    break
            except OSError:
                if time.monotonic() >= deadline:
                    raise SetupError("The web service did not become ready within 30 seconds.")
                time.sleep(0.1)
        if config["email"]["mode"] != "off":
            command = [sys.executable, str(HERE / "notifications.py"), "--db", env["TRACKER_DB"], "--interval", str(config["interval"]), "--stale-hours", str(config["stale_hours"])]
            if config["email"]["mode"] == "preview":
                command += ["--preview-dir", str(workspace / "mail-preview")]
            children.append(subprocess.Popen(command, env=env))
        destination = config["public_url"] or f"http://{'[' + host + ']' if ':' in host else host}:{port}"
        print(f"Ready: {destination}\nEmail mode: {config['email']['mode']}. Press Ctrl-C to stop.", flush=True)
        while True:
            if any(child.poll() is not None for child in children):
                raise SetupError("A tracker service exited unexpectedly. Both services have been stopped; review the diagnostics and restart.")
            time.sleep(0.25)
    except KeyboardInterrupt:
        print("Stopping the tracker and email worker.", flush=True)
    finally:
        signal.signal(signal.SIGTERM, old_handler)
        for child in children:
            if child.poll() is None:
                child.terminate()
        for child in children:
            try:
                child.wait(timeout=5)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait()


def doctor(workspace, config):
    check_expected_url(config)
    if not requirements_ready():
        raise SetupError("Pinned shared-server dependencies are missing. Run start to prepare the isolated environment.")
    database = workspace / "tracker.sqlite"
    if not database.is_file() or database.is_symlink():
        raise SetupError("Workspace tracker.sqlite is missing or is not a regular file.")
    with closing(sqlite3.connect(database.as_uri() + "?mode=ro", uri=True)) as db:
        if db.execute("PRAGMA quick_check").fetchone()[0] != "ok":
            raise SetupError("SQLite integrity check failed. Restore a verified backup.")
        if not db.execute("SELECT 1 FROM users WHERE enabled=1 AND role='admin' LIMIT 1").fetchone():
            raise SetupError("No enabled administrator account exists. Enable an administrator using the account commands.")
    print("PASS: private configuration, pinned dependencies, database integrity and enabled administrator.")
    print(f"Access: {'HTTPS team hosting' if config['public_url'] else 'local HTTP on loopback only'}; email: {config['email']['mode']}.")
    print("SMTP connectivity and inbox delivery are not tested by doctor.")


def backup(workspace, output=None):
    source = workspace / "tracker.sqlite"
    if not source.is_file() or source.is_symlink():
        raise SetupError("Workspace database is missing or is not a regular file.")
    target = Path(output).expanduser().resolve() if output else workspace / "backups" / ("tracker-" + datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ") + ".sqlite")
    if target == REPOSITORY or REPOSITORY in target.parents:
        raise SetupError("Store database backups outside the repository.")
    target.parent.mkdir(parents=True, mode=0o700, exist_ok=True)
    descriptor = os.open(target, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    os.close(descriptor)
    try:
        with closing(sqlite3.connect(source.as_uri() + "?mode=ro", uri=True)) as src, closing(sqlite3.connect(target)) as dest:
            src.backup(dest)
            if dest.execute("PRAGMA quick_check").fetchone()[0] != "ok":
                raise SetupError("Backup integrity check failed.")
    except Exception:
        target.unlink(missing_ok=True)
        raise
    print(f"Database backup saved: {target}")
    print("Keep a separate private copy of config.json to preserve the signing key and mail settings.")


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workspace", default=str(DEFAULT_WORKSPACE), help="Private data/configuration directory outside the repository")
    commands = parser.add_subparsers(dest="command")
    init = commands.add_parser("setup", help="Create a workspace, or update its public HTTPS URL")
    init.add_argument("--public-url", default=os.environ.get("TRACKER_SETUP_PUBLIC_URL"))
    init.add_argument("--demo", action="store_true", help="Load fictional tasks into a new workspace")
    launch = commands.add_parser("start", help="Start the shared workspace and its configured email worker")
    launch.add_argument("--host", default="127.0.0.1")
    launch.add_argument("--port", type=int, default=8080)
    commands.add_parser("email", help="Configure off, local preview or SMTP delivery")
    test_mail = commands.add_parser("email-test", help="Preview a generic setup message locally, or explicitly send one test")
    test_mail.add_argument("--send", action="store_true", help="Explicitly send one test using saved SMTP settings")
    test_mail.add_argument("--to", help="One intended recipient, required with --send")
    commands.add_parser("doctor", help="Run offline configuration and storage checks; no SMTP connection")
    export = commands.add_parser("backup", help="Write a consistent, private SQLite backup")
    export.add_argument("--output")
    for name in ACCOUNT_COMMANDS:
        child = commands.add_parser(name)
        if name != "list-users":
            child.add_argument("--username", required=True)
        if name in ("add-user", "set-role"):
            child.add_argument("--role", choices=("viewer", "editor", "admin"), default="editor")
    args = parser.parse_args(argv)
    try:
        if sys.version_info < (3, 10):
            raise SetupError("Python 3.10 or newer is required.")
        workspace = workspace_path(args.workspace)
        command = args.command or "start"
        if command not in ("backup", "email-test"):
            ensure_runtime(workspace, argv, install=command != "doctor")
        if command == "setup":
            setup(workspace, args.public_url, args.demo)
            return 0
        if command == "start" and not (workspace / "config.json").exists():
            setup(workspace, os.environ.get("TRACKER_SETUP_PUBLIC_URL"))
        if command == "backup":
            backup(workspace, args.output)
            return 0
        config = load_config(workspace)
        if command == "start":
            start(workspace, config, getattr(args, "host", "127.0.0.1"), getattr(args, "port", 8080))
        elif command == "email":
            configure_email(workspace, config)
        elif command == "email-test":
            email_test(workspace, config, args.send, args.to)
        elif command == "doctor":
            doctor(workspace, config)
        else:
            arguments = [sys.executable, str(HERE / "server.py"), "--db", str(workspace / "tracker.sqlite"), command]
            if command != "list-users":
                arguments += ["--username", args.username]
            if command in ("add-user", "set-role"):
                arguments += ["--role", args.role]
            return subprocess.call(arguments, env=runtime_environment(workspace, config))
        return 0
    except (SetupError, EOFError) as error:
        print(f"Open Study Tracker setup: {error if isinstance(error, SetupError) else 'Input ended before setup completed.'}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("Setup cancelled; no service remains running.", file=sys.stderr)
        return 130
    except (OSError, sqlite3.Error) as error:
        print(f"Open Study Tracker setup: {type(error).__name__}. Check workspace permissions, paths and available disk space.", file=sys.stderr)
        return 1
    except ValueError:
        print("Open Study Tracker setup: invalid input. Check the documented account and configuration formats.", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
