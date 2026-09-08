#!/usr/bin/env python3
"""Reuse independently checked intermediate tensors and walk endpoints as parents.

The prior plan/parent corpus must already have a verified constructive ancestry.
This tool binds each added tensor to the full tensor check in its source audit;
equal ranks or bucket signatures never merge search states. Its output is an
arithmetic screen, not admission of newly implied larger tensors or a record
claim. Materialize and independently verify any selected result separately.
"""
import argparse
from collections import Counter
import copy
import hashlib
import json
from pathlib import Path
import re
import time

from composition_impact import CompositionImpact
from composition_expression_cover import ordinary_expression_cover
from verify_representation_portfolio import contained, parse_terms


def identity(shape, terms):
    body = 'x'.join(map(str, shape)) + '\n' + ''.join(
        ' '.join(map(str, t)) + '\n' for t in sorted(terms))
    return hashlib.sha256(body.encode()).hexdigest()


def json_digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def pricing_certificate(parents, report, engine_sha256):
    """Bind a completed planner run to its literal corpus and ordered table."""
    fields = ('maximum', 'model_shapes', 'baseline_recipes', 'bud_expressions', 'mixed_bud_expressions')
    return dict(version=1, engine_sha256=engine_sha256, parents_sha256=json_digest(parents),
                table_sha256=json_digest({key: report[key] for key in fields}))


def extend(prior_inputs, prior_plan, product_roots, walk_roots, output, maximum=32,
           projection_roots=(), reuse_priced_expressions=True, observer_walk_roots=()):
    if type(maximum) is not int or not 2 <= maximum <= 32:
        raise ValueError('invalid maximum')
    output = Path(output).resolve()
    if output.exists():
        raise ValueError('output must not exist')
    pins = {}

    def blob(path):
        path = Path(path).resolve()
        raw = path.read_bytes()
        digest = hashlib.sha256(raw).hexdigest()
        if str(path) in pins and pins[str(path)] != digest:
            raise ValueError('input changed while reading')
        pins[str(path)] = digest
        return raw

    def read(path):
        return json.loads(blob(path))

    def checked(report):
        if not report['complete'] or report['field'] != 'GF(2)' or report['record_claim']:
            raise ValueError('input is not a completed GF(2) audit/screen')

    old_inputs, old_plan = read(prior_inputs), read(prior_plan)
    checked(old_inputs)
    checked(old_plan)
    parents = copy.deepcopy(old_inputs['parents'])
    old_count = len(parents)
    seen = {p['identity']: i for i, p in enumerate(parents)}
    if len(seen) != len(parents):
        raise ValueError('prior corpus has duplicate literal identities')
    if len(old_plan['model_shapes']) != len(old_plan['baseline_recipes']):
        raise ValueError('prior plan shape/recipe mismatch')
    prices = {tuple(s): r['rank'] for s, r in zip(old_plan['model_shapes'], old_plan['baseline_recipes'])
              if max(s) <= maximum}
    output.mkdir()
    (output / 'parents').mkdir()
    admissions, added = [], Counter()

    def source(root, kind):
        root = Path(root).resolve()
        raw = blob(root / 'report.json')
        report, audit = json.loads(raw), read(root / 'independent-audit.json')
        checked(report)
        checked(audit)
        proofs = {}
        for row in audit['results']:
            shape = tuple(map(int, row['target'].split('x')))
            if len(shape) != 3 or any(not 1 <= d <= 32 for d in shape):
                raise ValueError('invalid audited shape')
            proofs[shape, row['sha256']] = row

        def admit(path, shape, digest):
            path = Path(path).resolve()
            relative = str(path.relative_to(root))
            body = blob(path)
            if hashlib.sha256(body).hexdigest() != digest or audit['source_sha256'][relative] != digest:
                raise ValueError('tensor bytes are not pinned by the independent audit')
            terms = parse_terms(body, int(body.splitlines()[0]))
            proof_body = ''.join('R ' + ' '.join(map(str, t)) + '\n' for t in terms).encode()
            proof = proofs.get((tuple(shape), hashlib.sha256(proof_body).hexdigest()))
            if (proof is None or proof['terms'] != len(terms) or proof['exact_rank'] != len(terms)
                    or len(set(terms)) != len(terms)):
                raise ValueError('missing full tensor proof for these bytes and this shape')
            key = identity(shape, terms)
            existing = key in seen
            signature = [sorted(Counter(t[a] for t in terms).values()) for a in range(3)]
            volume = shape[0] * shape[1] * shape[2]
            skip = ('outside_maximum' if max(shape) > maximum else
                    'non_decreasing_dependency' if any(max(a) >= volume for a in signature) else None)
            if not existing and skip is None:
                index = len(parents)
                name = 'x'.join(map(str, shape)) + '-' + digest + '.txt'
                snapshot = output / 'parents' / name
                snapshot.write_bytes(body)
                parents.append(dict(path=str(snapshot), shape=list(shape), sha256=digest, identity=key,
                    rank=len(terms), signature=signature,
                    mixed_partitions=[], provenance=kind))
                seen[key] = index
                added[kind] += 1
            admissions.append(dict(source_root=str(root), path=relative, sha256=digest,
                shape=list(shape), identity=key, parent=seen.get(key), duplicate=existing, kind=kind,
                skip=skip))

        if kind == 'composition_audit':
            if audit['report_sha256'] != hashlib.sha256(raw).hexdigest():
                raise ValueError('stale composition audit')
            for name, digest in audit['source_sha256'].items():
                path = contained(root, name)
                if hashlib.sha256(blob(path)).hexdigest() != digest:
                    raise ValueError('composition source changed')
                if name.endswith('.json'):
                    continue
                match = re.fullmatch(r'(\d+x\d+x\d+)-[0-9a-f]{64}\.txt', path.name)
                if not match:
                    raise ValueError('unsupported composition tensor filename')
                admit(path, list(map(int, match[1].split('x'))), digest)
        elif kind == 'projection_audit':
            if audit['report_sha256'] != hashlib.sha256(raw).hexdigest():
                raise ValueError('stale projection audit')
            if audit['outputs'] != len(report['outputs']):
                raise ValueError('projection audit accounting mismatch')
            for name, digest in audit['source_sha256'].items():
                if hashlib.sha256(blob(contained(root, name))).hexdigest() != digest:
                    raise ValueError('projection source changed')
            for row in report['outputs']:
                path = contained(root, row['path'])
                admit(path, row['shape'], row['sha256'])
        elif kind == 'observer_walk_audit':
            if audit['report_sha256'] != hashlib.sha256(raw).hexdigest():
                raise ValueError('stale observer walk audit')
            if audit['attempts'] != report['attempts'] or audit['cells'] != len(report['rows']):
                raise ValueError('observer walk audit accounting mismatch')
            for name, digest in audit['source_sha256'].items():
                if hashlib.sha256(blob(contained(root, name))).hexdigest() != digest:
                    raise ValueError('observer walk source changed')
            for row in report['rows']:
                entries = [row['source']]
                for trial in row['trials']:
                    entries.extend((trial['winner'], trial['endpoint']))
                    entries.extend(observer['winner'] for observer in trial['observers'])
                for entry in entries:
                    if entry['shape'] != row['shape']:
                        raise ValueError('observer walk tensor shape mismatch')
                    admit(contained(root, entry['path']), entry['shape'], entry['sha256'])
        else:
            if audit['attempts'] != report['total_attempts']:
                raise ValueError('walk audit accounting mismatch')
            for row in report['rows']:
                path = contained(root, row['report'])
                study = read(path)
                shape = study['parent']['shape']
                e = study['parent']
                admit(contained(path.parent, e['path']), shape, e['sha256'])
                for arm in study['arms']:
                    if arm['mode'] not in ('walk', 'greedy', 'anneal'):
                        raise ValueError('unsupported walk policy')
                    for trial in arm['trials']:
                        i = trial['trial']
                        if type(i) is not int or i < 0:
                            raise ValueError('invalid trial index')
                        for prefix, metric in (('trial', 'parent'), ('end', 'end_parent')):
                            admit(path.parent / arm['mode'] / f'{prefix}-{i}.txt', shape,
                                  trial[metric]['sha256'])

    for root in product_roots:
        source(root, 'composition_audit')
    for root in walk_roots:
        source(root, 'walk_audit')
    for root in projection_roots:
        source(root, 'projection_audit')
    for root in observer_walk_roots:
        source(root, 'observer_walk_audit')
    for name in ('extend_composition_parents.py', 'composition_impact.py',
                 'composition_expression_cover.py', 'verify_representation_portfolio.py'):
        blob(Path(__file__).resolve().parent / name)
    engine_sha256 = pins[str(Path(__file__).resolve().with_name('composition_impact.py'))]
    inputs = dict(complete=True, field='GF(2)', record_claim=False, parents=parents,
        seeds=[dict(shape=s, rank=r) for s, r in prices.items()], source_sha256=pins)
    (output / 'inputs.json').write_text(json.dumps(inputs, indent=2) + '\n')
    (output / 'admissions.json').write_text(json.dumps(admissions, indent=2) + '\n')
    start, cpu = time.monotonic(), time.process_time()
    cover = None
    if (reuse_priced_expressions and old_plan.get('maximum') == maximum and
        isinstance(old_plan.get('pricing_certificate'), dict) and
        old_plan.get('pricing_certificate') == pricing_certificate(old_inputs['parents'], old_plan, engine_sha256)):
        cover = ordinary_expression_cover(old_inputs['parents'], parents[old_count:], maximum)
    if cover is not None:
        (output / 'pricing-expression-cover.json').write_text(json.dumps(cover, indent=2)+'\n')
        shapes = old_plan['model_shapes']
        # The previous closed table supplies every initial price. Equal-cost
        # expressions do not replace first witnesses in the normal solver.
        recipes = [dict(kind='seed' if prices[tuple(s)] < s[0]*s[1]*s[2] else 'naive',
                        rank=prices[tuple(s)]) for s in shapes]
        gains, evaluated = [], 0
        bud_count, mixed_count = old_plan['bud_expressions'], old_plan['mixed_bud_expressions']
    else:
        model = CompositionImpact(prices, parents, maximum=maximum)
        result = model.solve()
        assert model.check_baseline_recipes(result)
        shapes, recipes = model.shapes, result['recipes']
        gains = [dict(shape=s, rank=int(result['values'][i, 0]), baseline=prices.get(s, s[0]*s[1]*s[2]),
                      recipe=recipes[i]) for i, s in enumerate(shapes)
                 if int(result['values'][i, 0]) < prices.get(s, s[0]*s[1]*s[2])]
        bud_count, mixed_count = result['bud_checks'], result['mixed_bud_checks']
        evaluated = bud_count
    report = dict(complete=True, field='GF(2)', record_claim=False, screen_only=True,
        canonical_archive_changed=False, prior_parents=old_count, parents=len(parents), added=dict(added),
        maximum=maximum, model_shapes=shapes, baseline_recipes=recipes,
        actual_price_improvements=gains, bud_expressions=bud_count,
        mixed_bud_expressions=mixed_count, evaluated_bud_expressions=evaluated,
        pricing_reuse=dict(used=cover is not None, appended_parents=len(parents)-old_count,
            covered_axes=3*len(cover) if cover is not None else 0), source_sha256=pins)
    report['pricing_certificate'] = pricing_certificate(parents, report, engine_sha256)
    report.update(elapsed_seconds=time.monotonic()-start, cpu_seconds=time.process_time()-cpu)
    if any(hashlib.sha256(Path(p).read_bytes()).hexdigest() != h for p, h in pins.items()):
        raise ValueError('source changed during extension')
    (output / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inputs', type=Path, required=True)
    parser.add_argument('--plan', type=Path, required=True)
    parser.add_argument('--products', type=Path, action='append', default=[])
    parser.add_argument('--walk', type=Path, action='append', default=[])
    parser.add_argument('--observer-walk', type=Path, action='append', default=[],
                        help='rank-primary reports replayed by verify_observer_walk.py, with or without sidecars')
    parser.add_argument('--projection', type=Path, action='append', default=[])
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--maximum', type=int, choices=range(2, 33), default=32)
    parser.add_argument('--no-reuse-priced-expressions', action='store_true',
                        help='matched control: always run the complete composition planner')
    args = parser.parse_args()
    result = extend(args.inputs, args.plan, args.products, args.walk, args.output, args.maximum,
                    projection_roots=args.projection, reuse_priced_expressions=not args.no_reuse_priced_expressions,
                    observer_walk_roots=args.observer_walk)
    print(json.dumps({k: v for k, v in result.items()
        if k not in ('source_sha256', 'model_shapes', 'baseline_recipes', 'actual_price_improvements')}))
    for row in result['actual_price_improvements']:
        print(json.dumps(row))
