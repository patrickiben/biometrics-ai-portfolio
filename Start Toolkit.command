#!/bin/zsh
cd -- "${0:A:h}" || exit 1
for TOOLKIT_PYTHON in /Library/Frameworks/Python.framework/Versions/Current/bin/python3 /opt/homebrew/bin/python3 /usr/local/bin/python3 "$(command -v python3)"; do
  if [[ -x "$TOOLKIT_PYTHON" ]] && "$TOOLKIT_PYTHON" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)' >/dev/null 2>&1; then
    exec "$TOOLKIT_PYTHON" toolkit_launcher/desktop.py
  fi
done
/usr/bin/osascript -e 'display dialog "Install Python 3.10 or newer using the macOS installer at python.org, then double-click Start Toolkit again. No terminal commands are needed." with title "Trial biostatistics toolkit" buttons {"Open Python downloads"} default button 1'
/usr/bin/open 'https://www.python.org/downloads/macos/'
