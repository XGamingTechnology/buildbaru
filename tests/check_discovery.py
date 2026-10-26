"""Static documentation checks only; run from any working directory with Python 3."""
import re
from pathlib import Path
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[1]
DOCS = sorted((ROOT / 'docs' / 'discovery').glob('*.md')) + [
    ROOT / 'docs/adr/0001-discovery-method.md',
    ROOT / 'docs/DECISIONS.md',
    ROOT / 'docs/PRD_TRACEABILITY.md',
]


def validate_document(path):
    text = path.read_text(encoding='utf-8')
    assert text.startswith('# '), f'{path}: missing title'
    assert text.endswith('\n'), f'{path}: missing final newline'
    assert not any(line.rstrip() != line for line in text.splitlines()), (
        f'{path}: trailing whitespace'
    )
    assert text.count('```') % 2 == 0, f'{path}: unbalanced code fences'
    for link in re.findall(r'\[[^\]]+\]\(([^\s)]+)\)', text):
        parsed = urlsplit(link)
        if parsed.scheme or parsed.netloc or not parsed.path:
            continue
        target = (path.parent / unquote(parsed.path)).resolve()
        assert target.is_relative_to(ROOT), f'{path}: link escapes repository: {link}'
        assert target.is_file(), f'{path}: missing link target: {link}'


for document in DOCS:
    validate_document(document)

matrix = (ROOT / 'docs/discovery/TECHNICAL_SPIKE.md').read_text()
weights = [int(n) for n in re.findall(r'^\|[^|]+\|\s*(\d+)\s*\|', matrix, re.M)]
assert len(weights) == 10 and sum(weights) == 100, weights
print(f'PASS: {len(DOCS)} documents: titles, whitespace, fences, relative file links')
print('PASS: 10 evaluation criteria; weights total 100 (no runtime assertions)')
