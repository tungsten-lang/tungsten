#!/usr/bin/env python3
"""Independent full replay of native basis/projection jobs and durable queue."""
from collections import Counter
from hashlib import sha256
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'benchmarks/matmul/metaflip'))
from pair_reduction_scan import reduce_pairs
from verify_cofactor_mergers import compress_shared, refactor_shared
from verify_coordinate_projections import project_grid
from verify_representation_portfolio import parse_terms


def blob(shape, terms):
    return (f'MFR1 {" ".join(map(str, shape))} {len(terms)}\n' +
            ''.join(' '.join(map(str, t))+'\n' for t in sorted(terms))).encode()


def identity(shape, terms):
    return sha256(blob(shape, terms)).hexdigest()


def exact(shape, terms):
    n, m, p = shape
    got = Counter()
    for term in terms:
        widths = (n*m, m*p, n*p)
        assert all(0 < v < 1 << w for v, w in zip(term, widths))
        positions = [[b for b in range(w) if v >> b & 1] for v, w in zip(term, widths)]
        for a in positions[0]:
            for b in positions[1]:
                for c in positions[2]:
                    got[a,b,c] ^= 1
    assert {key for key, value in got.items() if value} == {
        (i*m+j, j*p+k, i*p+k) for i in range(n) for j in range(m) for k in range(p)}


def expected_outputs(shape, source):
    source = sorted(source)
    source_id = identity(shape, source)
    expected = {}

    def add(s, terms):
        terms = sorted(terms)
        exact(s, terms)
        key = identity(s, terms)
        if key != source_id:
            expected[key] = (s, terms)
        return terms

    clean, _ = reduce_pairs(source, (0,1,2))
    clean, _ = compress_shared(clean, max_bits=63)
    clean = add(shape, clean)

    def pairs(terms):
        return sum(any(a == b for a, b in zip(left, right))
                   for i, left in enumerate(terms) for right in terms[:i])

    selected = clean
    for mode in range(6):
        proposed, _ = refactor_shared(clean, mode//2, max_bits=63, reverse_columns=bool(mode%2))
        proposed, _ = compress_shared(proposed, max_bits=63)
        proposed = add(shape, proposed)
        if (len(proposed), -pairs(proposed)) < (len(selected), -pairs(selected)):
            selected = proposed
    bases = [clean] + ([selected] if selected != clean else [])
    for base in bases:
        for axis, size in enumerate(shape):
            if size < 2:
                continue
            for removed in range(size):
                keep = [list(range(n)) for n in shape]
                keep[axis].remove(removed)
                s = tuple(map(len, keep))
                child = project_grid(shape, base, keep)
                child, _ = reduce_pairs(child, (0,1,2))
                child, _ = compress_shared(child, max_bits=63)
                add(s, child)
    return expected


def check(binary, external_parent=None):
    subprocess.run([binary], check=True, timeout=30)
    with tempfile.TemporaryDirectory(prefix='metaflip-native-queue-') as directory:
        subprocess.run([binary, '--queue-test', directory], check=True, timeout=30)
    seeds = ROOT / 'bits/tungsten-metaflip/lib/metaflip/seeds/gf2'
    inputs = []
    for name in ('matmul_2x2_rank7_strassen_gf2.txt', 'matmul_2x2_rank7_d36_gl120_gf2.txt'):
        terms = parse_terms((seeds/name).read_bytes(), 7)
        inputs.append(((2,2,2), terms))
    shape = (3,4,2)
    n,m,p = shape
    inputs.append((shape, [(1 << (i*m+j), 1 << (j*p+k), 1 << (i*p+k))
                           for i in range(n) for j in range(m) for k in range(p)]))
    if external_parent is not None:
        # Optional imported regression stays outside the distributable tree.
        inputs.append(((4,8,4), parse_terms(Path(external_parent).read_bytes(), 94)))
    outputs = 0
    with tempfile.TemporaryDirectory(prefix='metaflip-native-replay-') as directory:
        root = Path(directory)
        for name in ('objects', 'tasks', 'results'):
            (root/name).mkdir()
        for job, (shape, terms) in enumerate(inputs, 1):
            data = blob(shape, terms); key = sha256(data).hexdigest()
            (root/'objects'/f'{key}.tensor').write_bytes(data)
            (root/'tasks'/str(job)).write_text(key+'\n')
        subprocess.run([binary, '--refine-batch', directory, '1', str(len(inputs))], check=True, timeout=30)
        for job, (shape, terms) in enumerate(inputs, 1):
            expected = expected_outputs(shape, terms)
            if shape == (4,8,4):
                assert any(s == (4,7,4) and len(values) == 85
                           for s, values in expected.values())
            lines = (root/'results'/str(job)).read_text().splitlines()
            assert lines[0] == f'MFR_RESULT1 {job} {identity(shape, terms)} {len(expected)}'
            actual = [line.split()[0] for line in lines[1:]]
            assert len(actual) == len(set(actual)) and set(actual) == set(expected)
            for key, (s, values) in expected.items():
                data = (root/'objects'/f'{key}.tensor').read_bytes()
                assert data == blob(s, values) and sha256(data).hexdigest() == key
                index = root/'by-shape'/'x'.join(map(str, s))/key
                assert index.read_text() == key+'\n'
                outputs += 1
        # A cancelled job never claims completion; replay is idempotent.
        cancelled = str(len(inputs)+1)
        corrupted = str(len(inputs)+2)
        algebraically_invalid = str(len(inputs)+3)
        (root/'tasks'/cancelled).write_text(identity(*inputs[0])+'\n')
        (root/'stop').write_text('stop\n')
        subprocess.run([binary, '--refine-batch', directory, cancelled, cancelled], check=True, timeout=30)
        assert not (root/'results'/cancelled).exists()
        (root/'stop').unlink()
        subprocess.run([binary, '--refine-batch', directory, cancelled, cancelled], check=True, timeout=30)
        before = (root/'results'/cancelled).read_bytes()
        subprocess.run([binary, '--refine-batch', directory, cancelled, cancelled], check=True, timeout=30)
        assert (root/'results'/cancelled).read_bytes() == before
        # A corrupted input object must not leave a success manifest.
        key = identity(*inputs[0])
        (root/'objects'/f'{key}.tensor').write_bytes(b'MFR1 corrupt\n')
        (root/'tasks'/corrupted).write_text(key+'\n')
        failed = subprocess.run([binary, '--refine-batch', directory, corrupted, corrupted], timeout=30)
        assert failed.returncode != 0 and not (root/'results'/corrupted).exists()
        # Correct hash/format does not replace the algebraic identity check.
        invalid = blob((2,2,2), [(1,1,1)])
        bad_key = sha256(invalid).hexdigest()
        (root/'objects'/f'{bad_key}.tensor').write_bytes(invalid)
        (root/'tasks'/algebraically_invalid).write_text(bad_key+'\n')
        failed = subprocess.run([binary, '--refine-batch', directory, algebraically_invalid, algebraically_invalid], timeout=30)
        assert failed.returncode != 0 and not (root/'results'/algebraically_invalid).exists()
        canonical = blob(*inputs[0])
        lines = canonical.splitlines(keepends=True)
        malformed = [canonical.replace(b'MFR1 2 ', b'MFR1 02 ', 1),
                     canonical+b'\n', canonical[:-1],
                     lines[0]+b''.join(reversed(lines[1:])),
                     lines[0]+b'9223372036854775808 '+b' '.join(lines[1].split()[1:])+b'\n'+b''.join(lines[2:])]
        for job, data in enumerate(malformed, len(inputs)+4):
            bad_key = sha256(data).hexdigest()
            (root/'objects'/f'{bad_key}.tensor').write_bytes(data)
            (root/'tasks'/str(job)).write_text(bad_key+'\n')
            failed = subprocess.run([binary, '--refine-batch', directory, str(job), str(job)], timeout=30)
            assert failed.returncode != 0 and not (root/'results'/str(job)).exists()
    print(f'PASS native refinement replay: {len(inputs)} jobs, {outputs} exact outputs; resume, dedup, cancellation and corruption')


if __name__ == '__main__':
    check(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else None)
