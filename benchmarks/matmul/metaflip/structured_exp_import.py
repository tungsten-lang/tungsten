#!/usr/bin/env python3
"""Exact, offline integer .exp -> GF(2) import with explicit shape/provenance.

Source variables are a_ij, b_jk, c_ki (trace order). Filenames need not give
the stored orientation. Coordinates are one-digit, coefficients are integers,
and source text is never evaluated. This does not admit seeds to a live fleet
or establish redistribution rights, novelty, or a rank lower bound.
"""
from __future__ import annotations

import argparse
from collections import Counter
from dataclasses import asdict
import hashlib
import json
from pathlib import Path
import re
import tempfile

import verify_block_composition_records as tensor
from verify_composition_recipes import orient

ROW = re.compile(r"\(([^()]*)\)\*\(([^()]*)\)\*\(([^()]*)\)")
ATOM = re.compile(r"([+-]?)(?:([0-9]+)\*?)?([abc])([1-9])([1-9])")


def parse_integer_exp(raw: bytes):
    terms = []
    for line_number, line in enumerate(raw.decode('ascii').splitlines(), 1):
        line = ''.join(line.split())
        if not line:
            continue
        match = ROW.fullmatch(line)
        if match is None:
            raise ValueError(f'line {line_number}: expected three parenthesized linear forms')
        factors = []
        for letter, form in zip('abc', match.groups()):
            position, coefficients = 0, Counter()
            for atom in ATOM.finditer(form):
                sign, magnitude, variable, row, col = atom.groups()
                if atom.start() != position or (position and not sign) or variable != letter:
                    raise ValueError(f'line {line_number}: invalid {letter} form')
                position = atom.end()
                value = int(magnitude or '1') * (-1 if sign == '-' else 1)
                coefficients[int(row)-1, int(col)-1] += value
            coefficients = {ij: c for ij, c in coefficients.items() if c}
            if position != len(form) or not coefficients:
                raise ValueError(f'line {line_number}: malformed or zero {letter} form')
            factors.append(coefficients)
        terms.append(tuple(factors))
    if not terms:
        raise ValueError('empty expression source')
    return terms


def checked_projection(raw: bytes, shape):
    shape = tuple(shape)
    if len(shape) != 3 or any(type(d) is not int or not 1 <= d <= 9 for d in shape):
        raise ValueError('expected three dimensions in 1..9')
    signed = parse_integer_exp(raw)
    dimensions = [tuple(max(ij[d] for term in signed for ij in term[a])+1
                        for d in range(2)) for a in range(3)]
    n, m = dimensions[0]
    p = dimensions[1][1]
    source_shape = (n, m, p)
    if dimensions != [(n, m), (m, p), (p, n)]:
        raise ValueError('inconsistent trace-coordinate matrix dimensions')
    if sorted(source_shape) != sorted(shape):
        raise ValueError(f'source shape {source_shape} is not a permutation of {shape}')
    integer, parity = Counter(), Counter()
    for term in signed:
        # Only the dual c factor is transposed into output row-major storage.
        factors = [{(j*p+i if a == 2 else i*dimensions[a][1]+j): c
                    for (i, j), c in factor.items()} for a, factor in enumerate(term)]
        for i, a in factors[0].items():
            for j, b in factors[1].items():
                for k, c in factors[2].items():
                    integer[i, j, k] += a*b*c
        masks = tuple(sum(1 << i for i, c in factor.items() if c % 2) for factor in factors)
        if all(masks):
            parity[masks] += 1
    expected = {(i*m+j, j*p+k, i*p+k): 1
                for i in range(n) for j in range(m) for k in range(p)}
    if {key: value for key, value in integer.items() if value} != expected:
        raise ValueError('complete integer tensor mismatch; GF(2) validity alone is insufficient')
    terms = orient([t for t, count in parity.items() if count % 2], source_shape, shape)
    # Independent sparse-parity reconstruction checks the converted orientation.
    body = ''.join('R '+' '.join(map(str, t))+'\n' for t in terms).encode()
    with tempfile.TemporaryDirectory(prefix='metaflip-exp-verify-') as directory:
        path = Path(directory)
        (path/'tensor.txt').write_bytes(body)
        record = tensor.Record('x'.join(map(str, shape)), shape, len(terms),
                               'tensor.txt', hashlib.sha256(body).hexdigest())
        verification = asdict(tensor._verify_one((path, record)))
    return dict(shape=list(shape), source_shape=list(source_shape), terms=terms,
                integer_terms=len(signed), rank=len(terms), integer_tensor_verified=True,
                gf2_tensor_verified=True, verification=verification)


def import_file(source, shape, expected_sha256, output, source_url=None):
    source, output = Path(source), Path(output)
    if output.exists():
        raise ValueError('output directory must not exist')
    raw = source.read_bytes()
    digest = hashlib.sha256(raw).hexdigest()
    if digest != expected_sha256:
        raise ValueError('source SHA-256 mismatch')
    checked = checked_projection(raw, shape)
    terms = checked.pop('terms')
    certificate = (str(len(terms))+'\n'+''.join(' '.join(map(str, t))+'\n' for t in terms)).encode()
    report = dict(schema=1, complete=True, field='GF(2)', record_claim=False,
                  imported_not_discovered=True, canonical_archive_changed=False,
                  redistribution_cleared=False, source_path=str(source.resolve()),
                  source_url=source_url, source_sha256=digest, source_snapshot='source.exp',
                  path='tensor.txt', sha256=hashlib.sha256(certificate).hexdigest(), **checked)
    report['tool_sha256'] = {name: hashlib.sha256(Path(__file__).with_name(name).read_bytes()).hexdigest()
                            for name in ('structured_exp_import.py', 'verify_composition_recipes.py',
                                         'verify_block_composition_records.py')}
    output.mkdir(parents=True)
    (output/'source.exp').write_bytes(raw)
    (output/'tensor.txt').write_bytes(certificate)
    (output/'report.json').write_text(json.dumps(report, indent=2)+'\n')
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--shape', required=True, help='requested output orientation, e.g. 2x3x4')
    parser.add_argument('--sha256', required=True, help='expected source SHA-256')
    parser.add_argument('--source-url', help='provenance only; never fetched')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    try:
        shape = tuple(map(int, args.shape.split('x')))
        report = import_file(args.source, shape, args.sha256, args.output, args.source_url)
    except (ValueError, OSError) as error:
        parser.error(str(error))
    print(json.dumps(report))


if __name__ == '__main__':
    main()
