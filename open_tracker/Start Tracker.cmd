@echo off
setlocal
cd /d "%~dp0"
py -3 -c "import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)" >nul 2>&1
if not errorlevel 1 (
  py -3 "%~dp0desktop.py"
  exit /b
)
python -c "import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)" >nul 2>&1
if not errorlevel 1 (
  python "%~dp0desktop.py"
  exit /b
)
powershell -NoProfile -Command "Add-Type -AssemblyName PresentationFramework; [System.Windows.MessageBox]::Show('Install Python 3.10 or newer from python.org, then double-click Start Tracker again. No terminal commands are needed.','Open Study Tracker')" >nul
start "" "https://www.python.org/downloads/windows/"
