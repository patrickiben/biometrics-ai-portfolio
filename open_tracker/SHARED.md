# Shared accounts and email alerts

Use the [point-and-click setup guide](SETUP.html) to start a workspace and manage it in the browser. The open-source tracker has no client-specific settings or required mail provider.

## Local setup without terminal steps

1. Download and unzip the complete toolkit.
2. Open **Start Tracker.command** on macOS or **Start Tracker.cmd** on Windows. Install Python 3.10+ with its normal installer if the launcher asks for it.
3. Complete the browser form to create the first administrator. The local launcher carries a temporary setup key privately to that form.
4. Sign in and open **Settings**. Use **People** for accounts, **Email** for notification settings, and **Shared access** for the workspace URL. Download backups from the overview.

The launcher prepares required components automatically. A progress window may appear; no terminal commands are needed. The default workspace is empty and email starts in preview mode. Select the fictional example only if you want sample tasks. Configuration and data stay in your private home-folder workspace, outside the downloaded toolkit. Reopen the launcher to resume.

## Host a team workspace through a browser

The [setup page](SETUP.html#team) includes an optional **Open Render setup** button. It opens your own hosting account for review; a paid service and persistent disk are required. The supplied template disables automatic deployment of later repository changes. You choose and approve any hosting purchase yourself.

After the service becomes ready, open its URL. Copy the generated **TRACKER_SETUP_TOKEN** from the host's **Environment** screen into the setup-key field, then create the first administrator. The setup key cannot create another administrator after initialization. It does not replace account passwords.

The same browser setup works with the [generic Docker browser recipe](deploy/compose.browser.yaml). An operator configures the HTTPS URL, persistent volume and a private setup key in the chosen host. Existing deployments can keep their database and configuration. The public GitHub Pages demo remains a separate offline workspace.

Render is a convenience option, not a client requirement or a dependency of the application. See its [deployment-button documentation](https://render.com/docs/deploy-to-render) and [persistent-disk requirements](https://render.com/docs/disks). The standalone Docker recipe remains available for other suitable hosts.

## Manage the workspace in Settings

| Page | Point-and-click actions |
| --- | --- |
| Overview | Check storage and notification status, open the tracker, and download a consistent database backup. |
| People | Add accounts, set viewer/editor/admin access, reset passwords, and enable or disable accounts. The browser prevents removing the last enabled administrator or locking out the active administrator. |
| Email | Choose off, preview or SMTP; enter provider settings; preview a generic message; explicitly send one test to a chosen address; enable automatic delivery. |
| Shared access | Copy the hosted workspace URL and review the access boundary. A loopback-only workspace is not reachable by colleagues on other computers. |

Only administrators can open these controls. All members can read their workspace's tracker and history. Viewers cannot edit; editors can edit deliverables; administrators can also manage people and settings. Use separate workspaces/services for separate teams when they need separate access boundaries.

Email passwords are never returned to the browser. A blank password field can retain a saved credential when indicated; use the explicit clear control to remove it. Saving email settings applies automatically in the browser-managed runtime. **Enable automatic delivery** and **Send test email** are distinct actions. A test sends one generic message only to the specified address; it does not flush the operational alert queue. Starting automatic SMTP delivery can send currently eligible queued alerts as well as future changes.

Backups contain private workspace data, accounts and history. Store them privately. No user account is automatically subscribed to email: recipient settings are separate. Hosting infrastructure, public DNS and mail-provider authorization remain under the operator's control.

## Advanced and existing command-line workflows

The commands below remain available for operators, automated jobs and existing deployments. The browser-managed runtime is the recommended path for point-and-click setup. The older command-line `start` runtime reads configuration when it starts and requires a restart after changes; the browser runtime applies email settings automatically.

## One-command local start

Run this from the repository root:

```sh
python3 open_tracker/manage.py
```

On Windows, use `py -3 open_tracker/manage.py` and `py -3` in place of `python3` below. The launcher checks the pinned dependencies and creates a private virtual environment if needed. The first run needs internet access to install those packages. You do not need to activate the environment or set environment variables.

Follow the prompts to create your first administrator account and choose whether to load the fictional example. The default workspace is empty. Open **http://127.0.0.1:8080** and sign in. There are no default accounts or passwords.

The server and email-preview worker run together. Leave that terminal open while using the workspace. Press **Ctrl+C** to stop both; run the same command to resume. Your account, session-signing key and data survive restarts. `start` is an explicit alias for the no-argument command:

```sh
python3 open_tracker/manage.py start
```

Local mode listens only on your own computer. Use the team-hosting instructions below to give other people access over HTTPS.

### Where your files go

The default workspace is `~/.open-study-tracker`, where `~` means your user home directory:

| File or directory | Contents |
| --- | --- |
| `tracker.sqlite` | Deliverables, history, accounts, sessions and notification outbox. |
| `config.json` | Host settings, a generated signing secret and any SMTP credentials. Keep this file private. |
| `mail-preview/` | Preview messages as `.eml` files. |
| `backups/` | Database backups created by the backup command. |
| `.venv/` | The managed Python environment when one is needed. |

These files live outside the source checkout. To create a separate workspace, put `--workspace` before the command:

```sh
python3 open_tracker/manage.py --workspace /absolute/path/to/team-workspace
```

Use that same option for every later command concerning that workspace. Each workspace has its own accounts, database and mail settings. If running several local workspaces at once, give each a different port with `start --port 8081`.

## Accounts and permissions

Run these commands on the host that owns the workspace:

```sh
python3 open_tracker/manage.py add-user --username reviewer --role viewer
python3 open_tracker/manage.py add-user --username analyst --role editor
python3 open_tracker/manage.py list-users
python3 open_tracker/manage.py set-password --username reviewer
python3 open_tracker/manage.py set-role --username reviewer --role editor
python3 open_tracker/manage.py disable-user --username reviewer
python3 open_tracker/manage.py enable-user --username reviewer
```

Password commands prompt privately. Passwords must contain 12–256 characters; usernames use 3–64 lowercase letters, digits, dots, underscores or hyphens and start with a letter. Passwords are stored as salted scrypt hashes. Password resets, role changes and account disabling revoke that account's existing sessions.

| Role | Access |
| --- | --- |
| `viewer` | Read, filter and download snapshots. |
| `editor` | Viewer access plus add/edit deliverables. |
| `admin` | Editor access plus browser account/email administration when running the browser-managed service. The lower-level server can still be managed with host commands. |

Everyone with an account can read the entire workspace, including its history and exports. Use separate workspaces and services for separate access boundaries. Public signup, password-recovery email, SSO, MFA and per-study permissions are outside this tool's scope.

Use **Refresh tracker** after another person's edit or a scheduled import. Shared edits save directly to SQLite and record the signed-in account. A stale save returns a conflict instead of overwriting a newer change: keep your draft, refresh, and compare the latest row. Shared mode does not persist task data in browser storage; the light/dark preference may be stored there.

## Email: preview first, connect your service when ready

```sh
python3 open_tracker/manage.py email
```

Choose a mode in the guided prompts:

| Mode | Behavior |
| --- | --- |
| `preview` | The initial mode. Writes `.eml` files in `mail-preview/`, using a reserved example recipient. It never connects to SMTP. |
| `off` | Disables automatic notification processing. |
| `smtp` | Delivers through your configured SMTP service after you explicitly type `ENABLE`. |

After changing email settings, stop the running launcher with **Ctrl+C** and start it again. Starting in SMTP mode can send queued alerts to the configured recipients.

To check the email preview immediately, including in an empty workspace:

```sh
python3 open_tracker/manage.py email-test
```

Open the `.eml` file whose path is printed. This sample does not contact SMTP or change the notification queue. To try automatic operational alerts, sign in and create or change a synthetic task to **Blocked** or **At risk**. Wait up to 60 seconds for the worker's next poll, then open the `.eml` file in `mail-preview/`. Previewed operational messages remain eligible for later live delivery.

For SMTP, have these details ready:

- SMTP hostname and port from your chosen service.
- Encryption mode: STARTTLS, commonly on port 587, or implicit TLS on port 465.
- A sender address authorized by that service.
- Username and password if the service requires authentication.
- The intended recipient addresses.

SMTP credentials are entered through prompts, with the password hidden, and kept in the private workspace configuration. The wizard does not require a particular provider. Your provider may require an app password, an approved sending domain or administrator permission; use the SMTP values it supplies. Merely saving configuration does not verify that a provider will accept mail.

For an optional live connection test, keep the launcher stopped, configure SMTP mode, and replace `you@example.org` below with a real address you control:

```sh
python3 open_tracker/manage.py email-test --send --to you@example.org
```

This explicitly sends one generic test message to that address. It does not flush queued operational alerts. Check your inbox and provider logs; SMTP acceptance alone does not prove inbox delivery. Start the launcher when you want automatic delivery to begin.

Notifications contain operational IDs/status and an optional tracker link, not task notes or full history. A shared account does not automatically subscribe someone to email; recipients are configured separately.

### Which notifications are sent

Alerts are queued when a task enters **At risk** or **Blocked**. An unchanged import or a note edit with the same status does not enqueue another status alert. If several transitions occur between polls, only the latest still-current status is considered. Resolved or superseded pending alerts are canceled; a send already in progress cannot be recalled.

Daily digests cover unfinished overdue tasks and, when configured, stale scheduled imports. A changed exception set can produce an updated digest within the same UTC day. A manual edit does not refresh the scheduled-import heartbeat. The guided setup disables stale-import alerts initially. In the email wizard, enable the 24-hour check if your workspace uses scheduled imports; overdue alerts remain enabled in preview or SMTP mode.

Each recipient has an independent delivery record. Failures remain queued with retry delays. Delivery is **at least once**: a crash after SMTP acceptance but before recording success can cause a duplicate on retry. Successful SMTP acceptance does not prove inbox delivery. Adding a recipient affects subsequent transitions and current digests; it does not replay all historical transitions. Removed recipients' pending messages are canceled.

## Check setup and back up

```sh
python3 open_tracker/manage.py doctor
python3 open_tracker/manage.py backup
```

`doctor` checks the local configuration, dependencies and database, showing actionable results without revealing credentials or sending mail. It does not test public DNS, firewall rules or inbox delivery. `backup` uses SQLite's backup facility and writes a new timestamped database in the workspace's `backups/` directory. To choose a destination:

```sh
python3 open_tracker/manage.py backup --output /absolute/path/to/backup.sqlite
```

A backup contains the workspace's accounts, history and notification records. Keep it private. Keep a protected copy of `config.json` separately if you need to restore the signing key and SMTP settings. Do not commit either file to the public repository.

| Symptom | Next step |
| --- | --- |
| Python is not found | Install Python 3.10+; use `py -3` on Windows or `python3` on macOS/Linux. |
| Initial dependency installation fails | Check network access and Python's virtual-environment support, then rerun the launcher. |
| Port 8080 is already in use | Stop the other process or use `start --port 8081` and open that port. |
| Another computer cannot open local mode | Local mode is loopback-only. Set up the HTTPS team host below. |
| No preview files appear | Run `email-test` for an immediate sample. For automatic alerts, confirm preview mode, restart after configuration changes and create a synthetic at-risk or blocked task. |
| Live alerts do not arrive | Run `doctor`, confirm SMTP mode and recipients, restart the launcher, then review the worker's counts and your provider's delivery logs. |
| Edits conflict | Preserve your draft, refresh the tracker and compare the latest row before saving. |
| Data appears missing after restart | Check the `--workspace` path. Every workspace is independent. |

## Team hosting with Docker Compose

Use the supplied recipe on a Linux host with Docker Engine and the Compose plugin. You choose the host and hostname. Point that hostname's DNS records to the host, and make ports **80 and 443** available to Caddy. Those are the prerequisites for its [automatic certificate issuance and renewal](https://caddyserver.com/docs/automatic-https). A private-network deployment with its own certificate authority needs its own TLS configuration.

From a complete checkout on that host, copy the [team settings template](deploy/team.env.example) to a private location outside the repository:

```sh
cp open_tracker/deploy/team.env.example /private/path/team.env
```

Replace `/private/path/team.env` with a file in an existing directory you control. Edit its one setting, `TRACKER_PUBLIC_URL`, to the full HTTPS URL for your hostname. Use the same absolute file path in each command below. This file selects the host; account passwords and mail credentials are entered through the setup prompts.

```sh
docker compose --env-file /private/path/team.env -f open_tracker/deploy/compose.yaml run --rm --build tracker setup
docker compose --env-file /private/path/team.env -f open_tracker/deploy/compose.yaml up -d --build
```

The first command builds the tracker and prompts for the first account. The second starts the tracker, automatic preview worker and HTTPS proxy. Open your configured URL and sign in. Caddy manages certificates and redirects HTTP to HTTPS; the tracker port is not published directly. The private configuration and database use a persistent Docker volume. Services restart automatically after failure or host restart when Docker starts.

Use the same manager inside the running tracker container:

```sh
docker compose --env-file /private/path/team.env -f open_tracker/deploy/compose.yaml exec tracker python /app/open_tracker/manage.py --workspace /data add-user --username reviewer --role viewer
docker compose --env-file /private/path/team.env -f open_tracker/deploy/compose.yaml exec tracker python /app/open_tracker/manage.py --workspace /data email
docker compose --env-file /private/path/team.env -f open_tracker/deploy/compose.yaml exec tracker python /app/open_tracker/manage.py --workspace /data doctor
```

After changing email settings, restart the tracker to apply them:

```sh
docker compose --env-file /private/path/team.env -f open_tracker/deploy/compose.yaml restart tracker
```

For status and logs, use `ps` or `logs --tail 100` after the same Compose options. For a database backup, replace the manager command above with `backup`; the result is in `/data/backups` in the persistent volume. Use [Compose copy](https://docs.docker.com/reference/cli/docker/compose/cp/) to save previews or backups to a private local directory when you need them:

```sh
docker compose --env-file /private/path/team.env -f open_tracker/deploy/compose.yaml cp tracker:/data/mail-preview /private/path/mail-preview
docker compose --env-file /private/path/team.env -f open_tracker/deploy/compose.yaml cp tracker:/data/backups /private/path/backups
```

Run the preview worker or backup command first so the source directory exists. Keep backup copies in a separate protected location for recovery. `docker compose down` stops the services while keeping their volumes; `down -v` deletes the volumes and their data.

Keep one deployment's hostname, environment-file path and Compose project name consistent across commands. Separate services and volumes are needed for separate team access boundaries. If using more than one deployment on a machine, set distinct project names with `--project-name`; plan separate host port/proxy routing as well, because each supplied stack uses ports 80 and 443.

If the URL does not open, check DNS and inbound ports, then `logs --tail 100 proxy`. The manager's `doctor` checks the tracker locally; it cannot verify whether the internet can reach your host. The recipe uses standard [Docker Compose environment-file support](https://docs.docker.com/compose/how-tos/environment-variables/variable-interpolation/) and [Caddy](https://caddyserver.com/docs/automatic-https), so it can move between suitable hosts without a provider-specific account or SDK.

## Existing deployments and integrations

The lower-level commands remain available: [server.py](server.py) runs accounts and the web service; [notifications.py](notifications.py) runs the email worker; [tracker.py](tracker.py) imports and exports the same database. Scheduled R/SAS jobs can continue using the [data contract and bridge examples](README.md).

The guided launcher reads its private JSON configuration. The lower-level server and worker continue to read environment variables; see [shared.env.example](deploy/shared.env.example). The [web systemd unit](deploy/open-tracker.service) and [email systemd unit](deploy/open-tracker-alerts.service) remain templates for operators who already use that deployment style. Adjust their paths and create the service account and data directory before use. Run one managed launcher or one server/worker pair per database, rather than starting both styles together.

Shared hosting requires HTTPS for secure session cookies. The server checks allowed hosts, CSRF tokens and account roles, and uses expiring server-side sessions. It does not trust forwarded headers; proxy users share the proxy peer's IP login limit. A host operator with file access can bypass application permissions. This is an operational collaboration tool with tested controls, not regulatory validation or an external security certification.

## Development checks

```sh
python3 -m venv /path/to/test-environment
/path/to/test-environment/bin/python -m pip install -r open_tracker/requirements-shared.txt
/path/to/test-environment/bin/python -m unittest discover -s open_tracker/tests -v
```

Use `Scripts/python.exe` in place of `bin/python` for a Windows virtual environment. Tests cover setup, accounts, permissions, sessions, CSRF, conflicting edits, notification rules, retries and the offline import/export workflow. Email tests use local fixtures and simulated SMTP.

Reference documentation: [Flask security](https://flask.palletsprojects.com/en/stable/web-security/), [Waitress deployment](https://flask.palletsprojects.com/en/stable/deploying/waitress/) and [Python SMTP client](https://docs.python.org/3/library/smtplib.html).
