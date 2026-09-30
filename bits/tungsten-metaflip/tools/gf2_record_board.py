#!/usr/bin/env python3
"""Scoreboard: best exactly verified local GF(2) witness per shape vs public ranks.

Every counted witness is expanded against the full matrix-multiplication
tensor (results are cached by file SHA-256). Public comparisons:

  --lille          Sedoglavic fmm_digest `fmm_sota.json` (rank only, any ring)
  --matmulcatalog  solven-eu/matmulcatalog `docs/catalog.json`; commutative
                   entries are excluded; `fields` separates F2-valid schemes
  --fmm-repo       a clone of a FastMatrixMultiplication-format repository
                   (Perminov); the ring is the file-name suffix (_ZT/_Z/_Q)
  --extra-repo     further FMM-format scheme directories (e.g. fmm-schemes)

Classes: `below_all` beats every listed rank in any ring; `gf2_valid_only`
beats every listed GF(2)-valid scheme (ZT/Z or catalogue F2) but a listed
Q/C-only rank is lower. A listed rank is a comparison, never a certificate;
neither class is a novelty or optimality claim.
"""
import argparse
import base64
import concurrent.futures
import gzip
import hashlib
import itertools
import json
import os
from pathlib import Path
import re
import subprocess
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import screen_top_two_projection_children as top  # noqa: E402

RING = re.compile(r'(?:^|/)(\d+)x(\d+)x(\d+)_m(\d+)(?:_[^/]*)?_(ZT|Z|Q)\.json$')


def load(path):
    raw = path.read_bytes()
    if path.name.endswith('.gz.b64'):
        raw = gzip.decompress(base64.b64decode(raw.replace(b'\n', b''), validate=True))
    return raw


def shape_hint(path):
    for part in (path.name, path.parent.name):
        match = re.search(r'(\d+)x(\d+)(?:x(\d+))?', part)
        if match:
            dims = [int(g) for g in match.groups() if g]
            return tuple(dims if len(dims) == 3 else dims + [dims[0]])
    return None


def decode(path, raw):
    """(shape, terms) for MFW1 or decimal `R a b c` / rank-prefixed text."""
    if raw.startswith(b'MFW1'):
        shape, terms = top.read_blob(raw)
        top.exact(shape, terms)
        return tuple(shape), terms
    hint = shape_hint(path)
    if hint is None:
        raise ValueError('no shape')
    lines = [s.strip() for s in raw.decode().splitlines() if s.strip() and not s.startswith('#')]
    if lines and lines[0].isdigit():
        count = int(lines.pop(0))
        if count != len(lines):
            raise ValueError('rank header mismatch')
    terms = [tuple(map(int, s.removeprefix('R ').split())) for s in lines]
    for shape in dict.fromkeys(itertools.permutations(hint)):
        try:
            top.exact(shape, terms)
            return shape, terms
        except AssertionError:
            pass
    raise ValueError('no orientation verifies')


def witness_files(roots):
    for root in map(Path, roots):
        if root.is_file():
            yield root
        else:
            for pattern in ('*.mfw', '*.mfw.gz.b64', 'best.txt', 'matmul_*_gf2.txt'):
                yield from root.rglob(pattern)


_WORKER_CACHE = {}


def _init_worker(cache):
    global _WORKER_CACHE
    _WORKER_CACHE = cache


def _check(path_str):
    """(path, sha256, [shape, rank] | None, freshly verified?) for one witness file."""
    path = Path(path_str)
    try:
        raw = load(path)
    except (OSError, ValueError):
        return path_str, None, None, False
    digest = hashlib.sha256(raw).hexdigest()
    if digest in _WORKER_CACHE:
        return path_str, digest, _WORKER_CACHE[digest], False
    try:
        shape, terms = decode(path, raw)
        return path_str, digest, [list(shape), len(terms)], True
    except (AssertionError, ValueError, IndexError):
        return path_str, digest, None, True


def witnesses(roots, cache, jobs=1):
    """Best verified witness per canonical shape; new tensors are checked in parallel."""
    paths = sorted({str(p) for p in witness_files(roots)})
    if jobs > 1:
        pool = concurrent.futures.ProcessPoolExecutor(jobs, initializer=_init_worker,
                                                      initargs=(dict(cache),))
        results = pool.map(_check, paths, chunksize=16)
    else:
        _init_worker(cache)
        pool, results = None, map(_check, paths)
    best, fresh = {}, 0
    for path, digest, verdict, checked in results:
        if digest is None:
            continue
        if checked:
            cache[digest] = verdict
            fresh += 1
        if verdict:
            shape, rank = verdict
            key = tuple(sorted(shape))
            if key not in best or rank < best[key][0]:
                best[key] = (rank, path)
    if pool is not None:
        pool.shutdown()
    print(f'{len(paths)} witness files; {fresh} newly verified', file=sys.stderr)
    return best


def fmm_ranks(names):
    """{canonical shape: {ring: rank}} from FMM-format file names."""
    ranks = {}
    for name in names:
        match = RING.search(name)
        if match and '/known/' not in name:
            key = tuple(sorted(map(int, match.group(1, 2, 3))))
            ring, rank = match.group(5), int(match.group(4))
            ranks.setdefault(key, {})
            ranks[key][ring] = min(rank, ranks[key].get(ring, rank))
    return ranks


def public_tables(args):
    lille = {tuple(e['format']): e['rank'] for e in json.loads(Path(args.lille).read_text())['entries']}
    any_ring, gf2 = {}, {}

    def offer(table, key, rank):
        table[key] = min(rank, table.get(key, rank))

    if args.matmulcatalog:
        for scheme in json.loads(Path(args.matmulcatalog).read_text())['schemes']:
            if scheme.get('commutative'):
                continue
            key = tuple(sorted(scheme['format']))
            offer(any_ring, key, scheme['rank'])
            if 'F2' in scheme['fields']:
                offer(gf2, key, scheme['rank'])
    names = []
    if args.fmm_repo:
        names += subprocess.check_output(['git', '-C', args.fmm_repo, 'ls-tree', '-r', '--name-only',
                                          args.fmm_revision, 'schemes'], text=True).split()
    for extra in args.extra_repo:
        names += [str(p.relative_to(extra)) for p in Path(extra).rglob('*.json')]
    for key, rings in fmm_ranks(names).items():
        for ring, rank in rings.items():
            offer(any_ring, key, rank)
            if ring in ('ZT', 'Z'):
                offer(gf2, key, rank)
    for key, rank in lille.items():
        offer(any_ring, key, rank)
    return lille, any_ring, gf2


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    parser.add_argument('--lille', required=True)
    parser.add_argument('--matmulcatalog')
    parser.add_argument('--fmm-repo')
    parser.add_argument('--fmm-revision', default='HEAD')
    parser.add_argument('--extra-repo', action='append', default=[])
    parser.add_argument('--witness', action='append', required=True, help='file or directory (repeatable)')
    parser.add_argument('--cache', help='JSON verification cache keyed by SHA-256')
    parser.add_argument('--jobs', type=int, default=max(1, min(8, (os.cpu_count() or 2) - 2)),
                        help='processes for verifying new witness files')
    parser.add_argument('--json', help='write every row here')
    parser.add_argument('-v', '--verbose', action='store_true')
    args = parser.parse_args(argv)
    cache = json.loads(Path(args.cache).read_text()) if args.cache and Path(args.cache).exists() else {}
    ours = witnesses(args.witness, cache, args.jobs)
    if args.cache:
        Path(args.cache).write_text(json.dumps(cache))
    lille, any_ring, gf2 = public_tables(args)
    rows = []
    for key, (rank, path) in sorted(ours.items()):
        best_any, best_gf2 = any_ring.get(key), gf2.get(key)
        if best_any is not None and rank < best_any:
            kind = 'below_all'
        elif best_gf2 is not None and rank < best_gf2:
            kind = 'gf2_valid_only'
        elif best_any is not None and rank == best_any:
            kind = 'tie'
        elif best_any is None:
            kind = 'no_public_rank'
        else:
            kind = 'above'
        rows.append(dict(shape='x'.join(map(str, key)), rank=rank, kind=kind, lille=lille.get(key),
                         best_any=best_any, best_gf2_valid=best_gf2, path=path))
    if args.json:
        Path(args.json).write_text(json.dumps(rows, indent=1) + '\n')
    counts = {}
    for row in rows:
        counts[row['kind']] = counts.get(row['kind'], 0) + 1
    print(f'{len(rows)} shapes with verified witnesses: ' +
          ', '.join(f'{k}={counts.get(k, 0)}' for k in ('below_all', 'gf2_valid_only', 'tie', 'above', 'no_public_rank')))
    if args.verbose:
        for row in rows:
            if row['kind'] in ('below_all', 'gf2_valid_only'):
                print(f"{row['kind']:>15} {row['shape']:>10} {row['rank']:>6} any={row['best_any']} "
                      f"gf2={row['best_gf2_valid']} lille={row['lille']}")
    return 0


if __name__ == '__main__':
    sys.exit(main())
