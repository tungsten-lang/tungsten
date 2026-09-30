#!/usr/bin/env python3
"""Screen public integer-coefficient schemes for GF(2)-only rank reductions.

Public ternary (ZT) and integer (Z) schemes reduce modulo two to exact GF(2)
decompositions of the same rank. Their authors search over ZT/Z/Q, so a
GF(2) directed walk can find reductions that do not lift. This tool:

  seeds  convert every distinct integer scheme at each shape's best integer
         rank (or within best+N) from a local checkout of a
         FastMatrixMultiplication-format repository into MFW1 seeds;
  walk   run the finite directed walker (tools/wide_rect_walk.w) over seeds in
         parallel and append one JSON row per walk.

The ring comes from the file-name suffix, not the directory (a
`serendipitous_base` file can be `_Q`). Rational files are skipped unless
`--include-rational`; then the exact parity gate keeps only schemes whose
denominators are all odd (those reduce to GF(2)). Every
seed passes a full GF(2) tensor expansion before it is written; the native
walker re-checks its input and output. Walks are deterministic in
(seed, steps, nonce), so each row is replayable. Public ranks are
comparison data only; this tool makes no record claim.
"""
import argparse
from collections import Counter
import concurrent.futures
from fractions import Fraction
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import zlib

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import screen_top_two_projection_children as top  # noqa: E402

SCHEME = re.compile(r'(?:^|/)(\d+)x(\d+)x(\d+)_m(\d+)(?:_[^/]*)?_(ZT|Z|Q)\.json$')
RESULT = re.compile(r'seed_rank=(\d+) rank=(\d+) moves=(\d+) accepted=(\d+) '
                    r'no_pair=(\d+) escapes=(\d+)')


def parity(value):
    """Reduce an exact integer or odd-denominator rational modulo two."""
    if type(value) is not int and not (isinstance(value, str) and
                                       re.fullmatch(r'-?\d+/[1-9]\d*', value)):
        raise ValueError('coefficient must be an exact integer or rational')
    value = Fraction(value)
    if value.denominator % 2 == 0:
        raise ValueError('even denominator: scheme does not reduce to GF(2)')
    return value.numerator & 1


def bits(mask):
    while mask:
        low = mask & -mask
        yield low.bit_length() - 1
        mask ^= low


def reduce_mod2(data):
    """FastMatrixMultiplication JSON -> (shape, source rank, exact GF(2) terms)."""
    shape = tuple(data['n'])
    if len(shape) != 3 or min(shape) < 1 or data.get('z2') not in (False, None):
        raise ValueError('unsupported scheme header')
    n, m, p = shape
    rank = data['m']
    banks = []
    for name, width in (('u', n * m), ('v', m * p), ('w', p * n)):
        rows = data[name]
        if len(rows) != rank or any(len(row) != width for row in rows):
            raise ValueError(f'{name} has the wrong size')
        banks.append([sum(parity(value) << i for i, value in enumerate(row)) for row in rows])
    # The public W row is indexed C[k][i]; MFW1 indexes C[i][k].
    counts = Counter((a, b, sum(1 << ((j % n) * p + j // n) for j in bits(c)))
                     for a, b, c in zip(*banks))
    terms = sorted(term for term, count in counts.items() if count % 2 and all(term))
    top.exact(shape, terms)
    return shape, rank, terms


def integer_files(repo, revision, alternatives=0, rational=False):
    """{canonical shape: [(rank, path)]} within best integer rank + alternatives.

    The window is anchored on ZT/Z files: a lower `_Q` file usually has even
    denominators and must not crowd out the shape's GF(2)-valid seeds.
    """
    names = subprocess.check_output(['git', '-C', str(repo), 'ls-tree', '-r', '--name-only',
                                     revision, 'schemes'], text=True).split()
    found = {}
    for name in names:
        match = SCHEME.search(name)
        if not match or '/known/' in name or (match.group(5) == 'Q' and not rational):
            continue
        key = tuple(sorted(map(int, match.group(1, 2, 3))))
        found.setdefault(key, []).append((int(match.group(4)), match.group(5) != 'Q', name))
    result = {}
    for key, files in found.items():
        limit = min((rank for rank, integral, _ in files if integral), default=None)
        limit = max(rank for rank, _, _ in files) if limit is None else limit + alternatives
        result[key] = sorted((rank, name) for rank, _, name in files if rank <= limit)
    return result


def seeds(args):
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=False)
    revision = subprocess.check_output(['git', '-C', args.repo, 'rev-parse', args.revision],
                                       text=True).strip()
    rows, errors, seen = [], [], set()
    files = integer_files(args.repo, revision, args.alternatives, args.include_rational)
    for key, rank, name in sorted((k, r, n) for k, items in files.items() for r, n in items):
        if not (args.min_dim <= min(key) and args.min_max_dim <= max(key) <= args.max_dim):
            continue
        # A partial clone fetches the blob on demand.
        raw = subprocess.check_output(['git', '-C', args.repo, 'show', f'{revision}:{name}'])
        try:
            shape, source_rank, terms = reduce_mod2(json.loads(raw))
            if source_rank != rank:
                raise ValueError('file-name rank disagrees with the scheme')
        except (ValueError, AssertionError, KeyError) as exc:
            errors.append(dict(source=name, error=str(exc)))
            continue
        blob = top.blob(shape, terms)
        digest = hashlib.sha256(blob).hexdigest()
        if digest in seen:  # e.g. an addition-reduced copy with identical GF(2) terms
            continue
        seen.add(digest)
        path = out / f"{'x'.join(map(str, shape))}_r{len(terms)}_{digest[:8]}.mfw"
        path.write_bytes(blob)
        rows.append(dict(shape='x'.join(map(str, shape)), canonical='x'.join(map(str, key)),
                         source=name, source_rank=rank, source_sha256=hashlib.sha256(raw).hexdigest(),
                         gf2_rank=len(terms), mfw=str(path), mfw_sha256=digest))
    manifest = dict(schema=1, field='GF(2)', record_claim=False, repository=args.url or args.repo,
                    revision=revision, seeds=rows, errors=errors)
    (out / 'seeds.json').write_text(json.dumps(manifest, indent=1) + '\n')
    cancelled = sum(1 for row in rows if row['gf2_rank'] < row['source_rank'])
    print(f'{len(rows)} exact GF(2) seeds at {revision[:12]}; {cancelled} with mod-2 '
          f'cancellations; {len(errors)} rejected')
    return 0


def walk_one(walker, seed, steps, nonce, outdir):
    # Several seeds can share shape, rank and nonce (alternative presentations): key the output
    # by the seed's content hash so concurrent walks never overwrite each other.
    tag = (seed.get('mfw_sha256') or hashlib.sha256(seed['mfw'].encode()).hexdigest())[:8]
    out = outdir / f"{seed['shape']}_r{seed['gf2_rank']}_{tag}_n{nonce}_s{steps}.mfw"
    if out.exists():
        out.unlink()
    proc = subprocess.run([walker, seed['shape'], seed['mfw'], str(out), str(steps), str(nonce)],
                          capture_output=True, text=True)
    row = dict(shape=seed['shape'], canonical=seed['canonical'], seed=seed['mfw'],
               seed_sha256=seed.get('mfw_sha256'), steps=steps, nonce=nonce,
               returncode=proc.returncode)
    match = RESULT.search(proc.stdout)
    if proc.returncode == 0 and match:
        raw = out.read_bytes()
        row.update(seed_rank=int(match.group(1)), rank=int(match.group(2)),
                   moves=int(match.group(3)), output=str(out),
                   sha256=hashlib.sha256(raw).hexdigest())
    else:
        row['error'] = (proc.stdout + proc.stderr)[-400:]
    return row


def walk(args):
    manifest = json.loads(Path(args.seeds).read_text())
    rows = manifest['seeds'] if isinstance(manifest, dict) else manifest
    rows = [row for row in rows if row['gf2_rank'] >= args.min_rank]
    log = Path(args.out)
    outdir = log.parent / (log.stem + '_mfw')
    outdir.mkdir(parents=True, exist_ok=True)
    done = set()
    if log.exists():
        for line in log.read_text().splitlines():
            row = json.loads(line)
            # Content hash first: a regenerated seed directory must not repeat finished walks.
            done.add((row.get('seed_sha256') or row['seed'], row['nonce'], row['steps']))
    work = []
    for repeat in range(args.repeats):
        for seed in sorted(rows, key=lambda row: row['gf2_rank'], reverse=args.largest_first):
            nonce = args.nonce_base + 7919 * repeat + zlib.crc32(seed['shape'].encode()) % 1000003
            if (seed.get('mfw_sha256') or seed['mfw'], nonce, args.steps) not in done:
                work.append((seed, nonce))
    print(f'{len(work)} walks queued', flush=True)
    with open(log, 'a') as sink, concurrent.futures.ThreadPoolExecutor(args.jobs) as pool:
        futures = [pool.submit(walk_one, args.walker, seed, args.steps, nonce, outdir)
                   for seed, nonce in work]
        for future in concurrent.futures.as_completed(futures):
            row = future.result()
            sink.write(json.dumps(row) + '\n')
            sink.flush()
            if 'error' in row:
                print('ERROR', row['shape'], row['error'][-200:], flush=True)
            elif row['rank'] < row['seed_rank']:
                print('DROP', row['shape'], row['seed_rank'], '->', row['rank'], flush=True)
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    sub = parser.add_subparsers(dest='command', required=True)
    s = sub.add_parser('seeds', help='convert public integer schemes to exact GF(2) seeds')
    s.add_argument('--repo', required=True, help='local (partial) clone in FastMatrixMultiplication format')
    s.add_argument('--revision', default='HEAD')
    s.add_argument('--url', help='canonical repository URL recorded in the manifest')
    s.add_argument('--out', required=True, help='new output directory')
    s.add_argument('--min-dim', type=int, default=2)
    s.add_argument('--min-max-dim', type=int, default=5, help='skip shapes whose largest side is smaller')
    s.add_argument('--max-dim', type=int, default=16)
    s.add_argument('--include-rational', action='store_true',
                   help='also try _Q files; only odd-denominator schemes pass the parity gate')
    s.add_argument('--alternatives', type=int, default=0,
                   help='also convert every integer file within best+N (distinct GF(2) seeds only)')
    s.set_defaults(func=seeds)
    w = sub.add_parser('walk', help='directed GF(2) walks from converted seeds')
    w.add_argument('--seeds', required=True)
    w.add_argument('--walker', required=True, help='compiled tools/wide_rect_walk.w')
    w.add_argument('--out', required=True, help='JSONL log (appended; finished walks are skipped)')
    w.add_argument('--steps', type=int, default=40_000_000)
    w.add_argument('--jobs', type=int, default=max(1, (os.cpu_count() or 2) - 2))
    w.add_argument('--repeats', type=int, default=1, help='independent nonces per seed')
    w.add_argument('--nonce-base', type=int, default=1)
    w.add_argument('--min-rank', type=int, default=0)
    w.add_argument('--largest-first', action='store_true', help='queue high-rank seeds first')
    w.set_defaults(func=walk)
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == '__main__':
    sys.exit(main())
