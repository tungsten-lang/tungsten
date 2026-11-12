#!/usr/bin/env python3
"""Projection parents for the next round: scoreboard witnesses at or below the listed rank
(below_all / gf2_valid_only / tie) whose file was not already projected.

usage: next_parents.py BOARD.json OUT.json PROJ.jsonl [PROJ.jsonl ...] [--kinds below_all,gf2_valid_only]
"""
import json
from pathlib import Path
import sys

args = [a for a in sys.argv[1:] if not a.startswith('--kinds')]
kinds = ('below_all', 'gf2_valid_only')
for a in sys.argv[1:]:
    if a.startswith('--kinds'):
        kinds = tuple(a.split('=', 1)[1].split(','))
board, out, logs = args[0], args[1], args[2:]
done = set()
for log in logs:
    for line in open(log):
        done.add(json.loads(line)['parent'])
parents = []
for r in json.load(open(board)):
    if r['kind'] in kinds and r['path'] not in done:
        parents.append(dict(shape=r['shape'], canonical=r['shape'], gf2_rank=r['rank'], mfw=r['path'], kind=r['kind']))
parents.sort(key=lambda p: p['gf2_rank'])
json.dump(parents, open(out, 'w'), indent=1)
print(f"{len(parents)} new parents ({len(done)} already projected)")
