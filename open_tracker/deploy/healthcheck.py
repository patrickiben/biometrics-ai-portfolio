"""Probe the private web listener with its configured Host, without logging secrets."""
import json
from pathlib import Path
import sys
from urllib.parse import urlsplit
from urllib.request import Request, build_opener, ProxyHandler


def main():
    try:
        config = json.loads(Path('/data/config.json').read_text())
        host = urlsplit(config['public_url']).netloc
        if not host:
            return 1
        request = Request('http://127.0.0.1:8080/api/session', headers={'Host': host})
        # Do not send this local probe through a host-supplied HTTP proxy.
        with build_opener(ProxyHandler({})).open(request, timeout=4) as response:
            result = json.load(response)
            return 0 if response.status == 200 and isinstance(result.get('csrf_token'), str) else 1
    except Exception:
        return 1


if __name__ == '__main__':
    sys.exit(main())
