#!/usr/bin/env python3
"""Replay projection-filter evidence, not a rank or UNSAT-proof oracle.

Bit-expanded clipping and basis actions are independent of the Ruby clipping
model. Random production-context comparisons are finite tests. SMT replay
remains solver evidence: this checker does not check a solver proof object.
"""
from __future__ import annotations

import argparse
from concurrent.futures import ProcessPoolExecutor
from dataclasses import asdict
import functools
import gzip
import hashlib
import importlib.util
import itertools
import json
import math
import multiprocessing
from pathlib import Path
import subprocess
import sys
import tempfile

from verify_representation_portfolio import apply_word, contained, identity, parse_terms

EDGES = ((0, 1), (1, 2), (0, 2))


def read_json(path):
    return json.loads(path.read_text())


def load(root, entry):
    raw = contained(root, entry['path']).read_bytes()
    assert hashlib.sha256(raw).hexdigest() == entry['sha256']
    lines = [s.strip() for s in raw.decode().splitlines() if s.strip() and not s.lstrip().startswith('#')]
    rank = int(lines[0]) if lines[0].isdigit() else len(lines)
    return tuple(entry['shape']), parse_terms(raw, rank)


def bits(value):
    assert isinstance(value, int) and value >= 0
    while value:
        low = value & -value
        yield low.bit_length() - 1
        value ^= low


def embed(value, outer, parent_cols, row_alloc, col_alloc, local_cols):
    rows = [sum(row_alloc[:i]) for i in range(len(row_alloc))]
    cols = [sum(col_alloc[:j]) for j in range(len(col_alloc))]
    result = 0
    for block in bits(outer):
        i, j = divmod(block, parent_cols)
        for position in bits(value):
            r, c = divmod(position, local_cols)
            if r < row_alloc[i] and c < col_alloc[j]:
                result ^= 1 << ((rows[i] + r) * sum(col_alloc) + cols[j] + c)
    return result


def clipped_zero_count(parent_shape, outer, allocation, shape, terms):
    cache = [{} for _ in EDGES]
    zeros = 0
    for term in terms:
        dead = False
        for edge, (row, col) in enumerate(EDGES):
            value = term[edge]
            if value not in cache[edge]:
                cache[edge][value] = embed(value, outer[edge], parent_shape[col],
                    allocation[row], allocation[col], shape[col]) == 0
            dead |= cache[edge][value]
        zeros += dead
    return zeros


def evaluate(conditions, assignment):
    return sum(any(all(assignment[axis, side] == value for axis, side, value in clause)
                   for clause in disjunction) for disjunction in conditions)


def check_sample(parent_shape, outer, allocation, shape, terms, axes, conditions, sample):
    assignment = {(a, side): value for a, side, value in sample['assignment']}
    assert set(assignment) == {(a, side) for a in axes for side in ('u', 'v')}
    for axis in axes:
        u, v = assignment[axis, 'u'], assignment[axis, 'v']
        assert 0 < u < 2 ** shape[axis] and 0 < v < 2 ** shape[axis]
        assert (u & v).bit_count() % 2 == 1
    changed = apply_word(shape, terms, sample['word'])
    direct = clipped_zero_count(parent_shape, outer, allocation, shape, changed)
    assert direct == evaluate(conditions, assignment) == sample['zeros']
    return direct


def library_prices(root):
    seeds = {}
    for path in (root / 'threeway/basis').glob('*.txt'):
        shape = tuple(sorted(map(int, path.name.split('-')[0].split('x'))))
        lines = [s.strip() for s in path.read_text().splitlines() if s.strip() and not s.lstrip().startswith('#')]
        rank = int(lines[0]) if lines[0].isdigit() else len(lines)
        seeds[shape] = min(seeds.get(shape, rank), rank)

    def price(shape):
        return cost(tuple(sorted(shape)))

    @functools.cache
    def cost(shape):
        result = min(math.prod(shape), seeds.get(shape, math.prod(shape)))
        if 1 not in shape:
            for axis, extent in enumerate(shape):
                for cut in range(1, extent // 2 + 1):
                    left, right = list(shape), list(shape)
                    left[axis], right[axis] = cut, extent - cut
                    result = min(result, price(left) + price(right))
            divisors = [[d for d in range(1, n + 1) if n % d == 0] for n in shape]
            for left in itertools.product(*divisors):
                right = tuple(n // d for n, d in zip(shape, left))
                if (1, 1, 1) not in (left, right) and left <= right:
                    result = min(result, price(left) * price(right))
        return result
    return price


def formula(parent_shape, terms, allocation, price):
    total = 0
    for term in terms:
        local = []
        for axis in range(3):
            incident = []
            for edge, (r, c) in enumerate(EDGES):
                if axis in (r, c):
                    support = [divmod(b, parent_shape[c])[0 if axis == r else 1] for b in bits(term[edge])]
                    incident.append(max((allocation[axis][i] for i in support), default=0))
            local.append(min(incident))
        if 0 not in local:
            total += price(local)
    return total


def replay_solver(root, executable):
    # Replay both the saved SMT2 and a fresh formula rebuilt from the retained
    # conditions. Agreement here is still Z3 evidence, not an UNSAT certificate.
    import z3
    results = []
    for input_name, folder in [('sat-input.json', 'sat'), ('alternative-inputs/input.json', 'alternative-sat')]:
        source = root / input_name
        cases = read_json(source)['cases']
        report = read_json(root / folder / 'report.json')
        assert report['complete'] and hashlib.sha256(source.read_bytes()).hexdigest() == report['input_sha256']
        rows = {r['name']: r for r in report['rows']}
        assert len(rows) == len(cases)
        for case in cases:
            name = case.get('name', 'x'.join(map(str, case['target'])) + '-' + str(case['slot']))
            row = rows.pop(name)
            checks = row.get('checks', [row])
            assert len(checks) == 1 and checks[0]['result'] == 'unsat'
            query = contained(root / folder, checks[0]['query'])
            response = subprocess.run([str(executable), '-T:30', str(query)], capture_output=True,
                                      text=True, check=True, timeout=35).stdout.strip()
            assert response == 'unsat', (query, response)
            variables = {(axis, side): z3.BitVec(f'{side}{axis}', case['shape'][axis])
                         for axis in case['axes'] for side in ('u', 'v')}
            solver = z3.Solver()
            solver.set(timeout=30000)
            for axis in case['axes']:
                product = variables[axis, 'u'] & variables[axis, 'v']
                parity = z3.BitVecVal(0, 1)
                for bit in range(case['shape'][axis]):
                    parity = parity ^ z3.Extract(bit, bit, product)
                solver.add(parity == 1)
            terms = []
            for disjunction in case['conditions']:
                condition = z3.Or(*[z3.And(*[variables[a, s] == value for a, s, value in clause])
                                    for clause in disjunction])
                terms.append(z3.If(condition, 1, 0))
            threshold = case['required_zero'] if 'required_zero' in case else case['baseline_zero'] + 1
            assert threshold == (row['required_zero'] if 'required_zero' in row else checks[0]['bound'])
            solver.add(z3.Sum(terms) >= threshold)
            status = str(solver.check())
            assert status == 'unsat', (name, status)
            results.append(dict(name=name, kind=folder, saved=response, rebuilt=status))
        assert not rows
        print(json.dumps(dict(solver_replayed=len(results))), flush=True)
    return results


def verify(root, workers=2, z3_executable=Path('/opt/homebrew/bin/z3')):
    root = root.resolve()
    manifest = read_json(root / 'report.json')
    assert manifest['complete'] and manifest['field'] == 'GF(2)' and not manifest['record_claim']
    for name, digest in manifest['retained_files'].items():
        assert hashlib.sha256(contained(root, name).read_bytes()).hexdigest() == digest, name
    raw = gzip.decompress((root / 'single.json.gz').read_bytes())
    assert hashlib.sha256(raw).hexdigest() == manifest['single_uncompressed_sha256']
    assert len(json.loads(raw)['rows']) == manifest['single_axes']
    assert len(read_json(root / 'double/report.json')['rows']) == manifest['double_axes']
    contexts = read_json(root / 'contexts.json')['contexts']
    assert len(contexts) == manifest['contexts']
    samples = 0
    for context in contexts:
        parent_shape, parent = load(root, context['parent'])
        shape, terms = load(root, context['leaf'])
        outer = parent[context['slot']]
        direct = clipped_zero_count(parent_shape, outer, context['allocation'], shape, terms)
        for row in context.get('single', []) + context.get('double', []):
            assert direct == row['baseline_zero'] == row['maximum_zero']
        for sample in context['samples']:
            check_sample(parent_shape, outer, context['allocation'], shape, terms,
                         context['axes'], context['conditions'], sample)
            samples += 1
        if context['origin'] == 'alternative':
            original_shape, original = load(root, context['original_leaf'])
            before = clipped_zero_count(parent_shape, outer, context['allocation'], original_shape, original)
            assert before == context['original_leaf_zero']
            assert context['required_zero'] == max(len(terms) - len(original) + before + context['original_parity'] + 1, 0)
    assert samples == manifest['samples']
    print(json.dumps(dict(contexts=len(contexts), samples=samples)), flush=True)
    price = library_prices(root)
    history_count = 0
    descent = read_json(root / 'threeway-descent/report.json')
    assert descent['complete']
    for row in descent['rows']:
        for run in row['runs']:
            shape, terms = load(root / 'threeway-descent', run['initial_parent'])
            for step in run['history']:
                if step['kind'] == 'basis':
                    assert identity(shape, terms) == step['from']
                    terms = apply_word(shape, terms, step['word'])
                    assert identity(shape, terms) == step['to']
                else:
                    assert step['kind'] == 'allocation' and identity(shape, terms) == step['parent']
                assert formula(shape, terms, step['allocation'], price) == step['formula']
                history_count += 1
            final_shape, final = load(root / 'threeway-descent', run['final_parent'])
            assert shape == final_shape and terms == final
            assert formula(shape, terms, run['allocation'], price) == run['formula'] <= run['initial']
        assert row['formula'] == min(r['formula'] for r in row['runs'])
    assert history_count == manifest['threeway_history_steps']
    solver = replay_solver(root, z3_executable)
    checker = root / 'tools/verify_block_composition_records.py'
    spec = importlib.util.spec_from_file_location('projection_tensor_checker', checker)
    tensor = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = tensor
    spec.loader.exec_module(tensor)
    records = []
    with tempfile.TemporaryDirectory(prefix='metaflip-projection-check-') as temporary:
        temporary = Path(temporary)
        for index, case in enumerate(manifest['cases']):
            raw = contained(root, case['path']).read_bytes()
            assert hashlib.sha256(raw).hexdigest() == case['sha256']
            terms = parse_terms(raw, case['rank'])
            assert sum(v.bit_count() for t in terms for v in t) == case['density']
            body = ''.join('R ' + ' '.join(map(str, t)) + '\n' for t in terms).encode()
            name = f'{index}.txt'
            (temporary / name).write_bytes(body)
            records.append((temporary, tensor.Record('x'.join(map(str, case['shape'])),
                tuple(case['shape']), case['rank'], name, hashlib.sha256(body).hexdigest())))
        if workers == 1:
            results = list(map(tensor._verify_one, records))
        else:
            with ProcessPoolExecutor(max_workers=workers, mp_context=multiprocessing.get_context('fork')) as pool:
                results = list(pool.map(tensor._verify_one, records))
    return dict(schema=1, complete=True, field='GF(2)', record_claim=False, contexts=len(contexts),
        projection_samples=samples, independent_history_steps=history_count,
        solver_queries=len(solver), solver_proof_checked=False, solver=solver,
        cases=len(results), terms=sum(r.terms for r in results), pair_xors=sum(r.pair_xors for r in results),
        results=[asdict(r) for r in results])


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', required=True, type=Path)
    parser.add_argument('--workers', type=int, choices=range(1, 5), default=2)
    parser.add_argument('--z3', type=Path, default=Path('/opt/homebrew/bin/z3'))
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    result = verify(args.root, args.workers, args.z3)
    if args.report:
        args.report.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({k: v for k, v in result.items() if k not in ('results', 'solver')}))
