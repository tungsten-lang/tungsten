#!/usr/bin/env python3
"""Multiword native algebra against an independent integer row-equation oracle.

Optional --corpus is the retained construction/cleanup.json from the dated
backtracking audit. No external witness is redistributed by this test.
"""
from collections import defaultdict
from hashlib import sha256
from pathlib import Path
import argparse
import json
import random
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'benchmarks/matmul/metaflip'))
from verify_cofactor_mergers import compress_shared
from verify_representation_portfolio import parse_terms
from packed_composition_parity_test import exact, bits


def blob(shape, terms):
    return (f'MFW1 {" ".join(map(str, shape))} {len(terms)}\n' +
            ''.join(' '.join(f'{v:x}' for v in t) + '\n' for t in sorted(terms))).encode()


def read_blob(raw):
    header, *lines = raw.decode().splitlines()
    tag, n, m, p, rank = header.split()
    shape = tuple(map(int, (n, m, p)))
    terms = [tuple(int(v, 16) for v in line.split()) for line in lines]
    assert tag == 'MFW1' and len(terms) == int(rank)
    assert raw == blob(shape, terms) and len(terms) == len(set(terms))
    return shape, terms


def same_tensor(source, result):
    fibers = defaultdict(int)
    for u, v, w in [*source, *result]:
        for a in bits(u):
            for b in bits(v):
                fibers[a, b] ^= w
    assert not any(fibers.values())


def check(binary, corpus=None, report=None):
    binary = str(Path(binary).resolve())
    gate = subprocess.run([binary], capture_output=True, text=True, timeout=60, check=True)
    assert 'PASS wide matrix' in gate.stdout
    rng = random.Random(941071)
    counts = dict(random_inputs=0, budget_runs=0, limited=0, reduced=0, full_tensors=0)
    corpus_rows = []
    with tempfile.TemporaryDirectory(prefix='metaflip-wide-native-') as temp:
        temp = Path(temp)

        def run(shape, source, budget, expected=None):
            before = blob(shape, source)
            inp, out = temp / 'source.tensor', temp / 'result.tensor'
            inp.write_bytes(before)
            child = subprocess.run([binary, '--clean', str(inp), str(out), str(budget)],
                                   capture_output=True, text=True, timeout=60, check=True)
            fields = child.stdout.strip().split()
            assert fields[0] == 'WIDE_CLEAN' and len(fields) == 8, child.stdout
            n, r, used, limited, axes, groups, saved = map(int, fields[1:])
            target, result = read_blob(out.read_bytes())
            assert target == shape and n == len(source) and r == len(result) <= n
            assert limited in (0, 1) and (budget == 0 or used <= budget)
            assert axes >= 0 and groups >= 0 and 0 <= saved <= n-r
            assert inp.read_bytes() == before
            if expected is not None:
                assert not limited and result == sorted(expected), (shape, n, r, len(expected))
            same_tensor(source, result)
            counts['budget_runs'] += 1
            counts['limited'] += limited
            counts['reduced'] += r < n
            return result, dict(before=n, after=r, work=used, limited=limited,
                                axes=axes, groups=groups, saved=saved,
                                mfw_sha256=sha256(out.read_bytes()).hexdigest())

        for trial in range(96):
            shape = (32, 32, 32)
            width = (31, 32, 33, 63, 64, 65, 127, 256, 511, 756, 1023, 1024)[trial % 12]
            palette = [sum(1 << b for b in rng.sample(range(width), min(width, rng.randint(1, 5))))
                       for _ in range(9)]
            source = set()
            for i in range(3 + trial % 97):
                source.add(tuple(palette[rng.randrange(len(palette))] for _ in range(3)))
            # A reducible rank-three matrix with no pair-only reduction.
            a, b, c, d, e = rng.sample(range(width), 5)
            fixed = 1 << a
            source.update(((fixed, 1 << b, 1 << e), (fixed, 1 << c, 1 << d),
                           (fixed, (1 << b) ^ (1 << c), (1 << d) ^ (1 << e))))
            source = sorted(source)
            expected, _ = compress_shared(source, max_bits=1024)
            run(shape, source, 0, expected)
            for budget in (1, 3000, 50000):
                run(shape, source, budget)
            counts['random_inputs'] += 1

        # Malformed canonical files must fail before output is written.
        good = b'MFW1 1 1 2 2\n1 1 1\n1 2 2\n'
        mutations = [good+b'\n', good[:-1], good.replace(b'\n1 1 1\n', b'\n01 1 1\n'),
                     good.replace(b'1 1 2 2', b'01 1 2 2'),
                     good.replace(b'\n1 2 2\n', b'\n1 0 2\n'), good.replace(b'\n1 2 2\n', b'\n1 A 2\n'),
                     good.replace(b'\n1 2 2\n', b'\n1 4 2\n'), good.replace(b'\n1 2 2\n', b'\n1 1 1\n'),
                     b'MFW1 1 1 2 2\n1 2 2\n1 1 1\n']
        for raw in mutations:
            inp, out = temp/'bad.tensor', temp/'bad-output.tensor'
            inp.write_bytes(raw)
            child = subprocess.run([binary, '--clean', str(inp), str(out), '0'],
                                   capture_output=True, text=True, timeout=10)
            assert child.returncode != 0 and not out.exists(), (raw, child.stdout, child.stderr)

        if corpus:
            corpus = Path(corpus).resolve()
            data = json.loads(corpus.read_text())
            assert data['summary']['complete']
            for row in data['rows']:
                path = Path(row['source'])
                if not path.exists():
                    # Cold archive relocation keeps the source suffix.
                    path = corpus.parent / Path(*path.parts[path.parts.index('products'):])
                raw = path.read_bytes()
                assert sha256(raw).hexdigest() == row['sha256']
                source = parse_terms(raw, row['before'])
                shape = tuple(row['shape'])
                exact(shape, source)
                expected, _ = compress_shared(source, max_bits=row['max_bits'])
                result, audit = run(shape, source, 0, expected)
                assert len(result) == row['after']
                exact(shape, result)
                counts['full_tensors'] += 2
                # Exercise the actual background cap as well as full parity.
                bounded, limited = run(shape, source, 20000000)
                exact(shape, bounded)
                counts['full_tensors'] += 1
                corpus_rows.append(dict(shape=shape, source_sha256=row['sha256'],
                                        full=audit, bounded=limited))
    result = dict(complete=True, record_claim=False, counts=counts, corpus=corpus_rows,
                  binary_sha256=sha256(Path(binary).read_bytes()).hexdigest())
    if report:
        path = Path(report)
        assert not path.exists()
        path.write_text(json.dumps(result, indent=2)+'\n')
    print(json.dumps(result))


if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('binary')
    p.add_argument('--corpus', type=Path)
    p.add_argument('--report', type=Path)
    a = p.parse_args()
    check(a.binary, a.corpus, a.report)
