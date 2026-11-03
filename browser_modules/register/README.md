# Browser study deliverable register

Open `index.html` through the toolkit website. Start blank, add records or explicitly load all 132 canonical records from `biostat_pipeline/_register.json`. The source starter remains unchanged. Every original reference field remains editable and is retained in complete JSON, CSV and print exports.

The page supports study labels, guided record editing, removal, undo, stage/status filters, all-field search and atomic JSON/CSV replacement imports. Filters never limit exports. Unsaved row edits must be saved or discarded before other state-changing actions or exports. JSON is the lossless interchange format; CSV adds a protective apostrophe to spreadsheet formula-like values and retains that apostrophe on import.

Records exist only in tab memory. No study content is stored in browser persistent storage, sent to a model or posted to a service. The only application data fetch is the public reference starter after a user click. The shared toolkit theme stores only its light/dark preference. Export JSON before leaving or reloading.

Statuses and QC text are planning notes. Neither entering “Review recorded” nor exporting a file creates an approval, signature or audit trail. Review the starter's scientific, regulatory and workflow references for the study's actual requirements.

Developer checks:

```sh
node --test browser_modules/register/tests/core.test.mjs
PLAYWRIGHT_MODULE=/absolute/path/to/playwright node browser_modules/register/tests/browser.cjs http://127.0.0.1:8000 /absolute/path/to/qc-output
```

The browser check exercises actual inputs, exports, malformed imports, undo/reset, theme changes, phone layout, literal rendering of imported markup, tab-memory privacy and the absence of external data requests. It needs a local static server and Chrome; neither is required by toolkit users.
