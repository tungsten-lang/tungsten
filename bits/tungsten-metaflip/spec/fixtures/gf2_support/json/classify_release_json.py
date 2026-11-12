#!/usr/bin/env python3
"""Which json.dumps settings reproduce each JSON / JSONL file of a release tree byte for byte.

usage: classify_release_json.py RELEASE_DIR > release_formats.tsv
Columns: relative path, kind (json | jsonl), format (json: indent1_nl | indent1 | indent2_nl | default | none;
jsonl: number of lines that json.dumps(json.loads(line)) reproduces), total lines (jsonl) or 1.
The Tungsten test (spec/gf2_support/json_cases.w) recomputes the same table with Jsonx and compares.
"""
import json
import sys
from pathlib import Path

FORMATS = (('indent1_nl', dict(indent=1), '\n'), ('indent1', dict(indent=1), ''), ('indent2_nl', dict(indent=2), '\n'),
           ('default', dict(), ''))

root = Path(sys.argv[1])
for path in sorted(root.rglob('*.json*')):
    if path.suffix not in ('.json', '.jsonl') or not path.is_file():
        continue
    rel = path.relative_to(root)
    if path.suffix == '.json':
        raw = path.read_bytes()
        try:
            value = json.loads(raw)
        except ValueError:
            print(f'{rel}\tjson\tunparseable\t1')
            continue
        label = 'none'
        for name, kw, tail in FORMATS:
            if (json.dumps(value, **kw) + tail).encode() == raw:
                label = name
                break
        print(f'{rel}\tjson\t{label}\t1')
    else:
        lines = [l for l in path.read_text().split('\n') if l.strip()]
        same = sum(json.dumps(json.loads(l)) == l for l in lines)
        print(f'{rel}\tjsonl\t{same}\t{len(lines)}')
