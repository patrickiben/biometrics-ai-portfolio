#!/usr/bin/env python3
"""Inline the shared light/dark adapter in legacy HTML; preserve single-file downloads.

Called by build_pages.py. Also run alone after rendering a legacy Quarto page.
Pages already using assets/ui.js and the shared top bar keep their native control.
"""
from pathlib import Path
import re
from html.parser import HTMLParser
import subprocess
import sys

MARKER = re.compile(r'\n?<!-- toolkit-theme:start -->.*?<!-- toolkit-theme:end -->\n?', re.S)


class DocumentStructure(HTMLParser):
    """Locate real markup, ignoring HTML-looking strings in embedded JavaScript."""
    def __init__(self, source):
        super().__init__(convert_charrefs=False)
        self.offsets = [0] + [match.end() for match in re.finditer("\\n", source)]
        self.head_end = None
        self.native_toggle = False
        self.has_html = False
        self.feed(source)
        self.close()

    def handle_starttag(self, tag, attrs):
        values = dict(attrs)
        if tag == 'html':
            self.has_html = True
        if tag == 'button' and 'theme-toggle' in values.get('class', '').split():
            self.native_toggle = True

    def handle_endtag(self, tag):
        if tag == 'head' and self.head_end is None:
            line, column = self.getpos()
            self.head_end = self.offsets[line - 1] + column


def theme_updates(root, generated=None):
    root = Path(root)
    generated = generated or {}
    read = lambda p: generated.get(p, (root / p).read_text(encoding='utf-8'))
    tokens = read('assets/theme/tokens.css')
    block = ('\n<!-- toolkit-theme:start -->\n<style id="toolkit-legacy-theme">\n' + tokens + '\n' +
             read('assets/legacy-theme.css') + '\n</style>\n<script>\n' + read('assets/legacy-theme.js') +
             '\n</script>\n<!-- toolkit-theme:end -->\n')
    names = subprocess.check_output(['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z'], cwd=root).decode().split('\0')
    updates = {}
    for name in sorted(set(names)):
        if not name.endswith('.html') or any(part.startswith(('.', '_')) for part in Path(name).parts):
            continue
        path = root / name
        if not path.is_file():
            continue
        original = read(name)
        if name == 'open_tracker/index.html':
            result = re.sub(r'(<style id="tracker-theme-tokens">).*?(</style>)', lambda m: m[1] + '\n' + tokens + '\n' + m[2], original, flags=re.S)
        else:
            page = MARKER.sub('', original)
            structure = DocumentStructure(page)
            if not structure.has_html or structure.head_end is None or structure.native_toggle:
                continue
            at = structure.head_end
            result = page[:at].rstrip() + block + page[at:]
        updates[name] = result
    return updates


if __name__ == '__main__':
    root = Path(__file__).resolve().parent
    managed = theme_updates(root)
    updates = {name: text for name, text in managed.items() if (root / name).read_text(encoding='utf-8') != text}
    if '--check' in sys.argv:
        for name in updates:
            print('Theme out of date: ' + name)
        sys.exit(bool(updates))
    for name, text in updates.items():
        (root / name).write_text(text, encoding='utf-8')
    print(f'Updated themes in {len(updates)} of {len(managed)} managed pages.')
