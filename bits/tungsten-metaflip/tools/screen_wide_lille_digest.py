#!/usr/bin/env python3
"""Compare verified wide GF(2) certificates with a supplied Lille rank digest.

The digest is external and time-varying. This tool never infers a public
record from the pinned composition catalog or from a missing digest row.
"""
import argparse
import json
from pathlib import Path

from check_wide_rectangular_closure import CANDIDATES


def compare(entries, candidates=CANDIDATES):
    public = {}
    for entry in entries:
        shape = tuple(sorted(entry['format']))
        rank = entry['rank']
        if len(shape) != 3 or any(not isinstance(n, int) or n < 1 for n in shape):
            raise ValueError(f'invalid Lille format: {entry!r}')
        if not isinstance(rank, int) or rank < 1:
            raise ValueError(f'invalid Lille rank: {entry!r}')
        if shape in public and public[shape] != rank:
            raise ValueError(f'conflicting Lille ranks for {shape}')
        public[shape] = rank
    local = {}
    for shape, _, rank, _, _ in candidates:
        key = tuple(sorted(shape))
        local[key] = min(local.get(key, rank), rank)
    missing = sorted(set(local) - set(public))
    if missing:
        raise ValueError(f'Lille digest missing {len(missing)} archive shapes: {missing[:8]}')
    return sorted(({'shape': list(shape), 'local_gf2_rank': rank,
                    'lille_rank': public[shape], 'gap': rank - public[shape]}
                   for shape, rank in local.items()),
                  key=lambda row: (row['gap'], row['shape']))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('digest', type=Path, help='fmm_sota.json from sedoglavic/fmm_digest')
    parser.add_argument('--mode', choices=('all', 'above', 'below', 'tie'), default='all')
    parser.add_argument('--limit', type=int, default=0, help='0 prints every matching row')
    args = parser.parse_args()
    if args.limit < 0:
        parser.error('--limit must be nonnegative')
    digest = json.loads(args.digest.read_text())
    rows = compare(digest['entries'])
    if args.mode == 'above':
        rows = [row for row in rows if row['gap'] > 0]
    elif args.mode == 'below':
        rows = [row for row in rows if row['gap'] < 0]
    elif args.mode == 'tie':
        rows = [row for row in rows if row['gap'] == 0]
    if args.mode == 'above':
        rows.sort(key=lambda row: (row['gap'], row['shape']))
    elif args.mode == 'below':
        rows.sort(key=lambda row: (-row['gap'], row['shape']))
    if args.limit:
        rows = rows[:args.limit]
    print(json.dumps({'source': digest.get('source'), 'created_at': digest.get('createdAt'),
                      'mode': args.mode, 'rows': rows}, indent=2))


if __name__ == '__main__':
    main()
