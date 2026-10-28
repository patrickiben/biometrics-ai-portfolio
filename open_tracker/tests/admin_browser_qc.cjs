/* Browser setup/admin regressions with disposable accounts, data and simulated SMTP.
 * NODE_PATH=/path/to/node_modules TRACKER_PYTHON=/path/to/venv/bin/python \
 *   CHROME_PATH=/path/to/chrome node open_tracker/tests/admin_browser_qc.cjs
 * No SMTP connection is made. QA_OUTPUT_DIR selects the retained evidence folder.
 */
const { chromium } = require("playwright");
const assert = require("node:assert/strict"),
  fs = require("node:fs"),
  os = require("node:os"),
  path = require("node:path"),
  cp = require("node:child_process"),
  crypto = require("node:crypto");
const root = path.resolve(__dirname, "../.."),
  python = process.env.TRACKER_PYTHON || "python3";
const temp = fs.mkdtempSync(path.join(os.tmpdir(), "tracker-admin-fixture-"));
const output =
  process.env.QA_OUTPUT_DIR ||
  fs.mkdtempSync(path.join(os.tmpdir(), "tracker-admin-browser-"));
fs.mkdirSync(output, { recursive: true });
const workspace = path.join(temp, "workspace"),
  deliveries = path.join(temp, "deliveries.json");
const token = crypto.randomBytes(36).toString("hex"),
  password = "Synthetic-" + crypto.randomBytes(20).toString("hex");
const secondPassword = "Replacement-" + crypto.randomBytes(20).toString("hex"),
  smtpPassword = "SMTP-" + crypto.randomBytes(24).toString("hex");
const report = {
  started_at: new Date().toISOString(),
  scenarios: [],
  errors: [],
  screenshots: [],
  smtp_transport: "simulated; no network",
  external_email_sent: false,
};
let browser,
  serverProcess,
  base,
  dismissNextDialog = false;
const errors = [],
  requests = [],
  dialogs = [];
async function scenario(name, fn) {
  await fn();
  report.scenarios.push({ name, passed: true });
  console.log("PASS " + name);
}
async function shot(page, name) {
  const viewport = page.viewportSize();
  await page.evaluate(() => scrollTo(0, 0));
  const height = await page.evaluate(
    () => document.documentElement.scrollHeight,
  );
  if (height > viewport.height)
    await page.setViewportSize({ width: viewport.width, height });
  await page.evaluate(
    () =>
      new Promise((resolve) =>
        requestAnimationFrame(() => requestAnimationFrame(resolve)),
      ),
  );
  await page.screenshot({ path: path.join(output, name) });
  if (height > viewport.height) await page.setViewportSize(viewport);
  report.screenshots.push(name);
}
async function newPage(context, url) {
  const p = await context.newPage();
  p.on("pageerror", (e) => errors.push(e.message));
  p.on("request", (r) => requests.push({ url: r.url(), method: r.method() }));
  p.on("dialog", (d) => {
    dialogs.push(d.message());
    if (dismissNextDialog) {
      dismissNextDialog = false;
      d.dismiss();
    } else d.accept();
  });
  await p.goto(url);
  return p;
}
async function adminState(page) {
  return await page.evaluate(async () => {
    const r = await fetch("/api/admin/state");
    if (!r.ok) throw Error("Admin status " + r.status);
    return r.json();
  });
}
async function waitState(page, test, timeout = 5000) {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    const value = await adminState(page);
    if (test(value)) return value;
    await page.waitForTimeout(100);
  }
  throw Error("Workspace status did not reach expected state");
}
async function login(page, username = "owner", secret = password) {
  await page.locator("#login-username").fill(username);
  await page.locator("#login-password").fill(secret);
  await page.locator("#login-form button[type=submit]").click();
  await page.locator("#admin-shell").waitFor({ state: "visible" });
}
async function person(page, username, role = "viewer", secret = password) {
  await page.locator("#add-person").click();
  await page.locator("#person-username").fill(username);
  await page.locator("#person-role").selectOption(role);
  await page.locator("#person-password").fill(secret);
  await page.locator("#person-confirm").fill(secret);
  await page.locator("#save-person").click();
  await page.locator("#person-dialog").waitFor({ state: "hidden" });
}
function records() {
  return fs.existsSync(deliveries)
    ? JSON.parse(fs.readFileSync(deliveries, "utf8"))
    : [];
}
(async () => {
  const fixture = `import os,sys,json,threading,signal\nsys.path.insert(0,sys.argv[1])\nfrom open_tracker import web_setup,notifications\nfrom waitress import create_server\nrecords=[]\nlock=threading.Lock()\ndef simulated(message,config,recipient):\n with lock:\n  records.append({'recipient':recipient,'subject':message['Subject'],'body':message.get_content()})\n  with open(sys.argv[3],'w') as f: json.dump(records,f)\nnotifications.smtp_send=simulated\napp=web_setup.create_web_app(sys.argv[2],setup_token=os.environ['TRACKER_QA_TOKEN'],env={'TRACKER_DESKTOP_INSTANCE':'synthetic-admin-browser-instance'})\ns=create_server(app,host='127.0.0.1',port=0)\nstopped=threading.Event()\nworker=web_setup.NotificationWorker(app,stopped)\ndef stop(*args):\n if stopped.is_set(): return\n stopped.set()\n s.trigger.pull_trigger(lambda: s.asyncore.close_all(map=s._map))\napp.extensions['tracker_stop']=stop\nworker.start()\nfor name in ('SIGTERM','SIGINT'):\n if hasattr(signal,name):signal.signal(getattr(signal,name),stop)\nprint('READY '+str(s.effective_port),flush=True)\ntry:s.run()\nfinally:\n worker.stop()\n s.close()\n s.task_dispatcher.shutdown()\n`;
  const env = { ...process.env, TRACKER_QA_TOKEN: token };
  for (const key of Object.keys(env)) {
    if (key.startsWith("TRACKER_") && key !== "TRACKER_QA_TOKEN")
      delete env[key];
  }
  serverProcess = cp.spawn(
    python,
    ["-u", "-c", fixture, root, workspace, deliveries],
    { env, stdio: ["ignore", "pipe", "pipe"] },
  );
  const logs = [];
  serverProcess.stdout.on("data", (d) => logs.push(d.toString()));
  serverProcess.stderr.on("data", (d) => logs.push(d.toString()));
  base = await new Promise((resolve, reject) => {
    const timeout = setTimeout(
      () => reject(Error("Server did not start: " + logs.join(""))),
      30000,
    );
    serverProcess.stdout.on("data", (d) => {
      const m = d.toString().match(/READY (\d+)/);
      if (m) {
        clearTimeout(timeout);
        resolve("http://127.0.0.1:" + m[1]);
      }
    });
    serverProcess.once("exit", (code) => {
      clearTimeout(timeout);
      reject(Error("Server exited " + code + ": " + logs.join("")));
    });
  });
  browser = await chromium.launch({
    headless: true,
    ...(process.env.CHROME_PATH
      ? { executablePath: process.env.CHROME_PATH }
      : {}),
  });
  const context = await browser.newContext({
    viewport: { width: 1440, height: 1000 },
    acceptDownloads: true,
  });
  await scenario(
    "Public administration copy has a clear setup link and never calls a server API",
    async () => {
      const p = await newPage(
        context,
        "file://" + path.join(root, "open_tracker/admin.html"),
      );
      await p.locator("#static-panel").waitFor({ state: "visible" });
      assert.equal(await p.locator("#setup-panel").isVisible(), false);
      assert.equal(
        await p.locator("#static-panel a").getAttribute("href"),
        "https://patrickiben.github.io/biometrics-ai-portfolio/open_tracker/SETUP.html",
      );
      assert.ok(!requests.some((r) => r.url.includes("/api/")));
      await shot(p, "admin-static-fallback.png");
      await p.close();
    },
  );
  const page = await newPage(context, base + "/setup");
  await scenario(
    "First-account setup rejects a wrong key, then consumes a private fragment key",
    async () => {
      await page.locator("#setup-panel").waitFor({ state: "visible" });
      await page.locator("#setup-token").fill("wrong-key");
      await page.locator("#setup-username").fill("owner");
      await page.locator("#setup-password").fill(password);
      await page.locator("#setup-confirm").fill(password + "-mismatch");
      await page.locator("#setup-form button[type=submit]").click();
      await page.waitForFunction(() =>
        document
          .getElementById("setup-error")
          .textContent.includes("do not match"),
      );
      await page.locator("#setup-confirm").fill(password);
      await page.locator("#setup-form button[type=submit]").click();
      await page.waitForFunction(() =>
        document
          .getElementById("setup-error")
          .textContent.includes("setup key"),
      );
      assert.equal(await page.locator("#admin-shell").isVisible(), false);
      await page.goto(base + "/setup#setup-token=" + token);
      await page.locator("#setup-panel").waitFor({ state: "visible" });
      await page.waitForFunction(() => !location.hash);
      assert.equal(new URL(page.url()).hash, "");
      assert.equal(await page.locator("#setup-token-field").isVisible(), false);
      await shot(page, "first-account-setup.png");
      await page.locator("#setup-username").fill("owner");
      await page.locator("#setup-password").fill(password);
      await page.locator("#setup-confirm").fill(password);
      await page.locator("#setup-demo").check();
      await page.locator("#setup-form button[type=submit]").click();
      await page.locator("#admin-shell").waitFor({ state: "visible" });
      assert.equal(await page.locator("#account-count").textContent(), "1");
      assert.equal(
        await page.locator("#email-mode-label").textContent(),
        "Preview",
      );
      assert.equal(await page.locator("#setup-password").inputValue(), "");
      assert.ok(!requests.some((r) => r.url.includes(token)));
    },
  );
  await scenario(
    "People can be added, assigned roles, reset, disabled and enabled by clicks",
    async () => {
      await page.getByRole("tab", { name: "People", exact: true }).click();
      await person(page, "reviewer", "viewer");
      await person(page, "analyst", "editor");
      assert.equal(await page.locator(".person").count(), 3);
      await page
        .getByRole("button", { name: "Change role for analyst", exact: true })
        .click();
      await page.locator("#person-role").selectOption("viewer");
      await page.locator("#save-person").click();
      await page.locator("#person-dialog").waitFor({ state: "hidden" });
      await page
        .getByRole("button", {
          name: "Reset password for analyst",
          exact: true,
        })
        .click();
      await page.locator("#person-password").fill(secondPassword);
      await page.locator("#person-confirm").fill(secondPassword);
      await page.locator("#save-person").click();
      await page.locator("#person-dialog").waitFor({ state: "hidden" });
      await page
        .getByRole("button", { name: "Disable for analyst", exact: true })
        .click();
      await page
        .getByRole("button", { name: "Enable for analyst", exact: true })
        .waitFor();
      await page
        .getByRole("button", { name: "Enable for analyst", exact: true })
        .click();
      await page
        .getByRole("button", { name: "Disable for analyst", exact: true })
        .waitFor();
      assert.equal(
        await page
          .getByRole("button", { name: "Disable for owner", exact: true })
          .isDisabled(),
        true,
      );
      const state = await adminState(page);
      assert.equal(
        state.users.find((x) => x.username === "analyst").role,
        "viewer",
      );
      assert.equal(
        state.users.find((x) => x.username === "analyst").enabled,
        1,
      );
    },
  );
  await scenario(
    "Viewer can use the tracker but has no workspace-settings button or admin access",
    async () => {
      const c = await browser.newContext();
      const viewer = await newPage(c, base + "/");
      await viewer.locator("#login-panel").waitFor({ state: "visible" });
      await viewer.locator("#login-username").fill("reviewer");
      await viewer.locator("#login-password").fill(password);
      await viewer.locator("#login-submit").click();
      await viewer.locator("#workspace-shell").waitFor({ state: "visible" });
      assert.equal(await viewer.locator("#admin-link").isVisible(), false);
      assert.equal(
        await viewer.evaluate(
          async () => (await fetch("/api/admin/state")).status,
        ),
        403,
      );
      await viewer.goto(base + "/admin");
      await viewer.locator("#restricted-panel").waitFor({ state: "visible" });
      assert.equal(await viewer.locator("#admin-shell").isVisible(), false);
      await c.close();
      const tracker = await newPage(context, base + "/");
      await tracker.locator("#admin-link").waitFor({ state: "visible" });
      assert.equal(
        await tracker.locator("#admin-link").getAttribute("href"),
        "/admin",
      );
      await tracker.close();
    },
  );
  await scenario(
    "Local previews and paused notifications need no SMTP service or restart",
    async () => {
      await page.getByRole("tab", { name: "Email", exact: true }).click();
      await page.locator("#preview-email").click();
      await page.locator("#email-preview").waitFor({ state: "visible" });
      assert.match(
        await page.locator("#email-preview").textContent(),
        /No email was sent/,
      );
      assert.deepEqual(records(), []);
      await page.locator("input[name=mail-mode][value=off]").check();
      await page.locator("#email-form button[type=submit]").click();
      await page.waitForFunction(
        () => document.getElementById("email-mode-label").textContent === "Off",
      );
      await waitState(page, (s) => s.worker.status === "off");
      assert.deepEqual(records(), []);
      assert.equal(await page.locator("#send-test").isDisabled(), true);
    },
  );
  await scenario(
    "Live SMTP requires explicit consent and never exposes saved credentials",
    async () => {
      await page.locator("input[name=mail-mode][value=smtp]").check();
      for (const [id, value] of [
        ["mail-recipients", "alerts@example.test"],
        ["mail-host", "smtp.example.test"],
        ["mail-sender", "sender@example.test"],
        ["mail-username", "synthetic-account"],
        ["mail-password", smtpPassword],
      ])
        await page.locator("#" + id).fill(value);
      const before = requests.filter(
        (r) => r.method === "POST" && r.url.endsWith("/api/admin/email"),
      ).length;
      await page.locator("#email-form button[type=submit]").click();
      await page.waitForTimeout(100);
      assert.equal(
        requests.filter(
          (r) => r.method === "POST" && r.url.endsWith("/api/admin/email"),
        ).length,
        before,
      );
      await page.locator("#mail-confirm-live").check();
      await page.locator("#email-form button[type=submit]").click();
      await page.waitForFunction(
        () =>
          document.getElementById("email-mode-label").textContent ===
          "Live email",
      );
      assert.equal(await page.locator("#mail-password").inputValue(), "");
      const value = await adminState(page);
      assert.equal(value.email.password_configured, true);
      assert.equal("password" in value.email, false);
      assert.ok(!JSON.stringify(value).includes(smtpPassword));
      assert.equal(await page.locator("#mail-confirm-live").isChecked(), false);
      await shot(page, "admin-smtp-desktop.png");
      await page.setViewportSize({ width: 390, height: 844 });
      assert.equal(
        await page.evaluate(
          () => document.documentElement.scrollWidth > innerWidth + 2,
        ),
        false,
      );
      await shot(page, "admin-smtp-mobile.png");
      await page.setViewportSize({ width: 1440, height: 1000 });
    },
  );
  await scenario(
    "A confirmed test sends one generic message only to its selected recipient",
    async () => {
      await page.locator("#test-recipient").fill("not-an-email");
      const attempts = requests.filter(
        (r) => r.method === "POST" && r.url.endsWith("/api/admin/email-test"),
      ).length;
      await page.locator("#send-test").click();
      assert.equal(
        requests.filter(
          (r) => r.method === "POST" && r.url.endsWith("/api/admin/email-test"),
        ).length,
        attempts,
      );
      await page.locator("#test-recipient").fill("test-reader@example.test");
      dismissNextDialog = true;
      await page.locator("#send-test").click();
      assert.equal(
        requests.filter(
          (r) => r.method === "POST" && r.url.endsWith("/api/admin/email-test"),
        ).length,
        attempts,
      );
      await page.locator("#send-test").click();
      await page.waitForFunction(() =>
        document
          .getElementById("message")
          .textContent.includes("accepted the test"),
      );
      const sent = records().filter(
        (x) => x.subject === "Open Study Tracker: email setup test",
      );
      assert.equal(sent.length, 1);
      assert.equal(sent[0].recipient, "test-reader@example.test");
      assert.ok(!sent[0].body.includes("DEMO-"));
      assert.ok(dialogs.some((x) => x.includes("test-reader@example.test")));
      const before = sent.length;
      await page.locator("#preview-email").click();
      assert.equal(
        records().filter(
          (x) => x.subject === "Open Study Tracker: email setup test",
        ).length,
        before,
      );
      await page.locator("input[name=mail-mode][value=off]").check();
      await page.locator("#email-form button[type=submit]").click();
      await page.waitForFunction(
        () => document.getElementById("email-mode-label").textContent === "Off",
      );
      const value = await waitState(page, (s) => s.worker.status === "off");
      assert.equal(value.email.password_configured, true);
    },
  );
  await scenario(
    "Saved SMTP credentials can be explicitly removed while notifications are off",
    async () => {
      await page.locator("input[name=mail-mode][value=smtp]").check();
      await page.locator("#mail-password").fill(smtpPassword + "-replacement");
      assert.equal(
        await page.locator("#mail-clear-password").isDisabled(),
        true,
      );
      await page.locator("#mail-password").fill("");
      await page.locator("#mail-clear-password").check();
      assert.equal(await page.locator("#mail-password").isDisabled(), true);
      await page.locator("#mail-clear-password").uncheck();
      assert.equal(await page.locator("#mail-password").isDisabled(), false);
      await page.locator("input[name=mail-mode][value=off]").check();
      await page.locator("#mail-clear-password").check();
      await page.locator("#email-form button[type=submit]").click();
      await page.waitForFunction(
        () => document.getElementById("mail-saved-password-field").hidden,
      );
      let saved = await adminState(page);
      assert.equal(saved.email.mode, "off");
      assert.equal(saved.email.password_configured, false);
      assert.equal(saved.email.username, "synthetic-account");
      assert.equal(
        await page.locator("#mail-clear-password").isChecked(),
        false,
      );
      await page.reload();
      await page.locator("#admin-shell").waitFor({ state: "visible" });
      saved = await adminState(page);
      assert.equal(saved.email.password_configured, false);
      assert.equal("password" in saved.email, false);
      await page.getByRole("tab", { name: "Email", exact: true }).click();
      await page.locator("input[name=mail-mode][value=smtp]").check();
      await page.locator("#mail-confirm-live").check();
      const attempts = requests.filter(
        (r) => r.method === "POST" && r.url.endsWith("/api/admin/email"),
      ).length;
      await page.locator("#email-form button[type=submit]").click();
      await page.waitForFunction(() =>
        document
          .getElementById("email-error")
          .textContent.includes("needs a password"),
      );
      assert.equal(
        requests.filter(
          (r) => r.method === "POST" && r.url.endsWith("/api/admin/email"),
        ).length,
        attempts,
      );
      await page.reload();
      await page.locator("#admin-shell").waitFor({ state: "visible" });
    },
  );
  await scenario(
    "Database backups download and local access is not presented as a team invitation",
    async () => {
      await page.getByRole("tab", { name: "Overview", exact: true }).click();
      const wait = page.waitForEvent("download");
      await page.locator("#backup").click();
      const download = await wait;
      const buffer = fs.readFileSync(await download.path());
      assert.ok(
        buffer.subarray(0, 16).toString().startsWith("SQLite format 3"),
      );
      await page
        .getByRole("tab", { name: "Shared access", exact: true })
        .click();
      assert.match(
        await page.locator("#sharing-note").textContent(),
        /not a team invitation link/,
      );
      assert.equal(await page.locator("#sharing-address").inputValue(), base);
    },
  );
  await scenario(
    "Hosted sharing displays the configured team URL and omits local shutdown",
    async () => {
      await page.route("**/api/admin/state", async (route) => {
        const response = await route.fetch();
        const data = await response.json();
        await route.fulfill({
          response,
          json: {
            ...data,
            local: false,
            public_url: "https://workspace.example.test",
            can_stop: false,
          },
        });
      });
      await page.locator("#refresh-state").click();
      await page.waitForFunction(
        () =>
          document.getElementById("sharing-title").textContent ===
          "Invite your team",
      );
      assert.equal(
        await page.locator("#sharing-address").inputValue(),
        "https://workspace.example.test",
      );
      assert.equal(
        await page.locator("#copy-address").textContent(),
        "Copy team address",
      );
      assert.equal(await page.locator("#stop-local").isVisible(), false);
      await page.unroute("**/api/admin/state");
      await page.locator("#refresh-state").click();
      await page.waitForFunction(
        () =>
          document.getElementById("sharing-title").textContent ===
          "This workspace is local",
      );
    },
  );
  await scenario(
    "All admin tabs work in both themes and at phone width without document overflow",
    async () => {
      for (const theme of ["light", "dark"]) {
        for (
          let attempt = 0;
          attempt < 2 &&
          (await page.locator("html").getAttribute("data-theme")) !== theme;
          attempt++
        )
          await page.locator(".theme-toggle").click();
        assert.equal(
          await page.locator("html").getAttribute("data-theme"),
          theme,
        );
        await page.reload();
        await page.locator("#admin-shell").waitFor({ state: "visible" });
        assert.equal(
          await page.locator("html").getAttribute("data-theme"),
          theme,
        );
        for (const tab of ["Overview", "People", "Email", "Shared access"]) {
          await page.getByRole("tab", { name: tab, exact: true }).click();
          await page.setViewportSize({ width: 1440, height: 1000 });
          assert.equal(
            await page.evaluate(
              () => document.documentElement.scrollWidth > innerWidth + 2,
            ),
            false,
          );
          if (tab === "Overview" || tab === "Email")
            await shot(
              page,
              "admin-" + theme + "-" + tab.toLowerCase() + "-desktop.png",
            );
          await page.setViewportSize({ width: 390, height: 844 });
          assert.equal(
            await page.evaluate(
              () => document.documentElement.scrollWidth > innerWidth + 2,
            ),
            false,
          );
          if (tab === "People" || tab === "Email")
            await shot(
              page,
              "admin-" + theme + "-" + tab.toLowerCase() + "-mobile.png",
            );
        }
      }
      await page.setViewportSize({ width: 1440, height: 1000 });
    },
  );
  await scenario(
    "Secrets never enter browser storage and self password reset clears the admin session",
    async () => {
      const saved = await page.evaluate(() => ({
        local: { ...localStorage },
        session: { ...sessionStorage },
      }));
      assert.ok(Object.keys(saved.local).every((k) => k === "bp-theme"));
      assert.deepEqual(saved.session, {});
      for (const secret of [token, password, smtpPassword])
        assert.ok(!JSON.stringify(saved).includes(secret));
      await page.getByRole("tab", { name: "People", exact: true }).click();
      await page
        .getByRole("button", { name: "Reset password for owner", exact: true })
        .click();
      await page.locator("#person-password").fill(secondPassword);
      await page.locator("#person-confirm").fill(secondPassword);
      await page.locator("#save-person").click();
      await page.locator("#login-panel").waitFor({ state: "visible" });
      assert.equal(await page.locator("#people-list").textContent(), "");
      assert.equal(await page.locator("#mail-password").inputValue(), "");
      await page.locator("#login-username").fill("owner");
      await page.locator("#login-password").fill(password);
      await page.locator("#login-form button[type=submit]").click();
      await page.waitForFunction(
        () => document.getElementById("login-error").textContent.length > 0,
      );
      assert.equal(await page.locator("#admin-shell").isVisible(), false);
      await login(page, "owner", secondPassword);
    },
  );
  await scenario(
    "Keyboard tabs, failed saves, and duplicate-submit prevention remain usable",
    async () => {
      await page.getByRole("tab", { name: "Overview", exact: true }).click();
      await page.getByRole("tab", { name: "Overview", exact: true }).focus();
      await page.keyboard.press("ArrowRight");
      assert.equal(
        await page
          .getByRole("tab", { name: "People", exact: true })
          .getAttribute("aria-selected"),
        "true",
      );
      await page.keyboard.press("End");
      assert.equal(
        await page
          .getByRole("tab", { name: "Shared access", exact: true })
          .getAttribute("aria-selected"),
        "true",
      );
      await page.keyboard.press("Home");
      assert.equal(
        await page
          .getByRole("tab", { name: "Overview", exact: true })
          .getAttribute("aria-selected"),
        "true",
      );
      await page.getByRole("tab", { name: "Email", exact: true }).click();
      await page.locator("input[name=mail-mode][value=preview]").check();
      let saves = 0;
      await page.route("**/api/admin/email", async (route) => {
        saves++;
        await new Promise((resolve) => setTimeout(resolve, 200));
        await route.fulfill({
          status: 503,
          contentType: "application/json",
          body: JSON.stringify({
            error: "Notification settings could not be saved. Try again.",
          }),
        });
      });
      await page.locator("#email-form button[type=submit]").click();
      assert.equal(
        await page.locator("#email-form button[type=submit]").isDisabled(),
        true,
      );
      await page.waitForFunction(() =>
        document
          .getElementById("email-error")
          .textContent.includes("could not be saved"),
      );
      assert.equal(saves, 1);
      assert.equal(
        await page.locator("input[name=mail-mode][value=preview]").isChecked(),
        true,
      );
      assert.equal(
        await page.locator("#email-form button[type=submit]").isDisabled(),
        false,
      );
      await page.unroute("**/api/admin/email");
      await page.locator("#email-form button[type=submit]").click();
      await page.waitForFunction(
        () =>
          document.getElementById("email-mode-label").textContent === "Preview",
      );
      await page.getByRole("tab", { name: "People", exact: true }).click();
      await page.locator("#add-person").click();
      await page.locator("#person-username").fill("cancelled");
      await page.keyboard.press("Escape");
      assert.equal(await page.locator("#person-dialog").isVisible(), false);
      assert.ok(
        !(await adminState(page)).users.some((x) => x.username === "cancelled"),
      );
    },
  );
  await scenario(
    "Local close button stops the service after saving data and no JavaScript errors occurred",
    async () => {
      await page.getByRole("tab", { name: "Overview", exact: true }).click();
      await page.locator("#stop-local").click();
      await page.locator("#closed-panel").waitFor({ state: "visible" });
      assert.equal(await page.locator("#admin-shell").isVisible(), false);
      const deadline = Date.now() + 5000;
      while (serverProcess.exitCode === null && Date.now() < deadline)
        await new Promise((resolve) => setTimeout(resolve, 100));
      assert.notEqual(
        serverProcess.exitCode,
        null,
        "Local close must stop the service",
      );
      assert.deepEqual(errors, []);
      assert.ok(
        requests.every(
          (r) => r.url.startsWith(base) || r.url.startsWith("file://"),
        ),
      );
    },
  );
  report.passed = true;
})()
  .catch((error) => {
    report.passed = false;
    report.errors.push(error.stack);
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => {
    if (browser) await browser.close();
    if (serverProcess && serverProcess.exitCode === null) {
      serverProcess.kill("SIGTERM");
      await new Promise((resolve) => {
        const timer = setTimeout(() => {
          serverProcess.kill("SIGKILL");
          resolve();
        }, 5000);
        serverProcess.once("exit", () => {
          clearTimeout(timer);
          resolve();
        });
      });
    }
    report.errors.push(...errors);
    report.completed_at = new Date().toISOString();
    fs.writeFileSync(
      path.join(output, "report.json"),
      JSON.stringify(report, null, 2),
    );
    fs.rmSync(temp, { recursive: true, force: true });
    console.log("Evidence: " + output);
  });
