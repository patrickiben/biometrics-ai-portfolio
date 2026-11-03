# Browser validation harness and seeded-defect run

This adapter executes the toolkit's original ten validation gates and frozen 18-case defect registry. It adapts scheduling and runtime boundaries; the canonical structural checks, R computations, mutation application and outcome classification remain the source implementation.

The browser workflow is a self-test of the reviewed toolkit snapshot. It does not execute uploaded R/Python project code, certify client data, run native SAS or grant study approval. G5 remains a manual record, G7 remains unsigned, and G10 checks whether recorded mutation evidence still matches the registry and runner sources. A partial defect run is labelled partial and cannot replace full-run evidence.

The Python package check still reports its unscanned formats. PDF text extraction needs a native executable unavailable in this browser adapter; PDF content is therefore not checked here. Office XML and other supported source formats retain the canonical checks. Native/CI document QC remains separate evidence.

## Integration

Load the complete reviewed public source inventory into the Python virtual filesystem. `source_requirements()` lists essential files and R package requirements; it is not a reduced source inventory. `validate_source_manifest(root, paths)` verifies an inventory supplied by the same publication filter as the site build.

```python
runtime = ValidationRuntime(
    '/project', run_r_command,
    required_source_hashes=reviewed_code_hashes,
    runner_files=('browser_modules/workbench/runtime.mjs',
                  'browser_modules/workbench/python-worker.mjs'),
)
ledger = await runtime.harness()
summary = await runtime.teeth()       # all 18 registered cases
downloads = runtime.export_files()    # [{path, base64}], current evidence only
```

Supply the actual bridge source paths in `runner_files`; these join the canonical gate fingerprints so a bridge change makes prior sensitivity evidence stale. `last_log` retains run diagnostics. An exception preserves partial logs as evidence; it does not manufacture a completed result.

The worker exposes `validation-init` and `validation-harness` with an empty options object, and `validation-teeth` with `{only: ""}` for the full registry or comma-separated frozen defect IDs for a partial run. Results include `ok` (execution completed), the ledger or summary, `files` and `last_log`. A completed execution can contain red, stale, manual or unsigned gates; `ok` does not mean scientific approval or that every gate passed. The UI reports those states separately. After a full defect run, **Recheck gates with this evidence** runs the harness in the same workspace and adds its ledger to the download without discarding defect evidence.

The async R callback receives `{argv, cwd, root, files, deleted, profile, release_root}`. File entries have a safe relative `path` and base64 bytes. Root switches send a complete R input snapshot and identify the previous root for removal. Subsequent commands send changed files and removals. All R sources are included for the parse gate; original simulation, interpretation and app data are also supplied. Large binary publications remain in Python for the package scanner.

The callback returns `{returncode, stdout, stderr, files, deleted}`. It must provide a fresh Rscript-equivalent environment, emulate `commandArgs`, trap `quit`/`q` as exit status, source the deterministic model-free profile and return changed output files. It must not reuse a failed command's prior output as success. The bridge is strictly sequential; mutation copies and their R environments are discarded independently.

The adapter converts only command-dependent canonical Python functions into async functions. Fixed Python checks execute in the worker; fixed R calls execute in webR. No shell or subprocess is used in the browser. Native tests below use a separate native R callback solely to compare the adapter with the original runtime.

## Developer checks

```sh
python3 -m unittest discover -s browser_modules/validation/tests -v
python3 browser_modules/validation/tests/run_native_qc.py --source /path/to/disposable/public-snapshot --output /path/to/qc-evidence --full-teeth
PLAYWRIGHT_MODULE=/absolute/path/to/playwright node browser_modules/validation/tests/browser.cjs http://127.0.0.1:8000 /path/to/browser-evidence full
```

Browser execution and network checks belong in the complete workbench browser suite. Native callback tests alone are not proof of webR/Pyodide execution.
