@echo off
setlocal
cd /d "%~dp0"
py -3 -c "import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)" >nul 2>&1
if not errorlevel 1 (
  py -3 "%~dp0toolkit_launcher\desktop.py"
  exit /b
)
python -c "import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)" >nul 2>&1
if not errorlevel 1 (
  python "%~dp0toolkit_launcher\desktop.py"
  exit /b
)
powershell -NoProfile -Command "Add-Type -AssemblyName PresentationFramework; [System.Windows.MessageBox]::Show('Install Python 3.10 or newer from python.org, then reopen Start Toolkit.','Trial biostatistics toolkit')" >nul
start "" "https://www.python.org/downloads/windows/"
