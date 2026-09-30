#!/usr/bin/env python3
"""Write PAPER/refs.bib from the verified master bibliography (refs-all.bib) and extra.bib,
keeping only the entries that PAPER/main.tex and PAPER/sections/*.tex cite.

usage: mkbib.py methods|results
"""
import re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
paper = ROOT / sys.argv[1]
text = ''.join(p.read_text() for p in sorted(paper.rglob('*.tex')))
cited = set()
for m in re.finditer(r'\\cite[a-z]*\*?(?:\[[^\]]*\])*\{([^}]*)\}', text):
    cited.update(k.strip() for k in m.group(1).split(','))
entries = {}
for src in ('refs-all.bib', 'extra.bib'):
    raw = (ROOT / src).read_text()
    for block in re.split(r'\n(?=@)', raw):
        m = re.match(r'@\w+\{([^,]+),', block)
        if m:
            entries[m.group(1)] = block.strip()
# refs-all.bib keeps verification memos in `note` fields ("the journal page was not opened", ...).  They are
# for us, not for readers: the printed bibliography keeps only the notes listed here, in their public form.
PRINT_NOTE = {
    'sedoglavic2017seven': 'Also HAL hal-01572046',
    'sedoglavic2026catalogue': 'Accessed 2026-09-29',
    'sedoglavic2026digest': 'Commit 9f26324 (2026-09-28)',
    'perminov2026fmmrepo': 'Commit 613599b (2026-09-28)',
    'witteveen2026schemes': 'Dataset, CC BY 4.0; version 1.1 (2026-09-27), doi:10.5281/zenodo.23001328',
    'lacelle2026catalog': 'arXiv v3 of 2026-08-14; code and catalogue at https://github.com/solven-eu/matmulcatalog',
    'waksman1970winograd': 'Commutative algorithm',
    'winograd1968inner': 'Commutative algorithm',
    'peterson2026results': 'Companion paper, in preparation',
    'peterson2026methods': 'Companion paper, in preparation',
}


def print_ready(key, block):
    block = re.sub(r'(?m)^%.*\n?', '', block)                      # section-header comments of the master file
    block = re.sub(r'(?m)^\s*note\s*=\s*\{.*\},?\s*\n?', '', block).rstrip()
    assert block.endswith('}')
    body = re.sub(r',\s*$', '', block[:-1].rstrip())      # drop a trailing comma before the closing brace
    if key in PRINT_NOTE:
        body += ',\n  note = {' + PRINT_NOTE[key] + '}'
    return body + '\n}'


for k in list(entries):
    entries[k] = print_ready(k, entries[k])
missing = sorted(k for k in cited if k not in entries)
(paper / 'refs.bib').write_text('\n\n'.join(entries[k] for k in sorted(cited) if k in entries) + '\n')
print(f'{sys.argv[1]}: {len(cited) - len(missing)} entries written', ('MISSING: ' + ', '.join(missing)) if missing else '')
