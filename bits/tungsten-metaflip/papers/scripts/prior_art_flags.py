#!/usr/bin/env python3
"""One prior-art flag per record, from the consolidated table of the 2026-09-29 prior-art audit
(work dir: paper-notes/08-rescore-and-prior-art.md, section C; produced by 08-consolidate.py).

usage: prior_art_flags.py RECORDS_TSV CONSOLIDATED_MD OUT_TSV

Flags (first that applies):  S1 superseded by a GF(2) scheme we built from published files and verified exactly,
S2 superseded by a published rank claim (not rebuilt), M1 matched by such a scheme, M2 matched by a rank claim,
Q  below_all contradicted only by a characteristic-0 (Q) catalogue claim, none = no prior art found.
Every flagged shape must be a record of records.tsv with the same rank and class; the counts are asserted.
"""
import csv
import re
import sys
from collections import Counter

records_tsv, consolidated_md, out_tsv = sys.argv[1:4]
records = {r['shape']: r for r in csv.DictReader(open(records_tsv), delimiter='\t')}
assert len(records) == 795
flags = {}
section = None
for line in open(consolidated_md):
    m = re.match(r'#### (S1|S2|M1|M2|Q)\b', line)
    if m:
        section = m.group(1)
        continue
    m = re.match(r'\| (\d+x\d+x\d+) \| (\d+) \| (below_all|gf2_valid_only) \| (\d+) \| (.*) \| ([^|]*) \|\s*$', line)
    if m and section:
        shape, rank, cls, prior, how, chain = m.groups()
        assert shape in records, shape
        r = records[shape]
        assert int(r['rank']) == int(rank) and r['class'] == cls, (shape, rank, cls, r['rank'], r['class'])
        assert shape not in flags, ('duplicate flag', shape)
        flags[shape] = (section, prior, how.strip())
counts = Counter(f[0] for f in flags.values())
expected = {'S1': 80, 'S2': 7, 'M1': 105, 'M2': 7, 'Q': 9}
assert dict(counts) == expected, (counts, expected)
with open(out_tsv, 'w', newline='') as fh:
    w = csv.writer(fh, delimiter='\t', lineterminator='\n')
    w.writerow(['shape', 'rank', 'class', 'flag', 'prior_rank', 'how'])
    for shape, r in records.items():
        f = flags.get(shape, ('none', '', ''))
        w.writerow([shape, r['rank'], r['class'], f[0], f[1], f[2]])
print(dict(counts), 'none', 795 - len(flags), 'of 795')
