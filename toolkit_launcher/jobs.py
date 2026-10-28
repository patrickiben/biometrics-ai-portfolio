"""Allowlisted local toolkit jobs. This module never invokes a shell or a model.

The launcher owns process supervision and logs. These adapters describe the exact
commands to supervise and prepare isolated copies with the original relative paths.
"""
from __future__ import annotations

import json
import hashlib
import os
from pathlib import Path
import re
import shutil
import socket
import sys
import tempfile
from urllib.parse import urlsplit

SOURCE_ROOT = Path(__file__).resolve().parents[1]

SHINY = {
    "trialmon": ("Synthetic safety review", "sasr_monitoring_wiki/trialmon_shiny", "sasr_monitoring_wiki/trialmon_shiny/data"),
    "lifecycle": ("Study lifecycle monitor", "lifecycle_dashboard/shiny", "lifecycle_dashboard/shiny/data"),
    "uat": ("IRT / RTSM UAT tracker", "uat_irt/shiny", "uat_irt/templates"),
    "risk": ("Operational risk signals", "risk_monitor/shiny", "risk_monitor/shiny/data"),
    "hours": ("Hours reconciliation", "budget_reconciliation/shiny", "budget_reconciliation/templates"),
}

ANALYSIS_PACKAGES = ("dplyr", "tidyr", "stringr", "purrr", "tibble", "rtables", "ggplot2", "ggrepel", "patchwork", "emmeans", "lme4", "lmerTest", "pbkrtest", "nlme", "broom", "broom.mixed", "jsonlite")

TEETH_PACKAGES = ("testthat", "shiny", "bslib", "DT", "ggplot2", "htmltools")


class JobError(ValueError):
    """A reviewable setup issue, suitable for display in the launcher."""


def _contained(path: Path, root: Path) -> bool:
    try:
        path.relative_to(root)
        return True
    except ValueError:
        return False


def detect_runtimes(settings: dict | None = None) -> dict:
    """Find user-installed runtimes, including GUI launches with a minimal PATH."""
    settings = settings or {}
    if not isinstance(settings, dict):
        raise JobError("Runtime settings must be an object.")
    guesses = {
        "r": ["/Library/Frameworks/R.framework/Resources/bin/Rscript"],
        "quarto": ["/Applications/quarto/bin/quarto"],
        "bash": ["/bin/bash"],
        "rsync": ["/usr/bin/rsync"],
        "sas": [],
        "model": ["/Applications/Ollama.app/Contents/Resources/ollama"],
    }
    names = {"r": "Rscript", "quarto": "quarto", "bash": "bash", "rsync": "rsync", "sas": "sas", "model": "ollama"}
    for key, name in names.items():
        guesses[key] += [f"/usr/local/bin/{name}", f"/opt/homebrew/bin/{name}"]
    if os.name == "nt":
        program_files = Path(os.environ.get("ProgramFiles", "C:/Program Files"))
        guesses["r"] += [str(p) for p in sorted((program_files / "R").glob("R-*/bin/Rscript.exe"), reverse=True)]
        guesses["quarto"] += [str(program_files / "Quarto/bin/quarto.exe"), str(program_files / "Quarto/bin/quarto.cmd")]
        guesses["bash"] += [str(program_files / "Git/bin/bash.exe")]
    result = {"python": {"available": True, "path": str(Path(sys.executable).resolve())}}
    for key, name in names.items():
        configured = settings.get(key) or settings.get(key + "_path") or None
        if configured is not None and (not isinstance(configured, str) or not Path(configured).expanduser().is_file()
                                       or not os.access(Path(configured).expanduser(), os.X_OK)):
            result[key] = {"available": False, "path": None, "message": "The selected runtime file does not exist."}
            continue
        path = str(Path(configured).expanduser().absolute()) if configured else shutil.which(name)
        if not path:
            path = next((p for p in guesses[key] if Path(p).is_file() and os.access(p, os.X_OK)), None)
        result[key] = {"available": bool(path), "path": str(Path(path).absolute()) if path else None,
                       "message": "Found; the module check verifies its dependencies." if path else "Choose an installed executable or use the installer link."}
    urls = {"r": "https://cran.r-project.org/", "quarto": "https://quarto.org/docs/get-started/", "python": "https://www.python.org/downloads/",
            "bash": "https://gitforwindows.org/", "rsync": "https://rsync.samba.org/", "sas": "https://www.sas.com/", "model": "https://ollama.com/download"}
    for key, item in result.items():
        item["install_url"] = urls.get(key)
    return result


def _project(path: str | Path) -> Path:
    root = Path(path).expanduser().resolve()
    if root == SOURCE_ROOT or _contained(root, SOURCE_ROOT):
        raise JobError("Jobs run in an isolated project, not in the toolkit checkout.")
    if not root.is_dir() or not (root / "launch_app.R").is_file():
        raise JobError("The working project is incomplete. Create a toolkit project first.")
    return root


def _safe_path(root: Path, relative: str) -> Path:
    path = root / relative
    if not _contained(path.resolve(), root) or any(p.is_symlink() for p in [path, *path.parents] if _contained(p, root)):
        raise JobError("A project path points outside its working folder.")
    return path


def _r_vector(items) -> str:
    return "c(" + ",".join(json.dumps(str(x)) for x in items) + ")"


def _package_check(packages) -> str:
    return ("p <- " + _r_vector(packages) + "; "
            "bad <- p[!vapply(p, requireNamespace, logical(1), quietly=TRUE)]; "
            "for (x in setdiff(p,bad)) cat(x,as.character(utils::packageVersion(x)),'\\n'); "
            "if(length(bad)) stop('Missing packages: ',paste(bad,collapse=', ')); "
            "cat('Required packages are available.\\n')")


def _study_lock_checks(root: Path) -> tuple[str, str]:
    """Build base-R checks from the actual lock, including transitive packages."""
    path = _safe_path(root, "study/renv.lock")
    try:
        if path.stat().st_size > 2 * 1024 * 1024:
            raise ValueError()
        lock = json.loads(path.read_text(encoding="utf-8"))
        r_version = lock["R"]["Version"]
        packages = {name: record["Version"] for name, record in lock["Packages"].items()}
        if not isinstance(r_version, str) or not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", r_version) or not packages:
            raise ValueError()
        for name, version in packages.items():
            if not re.fullmatch(r"[A-Za-z][A-Za-z0-9.]*", name) or not isinstance(version, str) or not re.fullmatch(r"[0-9][A-Za-z0-9.\-]*", version):
                raise ValueError()
    except (ValueError, KeyError, AttributeError, TypeError, OSError) as exc:
        raise JobError("The study lockfile is missing or invalid. Create a new project from a complete toolkit download.") from exc
    r_check = (
        "expected_r <- " + json.dumps(r_version) + "; actual_r <- as.character(getRversion()); "
        "if(!identical(actual_r,expected_r)) stop('This worked study requires R ',expected_r,"
        "' exactly (study/renv.lock); found R ',actual_r,'. Install and select that R version in Runtime settings, "
        "then choose Restore pinned study packages.',call.=FALSE); "
        "cat('Pinned R version:',actual_r,'\\n'); "
    )
    package_check = (
        r_check + "expected <- setNames(" + _r_vector(packages.values()) + "," + _r_vector(packages) + "); "
        "problems <- character(); "
        "for(p in names(expected)) { "
        "loaded <- requireNamespace(p,quietly=TRUE); "
        "actual <- if(loaded) as.character(utils::packageDescription(p,fields='Version')) else 'not available'; "
        "if(!loaded || length(actual)!=1L || is.na(actual) || !identical(actual,unname(expected[[p]]))) "
        "problems <- c(problems,paste0(p,': expected ',expected[[p]],', found ',paste(actual,collapse=', '))) "
        "else cat(p,actual,'at',find.package(p),'\\n'); }; "
        "if(length(problems)) stop('Restore pinned study packages before checking or rebuilding this study.\\n',"
        "paste(problems,collapse='\\n'),call.=FALSE); "
        "cat('All',length(expected),'locked package versions match study/renv.lock.\\n')"
    )
    return r_check, package_check


def _free_port() -> int:
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def _r_temporary_directory(preferred: Path) -> Path:
    """R rejects whitespace in R_TempDir, even when its argv is correctly quoted."""
    if not re.search(r"\s", str(preferred)):
        return preferred
    base = Path(tempfile.gettempdir()).resolve()
    if re.search(r"\s", str(base)) and os.name == "nt":
        import ctypes
        buffer = ctypes.create_unicode_buffer(32768)
        size = ctypes.windll.kernel32.GetShortPathNameW(str(base), buffer, len(buffer))
        if size:
            base = Path(buffer.value)
    if re.search(r"\s", str(base)):
        raise JobError("R needs a temporary folder without spaces. Select a project location without spaces and try again.")
    suffix = hashlib.sha256(str(preferred).encode()).hexdigest()[:24]
    path = base / ("toolkit-r-" + suffix)
    if path.is_symlink() or (path.exists() and hasattr(os, "getuid") and path.stat().st_uid != os.getuid()):
        raise JobError("The private R temporary folder is not owned by this user.")
    path.mkdir(mode=0o700, exist_ok=True)
    return path


def _runtime_path(runtime: dict, key: str) -> str:
    item = runtime.get(key, {})
    path = item.get("path") if isinstance(item, dict) else item
    if not path:
        raise JobError(f"{key} is not installed or could not be found. Use the setup link, then check again.")
    return str(path)


def action_catalog() -> dict:
    actions = {}

    def add(action_id, label, module, needs=("r",), install=False, long=False, description=""):
        actions[action_id] = {"label": label, "module_id": module, "needs": list(needs), "install": install,
                              "long_running": long, "description": description}

    for app in SHINY:
        add(f"shiny.{app}.check", "Check R packages", app)
        add(f"shiny.{app}.install", "Install missing R packages", app, install=True,
            description="Download missing packages from CRAN into this project's private library.")
        add(f"shiny.{app}.run", "Launch local app", app, long=True,
            description="Start the app on this computer. Use Stop when finished.")
    add("study.check", "Check pinned study dependencies", "study", ("r", "quarto"),
        description="Verify the exact R version and every package version recorded in study/renv.lock.")
    add("study.install", "Restore pinned study packages", "study", install=True,
        description="Download the versions recorded in study/renv.lock into a private project library.")
    add("study.run", "Rebuild worked study", "study", ("r", "quarto"), description="Regenerate the synthetic design, ADaM, analysis, QC and CSR outputs.")
    add("sandbox.run", "Rebuild synthetic sandbox", "sandbox", description="Base R simulation and analysis; text drafting uses the clearly labelled deterministic stub.")
    add("carryover.check", "Run carryover known-answer checks", "carryover")
    add("carryover.run", "Run full carryover study", "carryover", description="2,000 replicates per cell, then known-answer checks, tables and figures. This can take a long time.")
    add("cqtc.check", "Run hysteresis area tests", "cqtc")
    add("cqtc.run", "Run full hysteresis study", "cqtc", description="1,000 replicates per scenario; retains the complete outputs and generated page.")
    add("interpretation.check", "Test number-grounding validator", "interpretation", description="Runs the faithful and invented-number controls without a model.")
    add("analysis.check", "Check analysis dependencies", "analysis", description="Check the R packages required by this generated study package.")
    add("analysis.install", "Install analysis dependencies", "analysis", install=True, description="Download missing R packages into this private project's library.")
    add("analysis.run", "Run configured analysis and QC", "analysis", description="Run the selected generated package in a new results folder. Completion does not grant scientific approval.")
    add("r_tlf.check", "Parse R template library", "r_tlf", description="Syntax check only; this does not run the templates on study data.")
    add("harness.run", "Run validation gates", "harness", ("r", "python"), description="Regenerate the evidence ledger; manual review and sign-off gates remain manual.")
    add("teeth.check", "Check defect-test dependencies", "teeth", ("r", "python"))
    add("teeth.install", "Install defect-test R packages", "teeth", install=True)
    add("teeth.run", "Run seeded-defect study", "teeth", ("r", "python"), description="Run the existing seeded-defect controls in disposable private copies. This can take a long time.")
    for action in actions.values():
        action["options"] = []
    actions["carryover.run"]["options"] = [{"id": "cores", "label": "Processor cores", "type": "number", "default": min(4, os.cpu_count() or 1),
                                             "min": 1, "max": 8, "step": 1, "description": "Windows uses one core because this R workflow uses forked workers."}]
    return actions


def build_plan(action_id: str, project_root: str | Path, options: dict | None = None, settings: dict | None = None) -> dict:
    """Build fixed argv lists; no user input is treated as code or a shell command."""
    actions = action_catalog()
    if action_id not in actions:
        raise JobError("Unknown toolkit action.")
    options = options or {}
    if not isinstance(options, dict):
        raise JobError("Job options must be an object.")
    action = actions[action_id]
    allowed = {"allow_install"} if action["install"] else set()
    if action_id.startswith("shiny.") and action_id.endswith(".run"):
        allowed.add("port")
    if action_id == "carryover.run":
        allowed.add("cores")
    if action_id.startswith("analysis."):
        allowed.update({"module_id", "build_id"})
    if set(options) - allowed:
        raise JobError("Unexpected job option: " + ", ".join(sorted(set(options) - allowed)))
    if action["install"] and options.get("allow_install") is not True:
        raise JobError("Enable package downloads before starting this installation.")
    root = _project(project_root)
    runtime = detect_runtimes(settings)
    for requirement in action["needs"]:
        _runtime_path(runtime, requirement)
    r = _runtime_path(runtime, "r") if "r" in action["needs"] else None
    private = root.parent / "runtime"
    library = private / "r-library"
    temporary = private / "tmp"
    for folder in (private, library, temporary):
        if folder.is_symlink() or not _contained(folder.resolve(), root.parent.resolve()):
            raise JobError("The project's runtime directory must stay inside its private project folder.")
        folder.mkdir(parents=True, exist_ok=True)
    temporary = _r_temporary_directory(temporary)
    executable_dirs = [str(Path(item["path"]).parent) for item in runtime.values() if item.get("path")]
    env = {
        # R_LIBS precedes R_LIBS_USER at startup. Clear inherited search-path
        # overrides so an older CI/user library cannot shadow the private pins.
        "R_LIBS": "", "BIOMETRICS_R_LIB": str(library), "R_LIBS_USER": str(library),
        "RENV_PATHS_LIBRARY": str(private / "study-library"), "RENV_PATHS_CACHE": str(private / "renv-cache"),
        "RENV_CONFIG_AUTOLOADER_ENABLED": "FALSE", "RENV_CONFIG_PPM_ENABLED": "FALSE",
        "TMPDIR": str(temporary), "TMP": str(temporary), "TEMP": str(temporary),
        "PATH": os.pathsep.join(dict.fromkeys(executable_dirs)) + os.pathsep + os.environ.get("PATH", ""),
        "RETICULATE_PYTHON": sys.executable,
        "TOOLKIT_RSCRIPT": r or "", "TOOLKIT_PYTHON": sys.executable,
    }
    if runtime["quarto"]["available"]:
        env["QUARTO"] = runtime["quarto"]["path"]
    commands = []
    outputs = []
    plan = {"commands": commands, "outputs": outputs, "long_running": action["long_running"]}

    def command(argv, cwd=root, extra=None):
        if not Path(cwd).is_dir():
            raise JobError("The module folder is missing from this project.")
        commands.append({"argv": [str(a) for a in argv], "cwd": str(cwd), "env": dict(env, **(extra or {}))})

    def script(relative, cwd=root, args=(), extra=None):
        path = _safe_path(root, relative)
        if not path.is_file():
            raise JobError(f"The project is missing {relative}. Create a new complete project.")
        command([r, "--vanilla", str(path), *args], cwd=cwd, extra=extra)

    if action_id.startswith("analysis."):
        from . import analysis_jobs
        module_id, build_id = options.get("module_id"), options.get("build_id")
        try:
            analysis_jobs.resolve_build(root, module_id, build_id)
        except ValueError as error:
            raise JobError(str(error)) from None
        packages = ANALYSIS_PACKAGES if module_id in {"r_tlf", "sas_tlf"} else ("jsonlite",)
        if action_id == "analysis.install":
            expr = ("p <- " + _r_vector(packages) + "; "
                    "missing <- p[!vapply(p,requireNamespace,logical(1),quietly=TRUE)]; "
                    "if(length(missing)) utils::install.packages(missing,lib=Sys.getenv('R_LIBS_USER'),repos='https://cloud.r-project.org'); " + _package_check(packages))
            command([r, "--vanilla", "-e", expr], extra={"USE_BUNDLED_LIBUV": "1"})
        elif action_id == "analysis.check":
            command([r, "--vanilla", "-e", _package_check(packages)])
        else:
            runner = SOURCE_ROOT / "toolkit_launcher/analysis_runner.R"
            if not runner.is_file():
                raise JobError("The installed analysis engine is missing. Download the current toolkit.")
            try:
                run, relative = analysis_jobs.prepare_run(root, module_id, build_id)
            except ValueError as error:
                raise JobError(str(error)) from None
            command([r, "--vanilla", "-e", _package_check(packages)])
            command([sys.executable, str(SOURCE_ROOT / "toolkit_launcher/analysis_jobs.py"), str(Path(run["run_root"]) / "plan.json"), r])
            names = ["analysis_report.html", "results.zip", "qc.json", "execution_status.csv", "output_manifest.json", "software_versions.csv", "execution_error.json"]
            outputs.extend(relative + "/" + name for name in names)
            plan["failure_outputs"] = list(outputs)
            plan["output_labels"] = {relative + "/" + name: label for name, label in zip(names, ["Analysis report (HTML)", "Complete results (ZIP)", "Automated QC (JSON)", "Output status (CSV)", "Output manifest (JSON)", "Software versions (CSV)", "Execution error (JSON)"])}
            plan["analysis"] = {"module_id": module_id, "build_id": build_id, "run_id": run["run_id"]}
    elif action_id.startswith("shiny."):
        _, app, verb = action_id.split(".")
        args = ["--check", app]
        if verb == "install":
            args.append("--install")
        elif verb == "run":
            port = options.get("port", _free_port())
            if type(port) is not int or not 1024 <= port <= 65535:
                raise JobError("Choose a local app port from 1024 to 65535.")
            args = [app, "--no-browser", "--port", str(port)]
            plan["url"] = f"http://127.0.0.1:{port}/"
        script("launch_app.R", args=args)
        outputs.append(SHINY[app][2])
    elif action_id.startswith("study."):
        r_check, pinned_check = _study_lock_checks(root)
        study_lib = str(private / "study-library")
        study_env = {"R_LIBS_USER": os.pathsep.join((study_lib, str(library)))}
        if action_id == "study.install":
            # renv::restore receives explicit external library/cache paths. It may
            # download packages, and is reachable only through an install action.
            # Fail before any package or network operation when R differs from
            # the lock. Bootstrapping renv uses the generic private library;
            # the restored versions are checked in a fresh R process afterward.
            expr = (r_check + "lib <- Sys.getenv('R_LIBS_USER'); dir.create(lib,recursive=TRUE,showWarnings=FALSE); "
                    "if(!requireNamespace('renv',quietly=TRUE)) utils::install.packages('renv',lib=lib,repos='https://cloud.r-project.org'); "
                    "renv::restore(project='study', library=Sys.getenv('RENV_PATHS_LIBRARY'), prompt=FALSE)")
            command([r, "--vanilla", "-e", expr])
            command([r, "--vanilla", "-e", pinned_check], extra=study_env)
        else:
            command([r, "--vanilla", "-e", pinned_check], extra=study_env)
            if action_id == "study.run":
                script("study/run_all.R", extra=study_env)
        outputs += ["study/index.html", "study/run_manifest.json", "study/04_analysis", "study/05_qc", "study/06_csr"]
    elif action_id == "sandbox.run":
        helper = _safe_path(root, "toolkit_launcher/stub_profile.R")
        expr = "source(commandArgs(TRUE)[1]); source('sim_lifecycle/run_lifecycle.R')"
        command([r, "--vanilla", "-e", expr, str(helper)])
        outputs.append("sim_lifecycle/out")
    elif action_id.startswith("carryover."):
        if action_id == "carryover.run":
            cores = options.get("cores", min(4, os.cpu_count() or 1))
            if type(cores) is not int or not 1 <= cores <= 8:
                raise JobError("Carryover cores must be an integer from 1 to 8.")
            if os.name == "nt":
                cores = 1  # R's mclapply does not fork on Windows.
            script("sim_lifecycle/carryover_oc/R/run_oc.R", extra={"OC_CORES": str(cores)})
        script("sim_lifecycle/carryover_oc/tests/test_carryover.R")
        if action_id == "carryover.run":
            script("sim_lifecycle/carryover_oc/R/tables.R")
        outputs += ["sim_lifecycle/carryover_oc/out", "sim_lifecycle/carryover_oc/index.html"]
    elif action_id == "cqtc.check":
        script("cqtc_hysteresis/tests/test_area.R")
    elif action_id == "cqtc.run":
        script("cqtc_hysteresis/R/run_oc.R")
        outputs += ["cqtc_hysteresis/out", "cqtc_hysteresis/index.html"]
    elif action_id == "interpretation.check":
        script("tlf_interpret/selftest.R", cwd=_safe_path(root, "tlf_interpret"))
    elif action_id == "r_tlf.check":
        expr = ("files <- list.files('r_tlf_pseudocode',pattern='[.]R$',recursive=TRUE,full.names=TRUE); "
                "stopifnot(length(files)>0); bad <- files[vapply(files,function(f) inherits(try(parse(f),silent=TRUE),'try-error'),logical(1))]; "
                "if(length(bad)) stop('Parse errors: ',paste(bad,collapse=', ')); "
                "cat(length(files),'R programs parsed. Syntax only; templates were not executed.\\n')")
        command([r, "--vanilla", "-e", expr])
    elif action_id == "harness.run":
        helper = _safe_path(root, "toolkit_launcher/native_harness.py")
        if not helper.is_file():
            raise JobError("The portable harness adapter is missing. Update this toolkit project.")
        command([sys.executable, str(helper), str(root)])
        outputs += ["validation_harness/EVIDENCE_LEDGER.md", "validation_harness/ledger.json", "validation_harness/index.html"]
    elif action_id.startswith("teeth."):
        if action_id == "teeth.install":
            expr = ("p <- " + _r_vector(TEETH_PACKAGES) + "; "
                    "missing <- p[!vapply(p,requireNamespace,logical(1),quietly=TRUE)]; "
                    "if(length(missing)) utils::install.packages(missing,lib=Sys.getenv('R_LIBS_USER'),repos='https://cloud.r-project.org'); "
                    + _package_check(TEETH_PACKAGES))
            command([r, "--vanilla", "-e", expr])
        else:
            command([r, "--vanilla", "-e", _package_check(TEETH_PACKAGES)])
            if action_id == "teeth.run":
                helper = _safe_path(root, "toolkit_launcher/native_teeth.py")
                if not helper.is_file():
                    raise JobError("The portable seeded-defect adapter is missing. Update this toolkit project.")
                command([sys.executable, str(helper), str(root)], extra={"R_PROFILE_USER": str(root / "toolkit_launcher/stub_profile.R"), "TEETH_WORK": str(private / "teeth")})
                outputs += ["validation_harness/teeth/results", "validation_harness/index.html"]
    return plan


def configuration_catalog() -> dict:
    def field(name, label, default="", kind="text", **extra):
        return dict(id=name, label=label, default=default, type=kind, **extra)

    tlf = [field("study_id", "Study identifier", "STUDY"), field("adam", "ADaM input folder", "inputs/adam"),
           field("output", "Output folder", "outputs/tlf"), field("meddra", "MedDRA version from the SAP"),
           field("whodrug", "WHODrug version from the SAP")]
    model = [field("model", "Installed model tag", "qwen2.5:7b-instruct-q8_0"),
             field("endpoint", "Local model endpoint", "http://127.0.0.1:11434"),
             field("seed", "Fixed model seed", 42, "number", min=0, max=2147483647, step=1),
             field("gguf_path", "Optional existing GGUF file")]
    monitor = [field("study_id", "Study identifier", "STUDY"), field("root", "Monitoring output folder", "outputs/monitoring"),
               field("sdtm", "SDTM input folder", "inputs/sdtm"), field("adam", "ADaM input folder", "inputs/adam"),
               field("safety", "Safety input folder", "inputs/safety"), field("ixrs", "IRT input folder", "inputs/ixrs"),
               field("smtp", "SMTP hostname (configuration only)"), field("support", "Support email"), field("backup", "Backup email"),
               field("alias", "Team email alias"), field("pm", "Project manager email"), field("manager", "Study lead email"),
               field("medical_monitor", "Medical monitor name"), field("medical_phone", "Medical monitor phone"),
               field("max_age", "Feed freshness threshold (hours)", 26, "number", min=1, max=8760),
               field("alt_multiple", "Protocol ALT/AST threshold (ULN multiple)", 3, "number", min=0.01, max=100),
               field("bilirubin_multiple", "Protocol bilirubin threshold (ULN multiple)", 2, "number", min=0.01, max=100),
               field("dose_variable", "Dose-level column", "COHORT"),
               field("enrollment_floor", "Enrollment fraction threshold", 0.8, "number", min=0, max=1),
               field("query_age", "Query age threshold (days)", 30, "number", min=1, max=3650)]
    return {
        "sas_monitor": {"fields": monitor, "description": "Export configured SAS monitoring files. Open configured_monitor.sas in your SAS editor and use the exported macro-library folder as its working directory. Review paths, mappings, thresholds and recipients before running it in your approved SAS environment. Exporting schedules no job and sends no email."},
        "localmind": {"fields": model[:-1], "description": "Export configuration for an already installed local model. Open configured_triage.sas in your SAS editor, with the exported macro-library folder as its working directory, or use local_settings.R in your R editor. Review the model and environment before running a driver. Exporting does not download or call a model."},
        "interpretation": {"fields": model, "description": "Export local drafting settings. The validator action remains model-free."},
        "sas_tlf": {"fields": tlf, "description": "Export a SAS setup file. Templates still require study-specific mappings and review."},
        "r_tlf": {"fields": tlf, "description": "Export an R setup file. Templates still require study-specific mappings and review."},
    }


def read_configuration(module_id: str, project_root: str | Path) -> dict:
    schemas = configuration_catalog()
    if not isinstance(module_id, str) or module_id not in schemas:
        raise JobError("Unknown configuration form.")
    root = _project(project_root)
    values = {f["id"]: f["default"] for f in schemas[module_id]["fields"]}
    path = _safe_path(root, f"toolkit_configuration/{module_id}.json")
    if path.is_file():
        try:
            saved = json.loads(path.read_text(encoding="utf-8"))
        except (ValueError, OSError) as exc:
            raise JobError("The saved configuration cannot be read.") from exc
        values.update({key: value for key, value in saved.get("values", {}).items() if key in values})
    return {"values": values}


def _atomic_text(path: Path, text: str):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".toolkit-tmp")
    if temporary.exists() or temporary.is_symlink():
        raise JobError("A configuration write is already in progress; try again after it finishes.")
    try:
        with temporary.open("x", encoding="utf-8") as stream:
            stream.write(text)
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)


def configure_project(module_id: str, project_root: str | Path, values: dict) -> dict:
    """Write only allowlisted config files; no process, service or email is started."""
    root = _project(project_root)
    schemas = configuration_catalog()
    if not isinstance(module_id, str) or module_id not in schemas or not isinstance(values, dict):
        raise JobError("Unknown configuration form.")
    fields = {f["id"]: f for f in schemas[module_id]["fields"]}
    if set(values) - set(fields):
        raise JobError("Unknown configuration field: " + ", ".join(sorted(set(values) - set(fields))))
    config = {name: values.get(name, field["default"]) for name, field in fields.items()}
    for name, value in config.items():
        field = fields[name]
        if field["type"] == "number":
            if type(value) not in (int, float) or not field["min"] <= value <= field["max"]:
                raise JobError(f"{field['label']} must be a number between {field['min']} and {field['max']}.")
            if name == "seed" and int(value) != value:
                raise JobError("The model seed must be an integer.")
        elif not isinstance(value, str) or len(value) > 1024 or re.search(r"[\x00-\x1f\x7f;&%\"'`]|/\*|\*/", value):
            raise JobError(f"{field['label']} contains unsupported characters. Use plain text without code or quotes.")
    if "study_id" in config and not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_. -]{0,63}", config["study_id"]):
        raise JobError("Study identifier must be 1–64 plain letters, numbers, spaces, dots, underscores or hyphens.")
    if module_id == "sas_tlf" and any(re.search(r"[(),]", str(value)) for value in config.values()):
        raise JobError("SAS setup values cannot contain commas or parentheses. Use a plain version label or folder path.")
    for name in ("support", "backup", "alias", "pm", "manager"):
        value = config.get(name, "")
        if value and not re.fullmatch(r"[A-Za-z0-9_.+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}", value):
            raise JobError(f"{fields[name]['label']} must be one email address, or blank.")
    if "dose_variable" in config and not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]{0,31}", config["dose_variable"]):
        raise JobError("Dose-level column must be a SAS variable name.")
    if "endpoint" in config:
        try:
            endpoint = urlsplit(config["endpoint"])
            port = endpoint.port
        except ValueError as exc:
            raise JobError("The model endpoint is invalid.") from exc
        if (endpoint.scheme != "http" or endpoint.hostname not in {"localhost", "127.0.0.1", "::1"}
                or endpoint.username or endpoint.password or endpoint.query or endpoint.fragment or endpoint.path not in {"", "/"}
                or (port is not None and not 1 <= port <= 65535)):
            raise JobError("Use a loopback model endpoint such as http://127.0.0.1:11434.")
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.:/\-]{0,199}", config["model"]):
            raise JobError("Use an installed model tag with letters, digits, dots, colons, slashes or hyphens.")
    files = {}
    header = "/* Toolkit configuration export. Review before execution; no service has been started. */\n"
    if module_id == "sas_monitor":
        mapping = {"STUDY": "study_id", "ROOT": "root", "SDTM": "sdtm", "ADAM": "adam", "SAFE": "safety", "IXRS": "ixrs",
                   "SMTP": "smtp", "SUPPORT": "support", "BACKUP": "backup", "ALIAS": "alias", "PM": "pm", "MGR": "manager",
                   "MM_NAME": "medical_monitor", "MM_PHONE": "medical_phone", "MAXAGE": "max_age", "ALTM": "alt_multiple",
                   "BILM": "bilirubin_multiple", "DOSEVAR": "dose_variable", "ENROLL_KRI": "enrollment_floor", "QRY_AGE": "query_age"}
        sas = header + "".join(f"%let CFG_{key} = {config[field]};\n" for key, field in mapping.items())
        sas += f"%let CFG_STATE = {config['root'].rstrip('/')}/state;\n%let CFG_FEEDS = adam.adlb adam.adeg adam.adae safe.sae ixrs.rand;\n"
        files["sas_r_automation/macro_library/tm_config.sas"] = sas
        # Original worked driver has hard-coded include locations. A separate
        # configured copy changes only those includes and visible study titles.
        driver = _safe_path(root, "sas_r_automation/macro_library/monitor_driver.sas").read_text(encoding="utf-8")
        driver = driver.replace('"/opt/trialmon/tm_macros.sas"', '"tm_macros.sas"').replace('"/opt/trialmon/tm_config.sas"', '"tm_config.sas"')
        driver = driver.replace("title=CP-101 ", "title=&CFG_STUDY ")
        files["sas_r_automation/macro_library/configured_monitor.sas"] = driver
    elif module_id in {"localmind", "interpretation"}:
        if module_id == "localmind":
            files["slm_wiki/macro_library/slm_config.sas"] = (header + f"%let CFG_MODEL = {config['model']};\n%let CFG_BASE = {config['endpoint'].rstrip('/')};\n"
                f"%let CFG_SEED = {int(config['seed'])};\n%let CFG_BACKUP = ;\n"
                "%let CFG_OWNERS = DM|PROGRAMMING|PK|MEDICAL CODING|SITE|BIOSTAT;\n%let CFG_SEVERITY = CRITICAL|MAJOR|MINOR;\n%let CFG_NOVELTY = NEW|KNOWN;\n")
            files["slm_wiki/macro_library/local_settings.R"] = ("# Source from this folder after reviewing the local model and its licence.\n"
                "source('slm_companion.R')\n" + "LOCALMIND_SETTINGS <- list(model=" + json.dumps(config["model"]) + ", base=" + json.dumps(config["endpoint"].rstrip('/'))
                + f", seed={int(config['seed'])}L)\n# No connection or model call is made by this settings file.\n")
            driver = _safe_path(root, "slm_wiki/macro_library/triage_driver.sas").read_text(encoding="utf-8")
            files["slm_wiki/macro_library/configured_triage.sas"] = driver.replace("%let ROOT = /sasdata/cp101/localmind;", "%let ROOT = .; /* Run from this exported macro-library folder. */")
        else:
            expression = {"tlf.slm.ollama_url": config["endpoint"].rstrip('/'), "tlf.slm.ollama_model": config["model"], "tlf.slm.seed": int(config["seed"])}
            if config["gguf_path"]:
                expression["tlf.slm.model_path"] = config["gguf_path"]
            files["tlf_interpret/local_settings.R"] = "# Configuration only; no model is loaded or called.\noptions(\n" + ",\n".join("  " + key + " = " + json.dumps(value) for key, value in expression.items()) + "\n)\n"
    elif module_id == "sas_tlf":
        files["sas_tlf_pseudocode/00_setup_local.sas"] = (header + '%include "00_setup_macros.sas";\n'
            + f"%setup(study={config['study_id']}, adam={config['adam']}, out={config['output']}, meddraver={config['meddra']}, whodrugver={config['whodrug']});\n")
    elif module_id == "r_tlf":
        files["r_tlf_pseudocode/00_setup_local.R"] = ("# Review mappings before using a template. This only defines its configuration.\n"
            "source('00_setup_helpers.R')\nTOOLKIT_SETTINGS <- list(" + ", ".join(key + "=" + json.dumps(config[name]) for key, name in
            (("study", "study_id"), ("adam", "adam"), ("out", "output"), ("meddra", "meddra"), ("whodrug", "whodrug"))) + ")\n")
    json_path = f"toolkit_configuration/{module_id}.json"
    files[json_path] = json.dumps({"module": module_id, "values": config, "status": "configuration only; not executed"}, indent=2) + "\n"
    # Validate every destination before making the first change.
    destinations = {relative: _safe_path(root, relative) for relative in files}
    for relative, content in files.items():
        _atomic_text(destinations[relative], content)
    return {"paths": list(files), "values": config, "message": "Configuration exported. No model, SAS process, schedule or email was started."}
