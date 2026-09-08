#!/usr/bin/env python3
"""Replay rank-primary walks with up to eight read-only price observers.

Accepts rank-only controls as well as runs with observer sidecars. Checks
complete saved tensors, observer tables against a supplied frozen price
plan, scores, and accounting. The plan's leaves and reference/novelty claims
are NOT verified here; larger products still require full recipe replay.
"""
import argparse
from dataclasses import asdict
import hashlib
import json
from pathlib import Path
import tempfile

import verify_block_composition_records as tensor
from verify_parent_only_walk import pure_score
from verify_representation_portfolio import contained, parse_terms


def verify(root, price_plan):
    root, price_plan = Path(root).resolve(), Path(price_plan).resolve()
    raw = (root/'report.json').read_bytes()
    report = json.loads(raw)
    plan_raw = price_plan.read_bytes()
    plan = json.loads(plan_raw)
    for document in (report, plan):
        assert document['complete'] and document['field'] == 'GF(2)' and not document['record_claim']
    assert len(plan['model_shapes']) == len(plan['baseline_recipes'])
    prices = {tuple(s): row['rank'] for s, row in zip(plan['model_shapes'], plan['baseline_recipes'])}
    assert len(prices) == len(plan['model_shapes'])
    assert all(len(s) == 3 and tuple(sorted(s)) == s and all(type(d) is int and 1 <= d <= 32 for d in s)
               and type(rank) is int and rank > 0 for s, rank in prices.items())
    trials, chunks, steps, interval = (report[k] for k in ('trials', 'chunks', 'steps', 'observe_every'))
    assert all(type(x) is int and x > 0 for x in (trials, chunks, steps, interval)) and interval <= steps
    debt, density = report['debt'], report['density_slack']
    assert type(debt) is int and 0 <= debt <= 8
    assert type(density) is int and 0 <= density <= 1024
    cases, pins, rows, cells = {}, {}, [], set()

    def read(relative):
        path = contained(root, relative)
        body = path.read_bytes()
        digest = hashlib.sha256(body).hexdigest()
        assert relative not in pins or pins[relative] == digest
        pins[relative] = digest
        return body, digest

    def load(entry, shape, limit=None):
        assert entry['shape'] == list(shape)
        blob, digest = read(entry['path'])
        assert digest == entry['sha256']
        terms = parse_terms(blob, entry['rank'])
        assert len(terms) == len(set(terms)) == entry['rank']
        assert limit is None or len(terms) <= limit
        body = ''.join('R '+' '.join(map(str, t))+'\n' for t in terms).encode()
        cases[tuple(shape), hashlib.sha256(body).hexdigest()] = body
        return terms

    attempts = 0
    assert report['rows']
    for row in report['rows']:
        assert row['cell'] not in cells
        cells.add(row['cell'])
        shape = row['shape']
        assert len(shape) == 3 and all(type(d) is int and 1 <= d <= 32 for d in shape)
        source = load(row['source'], shape)
        blob, digest = read(row['prices']['path'])
        assert digest == row['prices']['sha256']
        lines = blob.decode('ascii').splitlines()
        limit, n = int(lines[0]), len(row['contexts'])
        assert len(source)+debt <= limit and 0 <= n <= 8
        if n:
            assert len(lines) == 5+3*n and lines[4] == f'observers {n}'
        else:
            # Four rows are the native rank-only format. A fifth row would
            # enable a different (grid) objective, which this replay excludes.
            assert len(lines) == 4
        assert all(list(map(int, line.split())) == list(range(limit+1)) for line in lines[1:4])
        for i, context in enumerate(row['contexts']):
            table = [list(map(int, line.split())) for line in lines[5+3*i:8+3*i]]
            assert table == context['prices']
            assert all(len(t) == limit+1 and t[0] == 0 and min(t[1:]) > 0 for t in table)
            scale = context['scale']
            assert len(scale) == 3 and all(type(d) is int and d > 0 for d in scale)
            assert sorted(d*k for d, k in zip(shape, scale)) == context['target']
            assert max(context['target']) <= 32
            for axis, free in enumerate((2, 0, 1)):
                costs = []
                for k in range(1, min(limit, 32//scale[free])+1):
                    leaf = scale.copy()
                    leaf[free] *= k
                    costs.append(prices[tuple(sorted(leaf))])
                for size in range(1, limit+1):
                    assert table[axis][size] == min(table[axis][size-j]+costs[j-1]
                                                  for j in range(1, min(size, len(costs))+1))
        totals = row['totals']
        assert totals['strategy'] == 'walk' and int(totals['held_terms']) == 0
        assert int(totals['density_slack']) == density
        assert int(totals['held_cost']) == int(totals['holdout_cancellations']) == 0
        assert int(totals['initial']) == len(source)
        assert all(int(totals[k]) == report[k] for k in ('trials', 'chunks', 'steps', 'observe_every'))
        if 'command' in row:
            # Historical paths can refer to the pre-retention directory. Pin
            # tensors separately, but do not silently accept different flags.
            command = row['command']
            assert len(command) == 13 and all(type(v) is str for v in command)
            assert command[2] == 'x'.join(map(str, shape))
            seed = report['rng_seed']
            assert type(seed) is int and 0 <= seed <= 2**31-1
            assert command[4:9] == [str(trials), str(chunks), str(steps), 'walk', str(seed)]
            assert command[10:] == [str(debt), str(density), str(interval)]
        expected = trials*chunks*steps
        assert int(totals['attempted']) == expected
        assert int(totals['observations']) == trials*chunks*((steps+interval-1)//interval)
        attempts += expected
        assert len(row['trials']) == trials
        for trial_id, trial in enumerate(row['trials']):
            assert trial['trial'] == trial_id
            primary = load(trial['winner'], shape, limit)
            load(trial['endpoint'], shape, limit)
            native = trial['native']
            assert int(native['trial']) == trial_id
            assert int(native['rank']) == int(native['score']) == len(primary)
            assert int(native['bits']) == sum(v.bit_count() for t in primary for v in t)
            assert len(trial['observers']) == len(trial['rank_winner_context_costs']) == n
            for i, observer in enumerate(trial['observers']):
                value = load(observer['winner'], shape, limit)
                native, table = observer['native'], row['contexts'][i]['prices']
                assert observer['observer'] == int(native['observer']) == i
                assert int(native['trial']) == trial_id and int(native['rank']) == len(value)
                assert int(native['score']) == pure_score(value, table)
                assert int(native['bits']) == sum(v.bit_count() for t in value for v in t)
                assert trial['rank_winner_context_costs'][i] == pure_score(primary, table)
        assert len(row['summary']) == n
        for i, summary in enumerate(row['summary']):
            context = row['contexts'][i]
            observed = min(int(t['observers'][i]['native']['score']) for t in row['trials'])
            control = min(t['rank_winner_context_costs'][i] for t in row['trials'])
            assert summary['target'] == context['target'] and summary['reference'] == context['reference']
            assert summary['initial'] == pure_score(source, context['prices'])
            assert summary['rank_observer'] == control and summary['context_observer'] == observed <= control
            assert summary['below_reference'] == (observed < summary['reference'])
            rows.append(dict(summary, shape=shape, cell=row['cell'], observer=i))
    assert attempts == report['attempts']
    checked = []
    with tempfile.TemporaryDirectory(prefix='metaflip-observer-audit-') as directory:
        tmp = Path(directory)
        for i, ((shape, digest), body) in enumerate(cases.items()):
            name = f'{i}.txt'
            (tmp/name).write_bytes(body)
            record = tensor.Record('x'.join(map(str, shape)), shape, len(body.splitlines()), name, digest)
            checked.append(asdict(tensor._verify_one((tmp, record))))
    assert (root/'report.json').read_bytes() == raw and price_plan.read_bytes() == plan_raw
    assert all(hashlib.sha256(contained(root, p).read_bytes()).hexdigest() == d for p, d in pins.items())
    return dict(complete=True, field='GF(2)', record_claim=False, products_materialized=False,
                references_revalidated=False, price_plan_leaves_reverified=False,
                report_sha256=hashlib.sha256(raw).hexdigest(), source_sha256=pins,
                price_plan_path=str(price_plan), price_plan_sha256=hashlib.sha256(plan_raw).hexdigest(),
                attempts=attempts, cells=len(cells), rows=rows, results=checked, tensors=len(checked),
                terms=sum(c['terms'] for c in checked), pair_xors=sum(c['pair_xors'] for c in checked),
                observer_better_rows=sum(r['context_observer'] < r['rank_observer'] for r in rows))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--price-plan', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        parser.error('output must not exist')
    result = verify(args.root, args.price_plan)
    with args.output.open('x') as stream:
        stream.write(json.dumps(result, indent=2)+'\n')
    print(json.dumps({k: v for k, v in result.items() if k not in ('source_sha256', 'rows', 'results')}))
