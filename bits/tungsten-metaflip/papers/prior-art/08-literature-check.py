#!/usr/bin/env python3
"""Part B of the 2026-09-29 prior-art audit: compare published rank tables with the 795 records.

Inputs: the texts fetched by 08-fetch-literature.py (W/upstream-latest/arxiv/<id>/paper.txt, pdftotext
-layout of the latest arXiv PDF), records.tsv (our ranks, the comparators we used) and
W/paper-data/rescore_latest.tsv (the comparators at the latest public revisions, from 08-rescore-latest.py).

  * Perminov's three rank papers (2511.20317, 2603.02398, 2606.02480): every table row is parsed from
    the text by the regular expressions below; the row count of each table is checked against the count
    the paper states, so no row is transcribed by hand.
  * Medley et al. (2609.17533): the rank-245 7x7x7 scheme printed in Appendix A is decoded from the text
    and checked against the 7x7x7 matrix multiplication tensor over F2 (independent re-implementation of
    the paper's own check).
  * Every other paper: rows transcribed from the text (LITERATURE below); every row carries a quote
    that must occur on the cited line of paper.txt (whitespace-normalised), else the script aborts.

For every row the script reports, against our 795 shapes (sorted dims):
  (a) GF(2)-valid result (F2/Z2, ZT, Z, or any ring) with rank <= ours;
  (b) GF(2)-valid result below the GF(2)-valid comparator we used (best_listed_gf2_valid; when that is
      empty, below best_listed_any_ring), even if above ours;
  (c) result valid only in characteristic 0 / not in characteristic 2 (Q, C) with rank < ours.
Run: python3 08-literature-check.py [--json OUT]
"""
import base64
import csv
import json
import re
import sys
import zlib
from pathlib import Path

W = Path('/Users/erik/.tungsten/metaflip/experiments/record-hunt-20260926/work')
ARXIV = W / 'upstream-latest/arxiv'
RECORDS = W / 'release-0929/gf2-campaign-records/records.tsv'
LATEST = W / 'paper-data/rescore_latest.tsv'
GF2_VALID = {'Z2', 'F2', 'ZT', 'Z', 'any'}  # rings whose schemes reduce to (or are) GF(2) schemes


def norm(s):
    return ' '.join(s.split())


class Paper:
    def __init__(self, aid):
        self.id = aid
        self.lines = (ARXIV / aid / 'paper.txt').read_text().split('\n')
        pages, self.page = 1, []
        for line in self.lines:
            pages += line.count('\f')
            self.page.append(pages)

    def check(self, line, text):
        """The quote must occur on 1-based line `line` (whitespace-normalised)."""
        if norm(text) not in norm(self.lines[line - 1]):
            raise SystemExit(f'QUOTE NOT FOUND {self.id}:{line}: {text!r}\n  line is: {self.lines[line - 1]!r}')
        return dict(line=line, page=self.page[line - 1], text=norm(text))

    def find(self, needle, start=0):
        for i in range(start, len(self.lines)):
            if needle in self.lines[i]:
                return i + 1
        raise SystemExit(f'{self.id}: {needle!r} not found')


def ours():
    rows = {}
    latest = {r['shape']: r for r in csv.DictReader(LATEST.open(), delimiter='\t')}
    for r in csv.DictReader(RECORDS.open(), delimiter='\t'):
        key = tuple(map(int, r['shape'].split('x')))
        rows[key] = dict(shape=r['shape'], rank=int(r['rank']), cls=r['class'],
                         any=int(r['best_listed_any_ring']) if r['best_listed_any_ring'] else None,
                         gf2=int(r['best_listed_gf2_valid']) if r['best_listed_gf2_valid'] else None,
                         any_latest=int(latest[r['shape']]['new_best_any']) if latest[r['shape']]['new_best_any'] else None,
                         gf2_latest=int(latest[r['shape']]['new_best_gf2']) if latest[r['shape']]['new_best_gf2'] else None)
    return rows


# ---------------------------------------------------------------- Perminov: parse every table row
X = r'(\d+)\s*×\s*(\d+)\s*×\s*(\d+)'   # "4 × 4 × 10" or "4×4×10"
P = r'\((\d+),\s*(\d+),\s*(\d+)\)'       # "(4, 4, 10)"


def parse_table(paper, caption, end_marker, pattern, fields, expected):
    """Rows matched by `pattern` between the caption line and the first line containing end_marker."""
    start = paper.find(caption)
    stop = paper.find(end_marker, start) if end_marker else len(paper.lines)
    rows = []
    for ln in range(start + 1, stop):
        for m in re.finditer(pattern, paper.lines[ln - 1]):
            rec = dict(zip(fields, m.groups()))
            rows.append(dict(rec, line=ln, page=paper.page[ln - 1], text=norm(m.group(0))))
    if len(rows) != expected:
        raise SystemExit(f'{paper.id} {caption!r}: parsed {len(rows)} rows, expected {expected}')
    return dict(caption=paper.check(start, caption), rows=rows)


def perminov():
    out = {}
    # arXiv:2511.20317 v2 (29 Nov 2025) - ternary meta flip graphs
    p = Paper('2511.20317')
    t = {}
    t['Table 1'] = parse_table(p, 'Table 1: Rediscovered schemes known only in Q field', '4.4   Binary Field Improvements',
                               P + r'\s+(\d+)', ('n', 'm', 'p', 'rank'), 8)
    for r in t['Table 1']['rows']:
        r['ring'] = 'ZT'  # "independent discovery of 32 ... schemes using ternary coefficients (ZT) ... 8 ... only known with rational"
    t['Table 2'] = parse_table(p, 'Table 2: Other rediscovered schemes with ternary coefficients', 'Table 3: New discoveries',
                               P + r'\s+(\d+)\s+(Z/Q|Z|Q)', ('n', 'm', 'p', 'rank', 'known_ring'), 24)
    for r in t['Table 2']['rows']:
        r['ring'] = 'ZT'
    t['Table 3'] = parse_table(p, 'Table 3: New discoveries in binary field (Z2 )', 'required. The additive complexity',
                               P + r'\s+(\?|\d+)\s+(\d+)', ('n', 'm', 'p', 'known', 'rank'), 30)
    for r in t['Table 3']['rows']:
        r['ring'] = 'Z2'
    t['Table 4'] = parse_table(p, 'Table 4: Reduce naive addition complexity', '4.6   Ternary Schemes',
                               P + r'\s+(\d+)\s+(\d+)\s+(\d+)', ('n', 'm', 'p', 'rank', 'adds_known', 'adds_new'), 40)
    for r in t['Table 4']['rows']:
        r['ring'] = 'ZT'
    t5 = parse_table(p, 'Table 5: Near optimal schemes discovered in ZT', '5     Discussion',
                     P + r'\s+(Q|Z)\s+(\d+)\s+(\d+)', ('n', 'm', 'p', 'best_ring', 'best_rank', 'zt_rank'), 72)
    t['Table 5 (best known, as listed)'] = dict(caption=t5['caption'], rows=[dict(r, rank=r['best_rank'], ring=r['best_ring']) for r in t5['rows']])
    t['Table 5 (ZT found)'] = dict(caption=t5['caption'], rows=[dict(r, rank=r['zt_rank'], ring='ZT') for r in t5['rows']])
    out['2511.20317'] = t
    # arXiv:2603.02398 v1 (2 Mar 2026) - open-source flip graph framework
    p = Paper('2603.02398')
    t = {}
    t['Table 1'] = parse_table(p, 'Table 1: Improved ranks for matrix multiplication formats', '7.1     Flip Potential',
                               X + r'\s+(\d+)\s+(ZT|Z|Q)\s+(\d+)\s+(ZT|Z|Q)\s+(\d\.\d+)',
                               ('n', 'm', 'p', 'prev_rank', 'prev_ring', 'rank', 'ring', 'omega'), 79)
    t['Table 2'] = parse_table(p, 'Table 2: Rediscovered schemes with ternary coefficients (ZT )', 'Table 3: Rediscovered',
                               X + r'\s+(\d+)\s+(Z/Q|Z|Q)', ('n', 'm', 'p', 'rank', 'known_ring'), 93)
    for r in t['Table 2']['rows']:
        r['ring'] = 'ZT'
    t['Table 3'] = parse_table(p, 'Table 3: Rediscovered schemes with integer coefficients (Z)', '7.2   Varying Search',
                               X + r'\s+(\d+)(?=\s|$)', ('n', 'm', 'p', 'rank'), 68)
    for r in t['Table 3']['rows']:
        r['ring'] = 'Z'
    t['Table 4'] = parse_table(p, 'Table 4: Matrix multiplication formats with exponent below', None,
                               X + r'\s+(\d+)\s+(ZT|Z|Q)\s+(\d\.\d+)', ('n', 'm', 'p', 'rank', 'ring', 'omega'), 29)
    out['2603.02398'] = t
    # arXiv:2606.02480 v2 (5 Jun 2026) - meta flip graph + serendipitous product
    p = Paper('2606.02480')
    t = {}
    t1 = parse_table(p, 'Table 1: Examples of serendipitous product constructions', '3.4   Searching for Alternative',
                     r'\((\d+),\s*(\d+),\s*(\d+)\s*:\s*(\d+)\)\s+' + X + r'\s+(\d+)\s+(\d+)',
                     ('n2', 'm2', 'p2', 'r2', 'n', 'm', 'p', 'rank', 'naive'), 13)
    for r in t1['rows']:
        r['ring'] = 'unstated'  # the table gives no ring; Table 2/3 give the ring of the resulting format
    t['Table 1'] = t1
    t['Table 2'] = parse_table(p, 'Table 2: Improved ranks for matrix multiplication formats', '• Z: 18 schemes',
                               X + r'\s+(\d+)\s+(\d+)\s+(ZT|Z|Q)\s+(\d\.\d+)', ('n', 'm', 'p', 'prev_rank', 'rank', 'ring', 'omega'), 207)
    t['Table 3'] = parse_table(p, 'Table 3: Rediscovered schemes with ternary coefficients (ZT )', 'Table 4: New discovered',
                               X + r'\s+(\d+)\s+(Z/Q|Z|Q)', ('n', 'm', 'p', 'rank', 'known_ring'), 84)
    for r in t['Table 3']['rows']:
        r['ring'] = 'ZT'
    t['Table 4'] = parse_table(p, 'Table 4: New discovered schemes with asymptotic exponent better', 'The total number of formats',
                               X + r'\s+(\d+)\s+(ZT|Z|Q)\s+(\d\.\d+)\s+(\d\.\d+)', ('n', 'm', 'p', 'rank', 'ring', 'omega_prev', 'omega'), 23)
    out['2606.02480'] = t
    return out


# ---------------------------------------------------------------- Medley et al.: decode and verify the rank-245 scheme
def medley():
    p = Paper('2609.17533')
    begin = p.find('BEGIN-RANK245-7X7X7-ZLIB-BASE32')
    end = p.find('END-RANK245-7X7X7-ZLIB-BASE32', begin)
    payload = ''.join(''.join(p.lines[i].split()) for i in range(begin, end - 1))
    payload += '=' * (-len(payload) % 8)
    data = zlib.decompress(base64.b32decode(payload))
    n, rank = 7, len(data) // 21
    assert len(data) == rank * 21
    # accumulate sum_r A_r (x) B_r (x) C_r over F2 as a set of (a, b, c) index triples with odd count
    parity = set()
    for off in range(0, len(data), 21):
        a, b, c = (int.from_bytes(data[off + k:off + k + 7], 'little') for k in (0, 7, 14))
        supp = [[i for i in range(n * n) if x >> i & 1] for x in (a, b, c)]
        assert all(supp), 'zero factor'
        parity ^= {(i, j, k) for i in supp[0] for j in supp[1] for k in supp[2]}
    expected = {(i * n + j, j * n + k, i * n + k) for i in range(n) for j in range(n) for k in range(n)}
    return dict(rank=rank, verified_over_F2=parity == expected,
                appendix=p.check(begin, 'BEGIN-RANK245-7X7X7-ZLIB-BASE32'),
                abstract=p.check(24, 'a way to multiply 7 × 7 matrices over F2 using 245 multiplications, a'),
                conclusion=p.check(994, 'found a decomposition of the 7 × 7 × 7 matrix multiplication tensor over F2 of'))


# ---------------------------------------------------------------- transcribed rows of the other papers
import importlib.util  # noqa: E402

SOURCES = {'FastMatrixF2': W / 'upstream-latest/FastMatrixF2/README.md'}
POS = ('characteristic 2', 'characteristic two', 'z2', 'f2', 'mod 2', 'zt', 'any', 'arbitrary', 'integer',
       'coefficients in z', 'lifted to z', 'default lifting', 'z[1/3', 'odd', 'without restriction',
       'without fractional', 'not restricted', 'ternary', '{-1,0,1}', 'ground field', 'strassen',
       'field with 2 elements', 'z (line', 'z (figures', 'searched over z2', 'lifted from z2')
NEG = ('not valid in characteristic two', 'except characteristic 2', 'inverse of 2', 'z[1/2]', 'fractional',
       'half-integer', 'complex', 'commutative scheme', 'f3,q', 'nnz', 'not stated', 'denominators 2',
       'divides by 2', '0.5*')


def gf2_valid(row):
    """GF(2)-valid only when the paper's own statement (as transcribed) says so: characteristic 2 / Z2 / F2,
    ternary or integer coefficients, any ring, or odd denominators; 'not stated' counts as not valid."""
    f = (row['field'] or '').lower()
    if row.get('agent_gf2_valid') is not True or not row.get('general', True) or row.get('structure') not in (None, 'gg'):
        return False
    if 'repo: z' in f and '0.5' not in f:
        return True
    if any(n in f for n in NEG):
        return False
    return any(t in f for t in POS)


def char0_only(row):
    f = (row['field'] or '').lower()
    return any(t in f for t in ('complex', 'z[1/2]', 'fractional', 'except characteristic 2', 'inverse of 2',
                                'denominators 2', 'divides by 2', '0.5*', 'half-integer entries (paper); repo: 0.5'))


class Source(Paper):
    def __init__(self, pid):
        self.id = pid
        path = SOURCES.get(pid, ARXIV / pid / 'paper.txt')
        self.lines = path.read_text().split('\n')
        pages, self.page = 1, []
        for line in self.lines:
            pages += line.count('\f')
            self.page.append(pages)


def transcribed():
    """Rows of 08-literature-data.py with each quote checked on its cited line; adds gf2 / char0 flags."""
    spec = importlib.util.spec_from_file_location('litdata', Path(__file__).resolve().parent / '08-literature-data.py')
    data = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(data)
    cache, out = {}, []
    for r in data.ROWS:
        src = cache.setdefault(r['paper'], Source(r['paper']))
        ref = src.check(r['line'], r['text'])
        out.append(dict(r, n=r['format'][0], m=r['format'][1], p=r['format'][2], page=ref['page'],
                        ring=('any' if gf2_valid(r) else 'Q' if char0_only(r) else 'unstated')))
    return data.PAPERS, out


def transcribed_gf2():
    _, rows = transcribed()
    return [dict(format=tuple(r['format']), rank=r['rank'],
                 label=f"arXiv:{r['paper']} {r['table']} line {r['line']} ({r['field'][:40]})") for r in rows
            if r['ring'] == 'any']


# ---------------------------------------------------------------- comparison
def compare(rows, mine, source):
    hits = dict(a=[], b=[], c=[])
    for r in rows:
        key = tuple(sorted((int(r['n']), int(r['m']), int(r['p']))))
        if key not in mine:
            continue
        o = mine[key]
        rank = int(r['rank'])
        valid = r['ring'] in GF2_VALID
        row = dict(source=source, shape=o['shape'], paper_rank=rank, ring=r['ring'], ours=o['rank'], cls=o['cls'],
                   best_any=o['any'], best_gf2=o['gf2'], line=r.get('line'), page=r.get('page'), text=r.get('text'))
        if valid and rank <= o['rank']:
            hits['a'].append(row)
        comparator = o['gf2'] if o['gf2'] is not None else o['any']
        if valid and comparator is not None and rank < comparator:
            hits['b'].append(row)
        if not valid and r['ring'] in ('Q', 'C', 'Q/C', 'char!=2') and rank < o['rank']:
            hits['c'].append(row)
    return hits


def main():
    mine = ours()
    report = dict(perminov={}, medley=medley(), transcribed={})
    papers, rows = transcribed()
    for pid in papers:
        prow = [r for r in rows if r['paper'] == pid]
        hits = compare(prow, mine, pid)
        report['transcribed'][pid] = dict(title=papers[pid]['title'], version=papers[pid]['version'],
                                          version_date=papers[pid]['version_date'], rows=len(prow),
                                          quotes_checked=len(prow), gf2_valid_rows=sum(1 for r in prow if r['ring'] == 'any'),
                                          max_side=max((max(r['format']) for r in prow), default=None),
                                          overlap_shapes=sorted({'x'.join(map(str, sorted(r['format']))) for r in prow}
                                                                & {o['shape'] for o in mine.values()}),
                                          hits=hits)
    tables = perminov()
    for aid, tabs in tables.items():
        for label, tab in tabs.items():
            hits = compare(tab['rows'], mine, f'{aid} {label}')
            report['perminov'][f'{aid} {label}'] = dict(caption=tab['caption'], rows=len(tab['rows']),
                                                        rings=sorted({r['ring'] for r in tab['rows']}),
                                                        max_side=max(max(int(r['n']), int(r['m']), int(r['p'])) for r in tab['rows']),
                                                        overlap_shapes=sorted({'x'.join(map(str, sorted((int(r['n']), int(r['m']), int(r['p'])))))
                                                                               for r in tab['rows']} & {o['shape'] for o in mine.values()}),
                                                        hits=hits)
    out = json.dumps(report, indent=1, ensure_ascii=False)
    if sys.argv[1:2] == ['--json']:
        Path(sys.argv[2]).write_text(out + '\n')
    print(out)


if __name__ == '__main__':
    main()
