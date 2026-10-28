# Shared accounts and email alerts

Open Study Tracker has an optional self-hosted server for people who need a shared tracker. Everyone signs in with an individual account and reads the same local SQLite database. An independent email worker observes recorded changes and delivers queued notifications through your SMTP service. The server and worker are open source under the repository's MIT license.

**Scope:** these are reusable setup instructions for consultants and employees, not a service configured for a specific client. Shared access needs hosting; live email needs SMTP configuration. Both are optional. Local sign-in and email previews let you evaluate the features before choosing any deployment.

The GitHub Pages demo remains an offline workspace. GitHub Pages cannot host the Python server, user accounts, or email worker. Run these on a machine you control; keep the database and environment file outside the published repository.

## Start a local shared workspace

Use Python 3.10+ and run from the repository root:

```sh
python3 -m venv open_tracker/.venv
open_tracker/.venv/bin/python -m pip install -r open_tracker/requirements-shared.txt
mkdir -p open_tracker/out
open_tracker/.venv/bin/python open_tracker/server.py --db open_tracker/out/shared.sqlite add-user --username patrick --role admin
```

The account command prompts for the password twice. Passwords are stored as salted scrypt hashes. There are no default accounts or passwords. Windows users can use `open_tracker\.venv\Scripts\python.exe` in place of the Unix virtual-environment executable.

Set a random session-signing key and enable HTTP only for this loopback preview:

```sh
export TRACKER_SECRET_KEY="$(python3 -c 'import secrets; print(secrets.token_hex(32))')"
export TRACKER_INSECURE_LOCAL=1
open_tracker/.venv/bin/python open_tracker/server.py --db open_tracker/out/shared.sqlite serve --host 127.0.0.1 --port 8080
```

Open `http://127.0.0.1:8080` and sign in. Start with an empty shared workspace or import the fictional example with the standard CLI:

```sh
python3 open_tracker/tracker.py --db open_tracker/out/shared.sqlite upsert --csv open_tracker/examples/status.csv --actor synthetic-demo
```

Use **Refresh** in the shared workspace after a scheduled import or another user's edit. Shared mode saves directly to SQLite, does not store task data in localStorage (only the light/dark preference may be stored there), and records the authenticated username. Stale saves return a conflict instead of overwriting newer work; preserve your edits, refresh, and compare the current row before trying again. A manual edit does not refresh the scheduled-import heartbeat.

## Accounts and permissions

| Role | Access |
| --- | --- |
| `viewer` | Read, filter and download snapshots. |
| `editor` | Viewer access plus add/edit deliverables. |
| `admin` | Current web permissions match editor. Account administration remains a server-local command. |

Account commands run on the host with database access:

```sh
open_tracker/.venv/bin/python open_tracker/server.py --db open_tracker/out/shared.sqlite add-user --username reviewer --role viewer
open_tracker/.venv/bin/python open_tracker/server.py --db open_tracker/out/shared.sqlite set-password --username reviewer
open_tracker/.venv/bin/python open_tracker/server.py --db open_tracker/out/shared.sqlite disable-user --username reviewer
open_tracker/.venv/bin/python open_tracker/server.py --db open_tracker/out/shared.sqlite list-users
```

Passwords must contain 12–256 characters. Usernames use 3–64 lowercase letters, digits, dots, underscores or hyphens and start with a letter. Password reset, account disabling, and role changes revoke existing sessions. Use `set-role --username reviewer --role editor` to change access or `enable-user --username reviewer` to restore a disabled account. Logout revokes its session server-side. Login attempts are rate-limited. There is no public signup, password-recovery email, SSO, per-study access partitioning, or MFA. Everyone granted an account can read the entire tracker, including its operational history and exports. Use separate databases/services when teams need separate access boundaries.

## Preview notifications without sending

The worker is disabled until `TRACKER_ALERT_TO` is configured. A preview writes `.eml` files locally; it never connects to SMTP and does not mark mail as delivered.

```sh
TRACKER_ALERT_TO=reviewer@example.test python3 open_tracker/notifications.py --db open_tracker/out/shared.sqlite --once --preview-dir open_tracker/out/mail-preview
```

The example address is reserved for demonstration. Open the generated `.eml` files to review their contents. Notification messages contain operational IDs/status and an optional tracker link, not task notes or the full change history.

## Enable automatic delivery

Configure your SMTP server and intended recipients in the worker's environment. Use your service manager or a private environment file with restricted permissions. See [the example configuration](deploy/shared.env.example). Credentials are never command-line arguments.

| Variable | Purpose |
| --- | --- |
| `TRACKER_ALERT_TO` | Comma-separated recipient email addresses; unset disables the worker. |
| `TRACKER_SMTP_HOST` | Your SMTP hostname. |
| `TRACKER_SMTP_PORT` | Usually `587` for STARTTLS or `465` for implicit TLS. |
| `TRACKER_SMTP_SECURITY` | `starttls` (default) or `ssl`; `plain` is restricted to loopback testing. |
| `TRACKER_SMTP_FROM` | Sender address authorized by your SMTP provider. |
| `TRACKER_SMTP_USERNAME` / `TRACKER_SMTP_PASSWORD` | SMTP authentication if required. |
| `TRACKER_PUBLIC_URL` | Optional HTTP(S) link included in notifications. |

Start the worker with the same database as the web server or scheduled import:

```sh
python3 open_tracker/notifications.py --db /absolute/path/to/shared.sqlite --interval 60
```

The loop checks for changes every 60 seconds. Alternatively, schedule `--once` with cron or Task Scheduler. Run only one worker per database in normal operation; database leases protect against overlapping workers.

Alerts are queued when a task enters **At risk** or **Blocked**. Re-running an unchanged import or editing a note while the status stays the same does not enqueue another status alert. If several transitions happen between worker polls, only the latest still-current status is considered. Resolved/superseded pending alerts are canceled. A send already in flight cannot be recalled. If an identical digest was already sent that UTC day, disappearance and recurrence of that same exception set does not send it again that day. Daily digests cover unfinished overdue tasks and stale scheduled imports; a changed exception set can trigger an updated digest within the same UTC day. Use `--stale-hours 0` to disable stale-import alerts for a workspace maintained entirely by people; overdue alerts remain enabled. The default stale threshold is 24 hours. An empty workspace does not produce a stale-data email.

The outbox records a separate delivery for each recipient. Failures remain queued with exponential retry delays. Delivery is **at least once**: a crash after SMTP accepts a message but before the database marks it sent can result in a duplicate on retry. A stable Message-ID helps mail clients recognize it. Successful SMTP acceptance does not prove inbox receipt. Previewed messages remain eligible for later real delivery when sending is enabled. Removed recipients' pending messages are canceled; adding a recipient affects subsequent transitions and current digests, without replaying already-consumed status transitions. Restart a running worker after changing its environment.

## Host for a team

Run the web service with Waitress behind an HTTPS reverse proxy. Leave it bound to `127.0.0.1`; expose only the proxy. Unset `TRACKER_INSECURE_LOCAL` for team access so cookies require HTTPS. Store a stable, random `TRACKER_SECRET_KEY` of at least 32 characters in the service environment. Restarting with a different signing key logs users out. Set `TRACKER_ALLOWED_HOSTS` to your public hostname (for example `tracker.example.org`); the default allows only `localhost`, `127.0.0.1` and `[::1]`. The application rejects other Host headers, does not trust forwarded headers, and does not add permissive cross-origin access. A reverse proxy must preserve the intended Host header. Rate limiting sees the proxy address, so proxied users share its IP limit; configure edge limits for the expected team size. Local HTTP mode additionally requires a loopback peer and host.

The server uses CSRF tokens for mutations, HttpOnly/SameSite cookies, expiring server-side sessions, and role checks on each request. The web routes expose neither SQLite files nor account records. Downloads contain task data and history; an authorized viewer can share them outside the server.

Example systemd units are provided for [the web server](deploy/open-tracker.service) and [the email worker](deploy/open-tracker-alerts.service). Adjust paths and create the service account and data directory first. These are deployment templates, not an installed service. Use your platform's HTTPS proxy and process supervision. Keep the database on local disk, back it up, and restrict host access: file-level access can bypass application permissions.

The server is a small operational collaboration tool. It has no claim of regulatory validation, tamper-evident history, or enterprise identity management. Its security controls have automated tests, but it has not undergone an external penetration test.

## Validate

```sh
open_tracker/.venv/bin/python -m unittest discover -s open_tracker/tests -v
```

Tests cover accounts, permissions, sessions, CSRF, conflicting edits, notification rules, deduplication, retries, TLS configuration, and the offline import/export workflow. Tests use local fixtures and simulated SMTP; they do not email real recipients.

The server configuration follows the official [Flask security guidance](https://flask.palletsprojects.com/en/stable/web-security/) and [Waitress deployment guidance](https://flask.palletsprojects.com/en/stable/deploying/waitress/). The worker uses Python's [SMTP client](https://docs.python.org/3/library/smtplib.html).
