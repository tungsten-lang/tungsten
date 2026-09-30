#!/usr/bin/env python3
"""Regenerates spec/fixtures/gf2_scheme/ from the ORIGINAL tooling (the oracles).

  generate.py --corpus DIR       (DIR = a port corpus: corpus.tsv + mfw/<sha256>.mfw)

writes, next to this file:

  shape_dir/2x2x2/certificate.mfw
                            a copy of strassen_2x2x2.mfw whose shape is only in its path
  <name>.mfw                canonical MFW1 bases (seeds and corpus tensors, re-serialised with the
                            Python `blob`), and the legacy-format twins <name>_R.txt (R-prefixed
                            decimal rows) and 3x3x3_rank23_checkpoint.txt (rank header + decimal rows)
  mutants/<base>__<kind>.mfw
                            one damaged copy of a base per rejection category
  cases.tsv                 what the originals say about every fixture and mutant:
                              file  shape  ruby_status  ruby_message_or_record  python_status
                            (Ruby = tools/verify_tensor.rb, Python = read_blob + exact; the Ruby
                            message has the fixture path replaced by @FIXTURES@)
  bits.tsv                  Python bits/popcount/T/remap of assorted masks (mmc_gf2_alg.py)
  orient.tsv                SHA-256 of the blob of every S3 orientation of each base (mmc_gf2_alg.py)
  naive.tsv                 rank, density and blob SHA-256 of the naive schemes (mmc_gf2_alg.naive)
  orient_to.tsv             SHA-256 of the blob of verify_cofactor_mergers.orient(shape, terms, target) for
                            every permuted target shape of each base
  clean.tsv                 a scheme with zero-factor terms and repeated terms, and mmc_gf2_alg.clean of it
  defects.tsv               the wrong entry of each inexact mutant: coordinates from Ruby, the expected
                            and actual w masks recomputed in Python from the terms

Everything here is derived from the Python and Ruby originals, never from the Tungsten port.
"""
import argparse
import csv
import hashlib
import json
from pathlib import Path
import random
import subprocess
import sys

HERE = Path(__file__).resolve().parent
BIT = HERE.parents[2]                 # bits/tungsten-metaflip
ROOT = HERE.parents[4]                # repository root
SPEC = BIT / 'spec'
TOOLS = BIT / 'tools'
sys.path[:0] = [str(SPEC), str(TOOLS), str(ROOT / 'benchmarks/matmul/metaflip')]
from wide_matrix_cleanup_parity_test import blob, read_blob  # noqa: E402
from packed_composition_parity_test import exact  # noqa: E402
from verify_cofactor_mergers import orient  # noqa: E402
import mmc_gf2_alg as alg  # noqa: E402

RUBY = TOOLS / 'verify_tensor.rb'
SEEDS = BIT / 'lib/metaflip/seeds/gf2'
BASES = {  # name -> (source, shape)
    'strassen_2x2x2': ('seed:matmul_2x2_rank7_strassen_gf2.txt', (2, 2, 2)),
    'rank23_3x3x3': ('seed:matmul_3x3_rank23_d139_gf2.txt', (3, 3, 3)),
    'rank47_4x4x4': ('seed:matmul_4x4_rank47_d450_gf2.txt', (4, 4, 4)),
    'repeated94_4x4x8': ('corpus:407bc69994a3', (4, 4, 8)),
    'wide68_2x4x17': ('corpus:70c680cfbf69', (2, 4, 17)),
    'wide145_2x5x29': ('corpus:4819137986dc', (2, 5, 29)),
    'wide264_4x11x24': ('corpus:cb438bdd9ea0', (4, 11, 24)),
    'wide529_3x23x23': ('corpus:4d3c629c6bff', (3, 23, 23)),
}
MUTATED = ('strassen_2x2x2', 'rank23_3x3x3', 'wide68_2x4x17', 'wide145_2x5x29')
BIG_MUTATED = ('wide264_4x11x24',)


def seed_terms(name):
    """Terms of a decimal seed file (optional rank line, optional R prefixes)."""
    terms = []
    for line in (SEEDS / name).read_text().split('\n'):
        words = line.split()
        if words and words[0] == 'R':
            words = words[1:]
        if len(words) == 3:
            terms.append(tuple(int(w) for w in words))
    return terms


def base_terms(source, corpus):
    kind, _, ref = source.partition(':')
    if kind == 'seed':
        return seed_terms(ref)
    for row in csv.DictReader(open(Path(corpus) / 'corpus.tsv'), delimiter='\t'):
        if row['sha256'].startswith(ref):
            return read_blob((Path(corpus) / 'mfw' / (row['sha256'] + '.mfw')).read_bytes())[1]
    raise SystemExit(f'no corpus tensor {ref}')


def ruby(path, shape):
    run = subprocess.run(['ruby', str(RUBY), '--shape', 'x'.join(map(str, shape)), str(path)],
                         capture_output=True, text=True)
    prefix = str(HERE)
    if run.returncode == 0:
        record = json.loads(run.stdout)[0]
        return 0, '\t'.join(str(record[k]) for k in ('rank', 'density', 'sha256'))
    message = run.stderr.strip().replace('Tensor verification failed: ', '', 1)
    return 1, message.replace(prefix, '@FIXTURES@')


def python(path, shape):
    try:
        got, terms = read_blob(Path(path).read_bytes())
        assert got == tuple(shape)
        exact(got, terms)
    except Exception:  # every rejection is an assertion or a parse error
        return 1
    return 0


def mutants(shape, terms):
    n, m, p = shape
    rng = random.Random(20260930)
    raw = blob(shape, terms)
    header, *rows = raw.split(b'\n')
    rows = rows[:-1]
    tag, *fields = header.split()
    out = {}

    def with_terms(new):
        return blob(shape, new)

    def flipped(axis, width):
        new = list(terms)
        i = len(new) // 2
        row = list(new[i])
        mutated = row[axis] ^ (1 << (width - 1))
        row[axis] = mutated if mutated else row[axis] ^ 1
        new[i] = tuple(row)
        return with_terms(new)

    out['bit_flip_u'] = flipped(0, n * m)
    out['bit_flip_v'] = flipped(1, m * p)
    out['bit_flip_w'] = flipped(2, n * p)
    out['dropped_term'] = with_terms(terms[:len(terms) // 2] + terms[len(terms) // 2 + 1:])
    out['duplicated_term'] = with_terms(list(terms) + [terms[0]])
    out['cancelling_pair'] = with_terms(list(terms) + [terms[0], terms[0]])
    if n != p:
        out['transposed_c'] = with_terms([(u, v, alg.remap(w, alg._ttab(n, p))) for u, v, w in terms])
    out['zero_factor'] = with_terms([(0, terms[0][1], terms[0][2])] + list(terms[1:]))
    out['wide_factor'] = with_terms([(terms[0][0] | 1 << (n * m), terms[0][1], terms[0][2])] + list(terms[1:]))
    out['wrong_term_count'] = b' '.join([tag, *fields[:3], str(len(terms) + 1).encode()]) + b'\n' + b'\n'.join(rows) + b'\n'
    out['short_file'] = raw[:raw.rfind(b'\n', 0, len(raw) - 1) + 1]
    out['shape_mismatch'] = b' '.join([tag, fields[0], fields[1], str(p + 1).encode(), fields[3]]) + b'\n' + b'\n'.join(rows) + b'\n'
    out['bad_tag'] = b'MFX1' + raw[4:]
    out['bad_header_fields'] = b' '.join([tag, *fields[:3]]) + b'\n' + b'\n'.join(rows) + b'\n'
    out['zero_dimension'] = b' '.join([tag, b'0', fields[1], fields[2], fields[3]]) + b'\n' + b'\n'.join(rows) + b'\n'
    out['header_double_space'] = header.replace(b' ', b'  ', 1) + b'\n' + b'\n'.join(rows) + b'\n'
    swapped = list(rows)
    swapped[0], swapped[-1] = swapped[-1], swapped[0]
    out['non_canonical_order'] = header + b'\n' + b'\n'.join(swapped) + b'\n'
    letters = [i for i, row in enumerate(rows) if any(c in row for c in b'abcdef')]
    upper = list(rows)
    if letters:
        upper[letters[0]] = upper[letters[0]].upper()
    out['uppercase_hex'] = header + b'\n' + b'\n'.join(upper) + b'\n'
    zeros = list(rows)
    zeros[0] = b'0' + zeros[0]
    out['leading_zero'] = header + b'\n' + b'\n'.join(zeros) + b'\n'
    out['blank_line'] = header + b'\n\n' + b'\n'.join(rows) + b'\n'
    out['comment_line'] = b'# note\n' + header + b'\n' + b'\n'.join(rows) + b'\n'
    out['crlf'] = raw.replace(b'\n', b'\r\n')
    out['trailing_space'] = raw.replace(b'\n', b' \n', 1)
    out['tab_separator'] = header + b'\n' + rows[0].replace(b' ', b'\t', 1) + b'\n' + b'\n'.join(rows[1:]) + b'\n'
    out['no_final_newline'] = raw[:-1]
    out['extra_blank_at_end'] = raw + b'\n'
    out['junk_row'] = header + b'\n' + b'\n'.join([rows[0], b'zz 1 1', *rows[1:]]) + b'\n'
    out['four_words'] = header + b'\n' + b'\n'.join([rows[0] + b' 1', *rows[1:]]) + b'\n'
    out['r_prefix_in_mfw1'] = header + b'\n' + b'\n'.join([b'R ' + rows[0], *rows[1:]]) + b'\n'
    out['empty_file'] = b''
    out['comments_only'] = b'# nothing here\n\n'
    return out


def orientations(shape, terms):
    a = alg.Alg(*shape, list(terms))
    rows = {'cyclic_shift': alg.cyclic_shift(a), 'transpose': alg.transpose(a)}
    for perm in alg.ORIENT_PERMS:
        rows['perm' + ''.join(map(str, perm))] = alg.orient_by_perm(a, perm)
    target = tuple(sorted(shape))
    found = alg.orient_as(a, target)
    rows['orient_as_sorted'] = found
    rows['orient_as_impossible'] = alg.orient_as(a, (shape[0] + 1, shape[1], shape[2]))
    out = {}
    for name, result in rows.items():
        if result is None:
            out[name] = ('none', '-')
        else:
            out[name] = ('x'.join(map(str, result.shape)), hashlib.sha256(blob(result.shape, result.terms)).hexdigest())
    return out


def dropped(x, table):
    """mmc_gf2_alg.project's `rm`: bits whose table entry is negative are dropped (OR, not sum: targets may collide)."""
    y = 0
    for b in alg.bits(x):
        if table[b] >= 0:
            y |= 1 << table[b]
    return y


def bits_vectors():
    rng = random.Random(9)
    masks = [0, 1, 2, 3, 5, (1 << 47) - 1, 1 << 47, (1 << 48) + 1, (1 << 62) | 1, (1 << 63) - 1, 1 << 63,
             (1 << 63) + 1, (1 << 64) - 1, 1 << 64, (1 << 64) + 5, (1 << 127) | 1, (1 << 128) - 1, 1 << 128,
             (1 << 200) | (1 << 64) | 3, (1 << 1023) | 1, (1 << 1024) - 1, 1 << 1023]
    for width in (7, 31, 46, 47, 48, 60, 63, 64, 65, 100, 129, 192, 255, 256, 257, 511, 512, 1000, 1024):
        for _ in range(3):
            masks.append(rng.getrandbits(width))
        density = rng.random()
        masks.append(sum(1 << b for b in range(width) if rng.random() < density))
    rows = []
    for x in masks:
        cols = 8
        rws = max(1, (x.bit_length() + cols - 1) // cols)
        table = [(b * 7 + 3) % 1500 for b in range(max(1, x.bit_length()))]
        dropping = [-1 if b % 5 == 0 else (b * 3 + 1) % 900 for b in range(max(1, x.bit_length()))]
        rows.append((f'{x:x}', alg.popcount(x), (x & -x).bit_length() - 1, x.bit_length() - 1, rws, cols,
                     f'{alg.remap(x, alg._ttab(rws, cols)):x}' if x else '0',
                     f'{alg.remap(x, table):x}' if x else '0',
                     ','.join(map(str, alg.bits(x))) or '-',
                     f'{dropped(x, dropping):x}'))
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--corpus', required=True)
    args = parser.parse_args()
    (HERE / 'mutants').mkdir(exist_ok=True)
    cases = []
    orient_rows = []
    for name, (source, shape) in BASES.items():
        terms = sorted(base_terms(source, args.corpus))
        exact(shape, terms)
        path = HERE / f'{name}.mfw'
        path.write_bytes(blob(shape, terms))
        cases.append((path, shape, 'base'))
        for kind, (label, result) in orientations(shape, terms).items():
            orient_rows.append((name, kind, label, result))
        if name in MUTATED + BIG_MUTATED:
            for kind, text in mutants(shape, terms).items():
                if name in BIG_MUTATED and kind not in ('bit_flip_u', 'dropped_term', 'crlf'):
                    continue
                target = HERE / 'mutants' / f'{name}__{kind}.mfw'
                target.write_bytes(text)
                cases.append((target, shape, kind))
    # The shape can also come from the directory the certificate lives in.
    (HERE / 'shape_dir/2x2x2').mkdir(parents=True, exist_ok=True)
    (HERE / 'shape_dir/2x2x2/certificate.mfw').write_bytes((HERE / 'strassen_2x2x2.mfw').read_bytes())
    # Legacy formats of the same tensors.
    small = sorted(seed_terms('matmul_3x3_rank23_d139_gf2.txt'))
    (HERE / '3x3x3_rank23_checkpoint.txt').write_text(
        f'{len(small)}\n' + ''.join(' '.join(map(str, t)) + '\n' for t in seed_terms('matmul_3x3_rank23_d139_gf2.txt')))
    cases.append((HERE / '3x3x3_rank23_checkpoint.txt', (3, 3, 3), 'checkpoint'))
    (HERE / 'strassen_2x2x2_R.txt').write_text(
        ''.join('R ' + ' '.join(map(str, t)) + '\n' for t in seed_terms('matmul_2x2_rank7_d36_gl120_gf2.txt')))
    cases.append((HERE / 'strassen_2x2x2_R.txt', (2, 2, 2), 'r_rows'))
    wide = sorted(base_terms(BASES['wide68_2x4x17'][0], args.corpus))
    (HERE / 'wide68_2x4x17_R.txt').write_text(''.join('R ' + ' '.join(map(str, t)) + '\n' for t in wide))
    cases.append((HERE / 'wide68_2x4x17_R.txt', (2, 4, 17), 'r_rows_wide'))
    (HERE / 'wide68_2x4x17_checkpoint.txt').write_text(f'{len(wide)}\n' + ''.join(' '.join(map(str, t)) + '\n' for t in wide))
    cases.append((HERE / 'wide68_2x4x17_checkpoint.txt', (2, 4, 17), 'checkpoint_wide'))
    (HERE / 'strassen_2x2x2_commented.txt').write_text(
        '# Strassen, with a comment, blank lines and CRLF-free padding\n\n   7   \n' +
        ''.join('  ' + ' '.join(map(str, t)) + '  \n\n' for t in seed_terms('matmul_2x2_rank7_strassen_gf2.txt')))
    cases.append((HERE / 'strassen_2x2x2_commented.txt', (2, 2, 2), 'commented_checkpoint'))

    with open(HERE / 'cases.tsv', 'w') as out:
        out.write('# file\tshape\tkind\truby_status\tpython_status\truby_message_or_rank_density_sha256\n')
        for path, shape, kind in cases:
            status, message = ruby(path, shape)
            out.write('\t'.join([str(path.relative_to(HERE)), 'x'.join(map(str, shape)), kind, str(status),
                                 str(python(path, shape)), message]) + '\n')
    with open(HERE / 'bits.tsv', 'w') as out:
        out.write('# hex\tpopcount\tlow_bit\thigh_bit\trows\tcols\ttransposed_hex\tremapped_hex\tpositions\tremapped_dropping_hex\n')
        for row in bits_vectors():
            out.write('\t'.join(map(str, row)) + '\n')
    with open(HERE / 'orient.tsv', 'w') as out:
        out.write('# base\tmove\tshape\tsha256_of_blob\n')
        for row in orient_rows:
            out.write('\t'.join(row) + '\n')
    with open(HERE / 'naive.tsv', 'w') as out:
        out.write('# shape\trank\tdensity\tsha256_of_blob\n')
        for shape in ((2, 2, 2), (2, 3, 4), (3, 1, 5), (1, 32, 32), (2, 32, 16), (1, 8, 8), (1, 9, 7), (1, 13, 5), (2, 8, 8), (8, 8, 1), (7, 9, 1), (3, 3, 7)):
            a = alg.naive(*shape)
            density = sum(alg.popcount(u) + alg.popcount(v) + alg.popcount(w) for u, v, w in a.terms)
            out.write('\t'.join(['x'.join(map(str, shape)), str(a.r), str(density),
                                 hashlib.sha256(blob(shape, a.terms)).hexdigest()]) + '\n')
    with open(HERE / 'orient_to.tsv', 'w') as out:
        out.write('# base\ttarget\tsha256_of_blob\n')
        for name, (source, shape) in BASES.items():
            terms = sorted(base_terms(source, args.corpus))
            seen = set()
            for perm in __import__('itertools').permutations(range(3)):
                target = tuple(shape[i] for i in perm)
                if target in seen:
                    continue
                seen.add(target)
                out.write('\t'.join([name, 'x'.join(map(str, target)),
                                     hashlib.sha256(blob(target, orient(shape, terms, target))).hexdigest()]) + '\n')
    original = sorted(base_terms(BASES['rank23_3x3x3'][0], args.corpus))
    dirty = list(original) + [original[2], (0, original[1][1], original[1][2]), original[5], original[5],
                              original[5], original[2], (original[3][0], 0, original[3][2]), original[9], original[9]]
    dirty.insert(4, original[7])
    with open(HERE / 'clean.tsv', 'w') as out:
        out.write('# in|out\tu\tv\tw  (3x3x3, hex): the input terms in order, then mmc_gf2_alg.clean of them in order\n')
        for u, v, w in dirty:
            out.write(f'in\t{u:x}\t{v:x}\t{w:x}\n')
        for u, v, w in alg.clean(alg.Alg(3, 3, 3, dirty)).terms:
            out.write(f'out\t{u:x}\t{v:x}\t{w:x}\n')
    defects = 0
    with open(HERE / 'defects.tsv', 'w') as out:
        out.write('# file\ta\tb\texpected_hex\tactual_hex\n')
        for path, shape, kind in cases:
            status, message = ruby(path, shape)
            if status == 0 or not message.startswith('inexact GF(2) tensor at coefficients '):
                continue
            try:
                _, terms = read_blob(path.read_bytes())
            except Exception:  # duplicates and the like: no canonical terms to recompute from
                continue
            a_index, b_index = map(int, message.rsplit(' ', 1)[1].split(','))
            n, m, p = shape
            actual = 0
            for u, v, w in terms:
                if u >> a_index & 1 and v >> b_index & 1:
                    actual ^= w
            expected = 1 << (a_index // m * p + b_index % p) if a_index % m == b_index // p else 0
            out.write('\t'.join([str(path.relative_to(HERE)), str(a_index), str(b_index), f'{expected:x}', f'{actual:x}']) + '\n')
            defects += 1
    print(f'{len(cases)} fixtures, {len(orient_rows)} orientation rows, {defects} defect rows')


if __name__ == '__main__':
    main()
