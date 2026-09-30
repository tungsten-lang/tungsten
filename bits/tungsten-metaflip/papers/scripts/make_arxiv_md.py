#!/usr/bin/env python3
"""Write ARXIV.md (paste-ready submission metadata) from the two main.tex abstracts and the compiled PDFs.
usage: make_arxiv_md.py     (run in papers/, after `make`)"""
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def plain(p):
    s = (ROOT / p / 'main.tex').read_text()
    a = s[s.index('\\begin{abstract}') + len('\\begin{abstract}'): s.index('\\end{abstract}')].strip()
    a = a.replace('\\MM nmp', '<n,m,p>')
    a = re.sub(r'\\MM\{([^}]*)\}\{([^}]*)\}\{([^}]*)\}', r'<\1,\2,\3>', a)
    a = re.sub(r'\\MM(\d)(\d)(\d)', r'<\1,\2,\3>', a)
    a = a.replace('\\(3.1\\times10^{11}\\)', '3.1x10^11')
    a = a.replace('{,}', ',').replace('\\emph{', '').replace('\\F', 'F_2').replace('\\mathrm{GF}(2)', 'GF(2)').replace('$', '').replace('\\%', '%')
    a = a.replace('\\times', 'x').replace('\\mathbb Z_2', 'Z_2')
    a = re.sub(r'\}', '', a)
    return ' '.join(a.split())


def pages(p):
    return int(re.search(r'Pages:\s+(\d+)', subprocess.check_output(['pdfinfo', str(ROOT / p / 'main.pdf')], text=True)).group(1))


def count(p, env):
    return sum(f.read_text().count('\\begin{%s}' % env) for f in (ROOT / p).rglob('*.tex'))


TITLE = {
    'methods': 'Directed Flip-Graph Walks, Projection Cascades and Composition Closure for GF(2) Matrix-Multiplication Schemes: Search Methods with Provenance-Preserving Verification',
    'results': 'Upper Bounds on the GF(2) Rank of Matrix Multiplication Below Four Public Tables: 795 Formats up to 32x32x32 and a Prior-Art Check',
}
out = ['# arXiv submission metadata (drafts of 2026-09-29)', '',
       'Paste-ready fields for the arXiv submission form (`python3 scripts/make_arxiv_md.py` regenerates this file from the abstracts in `main.tex`).',
       'arXiv limits the abstract field to 1,920 characters. Everything marked TODO needs the author.', '']
for p, other in (('results', 'methods'), ('methods', 'results')):
    abstract = plain(p)
    assert len(abstract) <= 1920, (p, len(abstract))
    appendices = 'plus appendices' if p == 'results' else 'no appendices'
    out += [f'## {p}/', '',
            f'- **Title:** {TITLE[p]}',
            '- **Authors:** Erik Peterson (TODO: affiliation, contact e-mail, ORCID)',
            f'- **Abstract** ({len(abstract)} characters; limit 1,920):', '', '  ' + abstract, '',
            f'- **Comments:** {pages(p)} pages, {count(p, "table")} tables, {count(p, "figure")} figures ({appendices}). Companion paper: "{TITLE[other]}". Draft of 2026-09-29.',
            '- **Primary category:** cs.SC (Symbolic Computation); **cross-lists:** cs.CC (Computational Complexity), cs.DS (Data Structures and Algorithms)',
            '- **MSC class:** 68Q25; 15A69; 68W30    **ACM class:** F.2.1; I.1.2',
            "- **License:** TODO (author's choice; CC BY 4.0 is the usual one)",
            f'- **Source bundle:** `make arxiv` writes `dist/{p}-arxiv.tar.gz` (main.tex, sections, tables, data, `main.bbl`, `refs.bib`); it is rebuilt standalone before it is written.',
            '']
(ROOT / 'ARXIV.md').write_text('\n'.join(out))
print('ARXIV.md written')
