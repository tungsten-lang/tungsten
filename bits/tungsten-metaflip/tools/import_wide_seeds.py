#!/usr/bin/env python3
"""Pinned, exact GF(2) imports for square seeds; no upstream code is executed.

Only MIT-licensed Perminov result files are imported. Catalog rank tables,
commutative algorithms and characteristic-zero-only schemes are not seeds.
Downloads remain in the user's cache; only compact MFW1 certificates ship.
"""
import argparse
from collections import Counter
import csv
from fractions import Fraction
import hashlib
import io
import json
from pathlib import Path
import re
from urllib.request import urlopen

COMMIT = 'db560ca5811bc38d5a6d5c0a3ec4315937ceabce'
REPO = 'https://github.com/dronperminov/FastMatrixMultiplication'
RAW = 'https://raw.githubusercontent.com/dronperminov/FastMatrixMultiplication/' + COMMIT + '/'
SOURCES = {
    'ZT/8x8x8_m343_ZT.json': '7bd55d1010443cf3acf51b6244f5ec09220e8edd',
    'addition_reduced_ZT/8x8x8_m343_cr1661_fv1015_cn4434_ZT_reduced.json': '81421204b5b597900bca8b34289ed2ce4a271664',
    'ZT/9x9x9_m486_ZT.json': 'ba73e1dfe493be5e308a3a728abeceab26ffb889',
    'ZT/10x10x10_m651_ZT.json': '87b2810a5f6674771e75df3be410524be668fdf1',
    'ZT/10x10x10_m686_ZT.json': 'b72e15761737314922a0a292c4fc8fca19cba0bb',
    'ZT/11x11x11_m873_ZT.json': '58606ce43d9135b309e60fb5fb3738690e30e043',
    'ZT/11x11x11_m960_ZT.json': '406ca1e14814ac6b75978e0399b0043b21b9fa82',
    'ZT/12x12x12_m1068_ZT.json': 'd027d3cd03d0a20e5f80659dd1708b4dd786e258',
    'ZT/12x12x12_m1071_ZT.json': 'eee721abea4964963fcc21d16dfa05562c790d60',
    'ZT/13x13x13_m1426_ZT.json': 'bea2062def2fac6a1ba7e73102cea288611079e3',
    'ZT/14x14x14_m1725_ZT.json': '97b4b09bb7f1e38968a4c06ae7982f5949be1475',
    'ZT/15x15x15_m2058_ZT.json': '45d0dd51109edd7907281dfba5f919eb7de666b0',
    'ZT/16x16x16_m2401_ZT.json': '6797c8fd2179236afa06e4a694becadb008cbfa1',
}


def parity(value):
    if type(value) is not int and not (isinstance(value, str) and re.fullmatch(r'-?\d+/[1-9]\d*', value)):
        raise ValueError('coefficient must be an exact integer or rational')
    value = Fraction(value)
    if value.denominator % 2 == 0:
        raise ValueError('even denominator: source does not reduce directly to GF(2)')
    return value.numerator & 1


def bit_indices(mask):
    while mask:
        bit = mask & -mask
        yield bit.bit_length() - 1
        mask ^= bit


def verify(n, terms):
    width = n*n
    tensor = [0] * (width*width)
    for u, v, w in terms:
        if not all(0 < factor < 1 << width for factor in (u, v, w)):
            raise ValueError('zero or out-of-bounds factor')
        for a in bit_indices(u):
            for b in bit_indices(v):
                tensor[a*width+b] ^= w
    for a in range(width):
        for b in range(width):
            expected = 1 << (a//n*n+b%n) if a%n == b//n else 0
            if tensor[a*width+b] != expected:
                raise ValueError(f'tensor mismatch at {a},{b}')


def circuit(data, name, count, width):
    basis = [1 << i for i in range(width)]
    def form(row):
        mask = 0
        if not isinstance(row, list):
            raise ValueError('malformed linear form')
        for item in row:
            if not isinstance(item, dict) or set(item) != {'index', 'value'}:
                raise ValueError('malformed circuit entry')
            index = item['index']
            if type(index) is not int or not 0 <= index < len(basis):
                raise ValueError('forward or out-of-range circuit reference')
            if parity(item['value']):
                mask ^= basis[index]
        return mask
    for row in data.get(name+'_fresh', []):
        basis.append(form(row))
    if len(data[name]) != count:
        raise ValueError('wrong circuit row count')
    return [form(row) for row in data[name]]


def decode(data):
    dims = data.get('n')
    if not isinstance(dims, list) or len(dims) != 3 or any(type(n) is not int for n in dims) or len(set(dims)) != 1 or not 8 <= dims[0] <= 16:
        raise ValueError('expected an 8..16 square tensor')
    if data.get('commutative') or data.get('scheme_type') == 'non_bilinear':
        raise ValueError('not a bilinear scheme')
    n, rank = dims[0], data.get('m')
    if type(rank) is not int or not 1 <= rank <= n**3:
        raise ValueError('invalid rank')
    width = n*n
    if any(name+'_fresh' in data for name in ('u', 'v', 'w')):
        u = circuit(data, 'u', rank, width)
        v = circuit(data, 'v', rank, width)
        outputs = circuit(data, 'w', width, rank)
        w = [sum(((output >> k) & 1) << i for i, output in enumerate(outputs)) for k in range(rank)]
    else:
        banks = []
        for name in ('u', 'v', 'w'):
            rows = data.get(name)
            if not isinstance(rows, list) or len(rows) != rank:
                raise ValueError('wrong factor row count')
            masks = []
            for row in rows:
                if not isinstance(row, list) or len(row) != width:
                    raise ValueError('wrong factor width')
                masks.append(sum(parity(value) << i for i, value in enumerate(row)))
            banks.append(masks)
        u, v, w = banks
    # Upstream W uses C[k,i]; MFW1 uses C[i,k]. Cancel identical GF(2) terms.
    terms = Counter((a, b, sum(1 << (i%n*n+i//n) for i in bit_indices(c))) for a, b, c in zip(u, v, w))
    terms = sorted(term for term, count in terms.items() if count % 2 and all(term))
    verify(n, terms)
    return n, rank, terms


def blob(n, terms):
    return (f'MFW1 {n} {n} {n} {len(terms)}\n' + ''.join(' '.join(f'{v:x}' for v in term)+'\n' for term in terms)).encode()


def run(cache, runtime):
    rows, outputs, seen = [], {}, set()
    for source, git_hash in SOURCES.items():
        path = 'schemes/results/' + source
        cached = cache / COMMIT / path
        if not cached.exists():
            with urlopen(RAW + path, timeout=45) as response:
                raw = response.read(16_000_001)
            if len(raw) > 16_000_000:
                raise ValueError('oversized upstream source')
            cached.parent.mkdir(parents=True, exist_ok=True)
            cached.write_bytes(raw)
        raw = cached.read_bytes()
        if hashlib.sha1(b'blob '+str(len(raw)).encode()+b'\0'+raw).hexdigest() != git_hash:
            raise ValueError('upstream git-blob hash mismatch: ' + path)
        n, source_rank, terms = decode(json.loads(raw))
        body = blob(n, terms)
        digest = hashlib.sha256(body).hexdigest()
        if digest in seen:
            print('DUPLICATE', path, flush=True)
            continue
        seen.add(digest)
        rel = f'seeds/gf2/wide/matmul_{n}x{n}_rank{len(terms)}_{git_hash[:10]}_perminov_gf2.mfw'
        outputs[rel] = body
        rows.append([n, len(terms), sum(bin(v).count('1') for term in terms for v in term), rel,
                     source_rank, COMMIT, path, git_hash, hashlib.sha256(raw).hexdigest(), digest,
                     'MIT', 'Andrew Perminov and cited algorithm authors'])
        print(f'EXACT {n}x{n}: rank {len(terms)}, {len(body)} bytes, {path}', flush=True)
    # All inputs pass before any runtime asset is published. This is an
    # offline, mechanical data generator; the search never fetches the network.
    for rel, body in outputs.items():
        target = runtime / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(body)
    out = io.StringIO()
    writer = csv.writer(out, delimiter='\t', lineterminator='\n')
    writer.writerow(['square', 'rank', 'density', 'runtime_path', 'upstream_rank', 'commit', 'source_path', 'git_blob_sha1', 'source_sha256', 'certificate_sha256', 'license', 'attribution'])
    writer.writerows(sorted(rows, key=lambda r: (r[0], r[1], r[2], r[3])))
    (runtime / 'manifests/wide-seeds.tsv').write_text(out.getvalue())
    print(f'RETAINED {len(outputs)} distinct tensors, {sum(map(len, outputs.values()))} bytes')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cache', type=Path, default=Path.home()/'.cache/metaflip/upstream')
    parser.add_argument('--runtime', type=Path, required=True)
    args = parser.parse_args()
    run(args.cache, args.runtime)
