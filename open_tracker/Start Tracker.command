#!/bin/zsh
# Double-click in Finder. Setup and all routine administration open in a browser.
cd -- "${0:A:h}" || exit 1
for TRACKER_PYTHON in /Library/Frameworks/Python.framework/Versions/Current/bin/python3 /opt/homebrew/bin/python3 /usr/local/bin/python3 "$(command -v python3)"; do
  if [[ -x "$TRACKER_PYTHON" ]] && "$TRACKER_PYTHON" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)' >/dev/null 2>&1; then
    exec "$TRACKER_PYTHON" desktop.py
  fi
done
/usr/bin/osascript -e 'display dialog "Install Python 3.10 or newer using the macOS installer at python.org, then double-click Start Tracker again. No terminal commands are needed." with title "Open Study Tracker" buttons {"Open Python downloads"} default button 1'
/usr/bin/open 'https://www.python.org/downloads/macos/'
