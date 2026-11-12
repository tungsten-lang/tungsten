#!/usr/bin/env python3
"""Select projection children worth walking.

usage: pick_children.py PROJ.jsonl BOARD.json OUT.json [TOLERANCE=0.03]
Per canonical child shape keep the lowest-rank projection when it beats our current
witness (or none exists) and is within TOLERANCE above the best listed rank in any ring.
"""
import hashlib
import json
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import pub  # noqa: E402

proj, board_json, out = sys.argv[1:4]
tol = float(sys.argv[4]) if len(sys.argv) > 4 else 0.03
_, ANY, _ = pub.tables()
board = {tuple(map(int, r['shape'].split('x'))): r['rank'] for r in json.load(open(HERE / board_json))}
best = {}
for line in open(HERE / proj):
    r = json.loads(line)
    if not r.get('shape'):
        continue
    key = tuple(sorted(map(int, r['shape'].split('x'))))
    if key not in best or r['rank'] < best[key]['rank']:
        best[key] = r
seeds, stats = [], dict(children=len(best), no_gain=0, too_far=0)
for key, r in sorted(best.items()):
    pubrank = ANY[key]
    if key in board and r['rank'] >= board[key]:
        stats['no_gain'] += 1
        continue
    if r['rank'] > pubrank * (1 + tol):
        stats['too_far'] += 1
        continue
    raw = Path(r['mfw']).read_bytes()
    seeds.append(dict(shape=r['shape'], canonical='x'.join(map(str, key)), gf2_rank=r['rank'], mfw=r['mfw'],
                      mfw_sha256=hashlib.sha256(raw).hexdigest(), public=pubrank, board=board.get(key),
                      parent=r['parent'], mode=r['mode'], axis=r['axis'], coordinate=r['coordinate']))
json.dump(seeds, open(HERE / out, 'w'), indent=1)
below = sum(1 for s in seeds if s['gf2_rank'] < s['public'])
print(f"{stats['children']} child shapes; {stats['no_gain']} no gain over board; {stats['too_far']} beyond "
      f"{tol:.0%} of public; {len(seeds)} selected ({below} already below every listed rank)")
