"""Probe the private web listener with its configured Host, without logging secrets."""
import json
import os
from pathlib import Path
import sys
from urllib.parse import urlsplit
from urllib.request import Request, build_opener, ProxyHandler


def main():
    try:
        file = Path('/data/config.json')
        url = (json.loads(file.read_text())['public_url'] if file.is_file() else
               os.environ.get('TRACKER_SETUP_PUBLIC_URL') or os.environ.get('RENDER_EXTERNAL_URL', ''))
        host = urlsplit(url).netloc
        if not host:
            return 1
        port = int(os.environ.get('PORT', '8080'))
        request = Request(f'http://127.0.0.1:{port}/api/session', headers={'Host': host})
        # Do not send this local probe through a host-supplied HTTP proxy.
        with build_opener(ProxyHandler({})).open(request, timeout=4) as response:
            result = json.load(response)
            return 0 if response.status == 200 and isinstance(result.get('csrf_token'), str) else 1
    except Exception:
        return 1


if __name__ == '__main__':
    sys.exit(main())
