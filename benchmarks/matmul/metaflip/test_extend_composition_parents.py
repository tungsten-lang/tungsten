from collections import Counter
import copy
import hashlib
from itertools import combinations_with_replacement
import json
from pathlib import Path
import tempfile
import unittest

from extend_composition_parents import extend, identity, observer_walk_entries, json_digest
from test_verify_composition_recipes import naive
from test_verify_parent_only_walk import ParentOnlyWalkTest
from verify_composition_recipes import verify as verify_products
from verify_parent_only_walk import verify as verify_walk
from verify_coordinate_projections import verify as verify_projection
import test_verify_observer_walk as observer_fixture
from verify_observer_walk import verify as verify_observers
from verify_parent_cover_scan import verify as verify_covers
import test_verify_parent_cover_scan as cover_fixture


def put(path, data):
    path.write_text(json.dumps(data))


def body(terms):
    return (str(len(terms)) + '\n' + ''.join(' '.join(map(str, t)) + '\n' for t in terms)).encode()


def alternate():
    # An invertible GF(2) basis change in each two-term U bucket. Rank and
    # all three bucket signatures equal naive 2x2x2; literal state differs.
    return [t for i in range(2) for j in range(2) for t in (
        (1 << (2*i+j), 3 << (2*j), 1 << (2*i)),
        (1 << (2*i+j), 2 << (2*j), 3 << (2*i)))]


class ExtendCompositionParentsTest(unittest.TestCase):
    def cover_scan(self, root):
        root.mkdir()
        fixture = cover_fixture.ParentCoverScanTest()
        report, inputs, plan = fixture.fixture(root)
        (root/'original.txt').write_bytes((root/'seed.txt').read_bytes())
        inputs['parents'][0]['path'] = str(root/'original.txt')
        fixture.write(root, report, inputs, plan)
        extend(root/'inputs.json', root/'plan.json', [], [], root/'closed', maximum=2)
        inputs = json.loads((root/'closed/inputs.json').read_bytes())
        plan = json.loads((root/'closed/report.json').read_bytes())
        fixture.write(root, report, inputs, plan)
        put(root/'independent-audit.json', verify_covers(root, root/'inputs.json', root/'plan.json'))
        return root/'inputs.json', root/'plan.json'

    def test_parent_covers_keep_identity_deduplicate_and_invalidate_append_only_reuse(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            scan = root/'scan'
            prior = self.cover_scan(scan)
            control = extend(*prior, [], [], root/'control', maximum=2)
            self.assertTrue(control['pricing_reuse']['used'])
            result = extend(*prior, [], [], root/'out', maximum=2, parent_cover_roots=[scan, scan])
            self.assertEqual(result['parents'], 1)
            self.assertEqual(result['added_cover_partitions'], 1)
            self.assertFalse(result['pricing_reuse']['used'])
            parent = json.loads((root/'out/inputs.json').read_bytes())['parents'][0]
            original = json.loads(prior[0].read_bytes())['parents'][0]
            for key in ('path', 'identity', 'sha256', 'rank'):
                self.assertEqual(parent[key], original[key])
            self.assertEqual(len(parent['mixed_partitions']), 1)
            admissions = json.loads((root/'out/admissions.json').read_bytes())
            self.assertEqual([r['duplicate'] for r in admissions], [False, True])
            self.assertEqual([r['cover'] for r in admissions], [0, 0])
            self.assertTrue(all(r['kind'] == 'parent_cover_audit' for r in admissions))

    def test_parent_cover_proofs_and_literal_factor_maps_fail_closed(self):
        for mutation in ('stale', 'plan', 'proof', 'order', 'factor', 'partition'):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as name:
                root = Path(name)
                scan = root/'scan'
                prior = self.cover_scan(scan)
                report = json.loads((scan/'report.json').read_bytes())
                audit = json.loads((scan/'independent-audit.json').read_bytes())
                if mutation == 'plan':
                    audit['price_plan_sha256'] = '0'*64
                elif mutation == 'proof':
                    audit['covers'][0]['sha256'] = '0'*64
                elif mutation == 'order':
                    lines = (scan/'seed.txt').read_bytes().splitlines()
                    lines[1], lines[2] = lines[2], lines[1]
                    raw = b'\n'.join(lines)+b'\n'
                    (scan/'seed.txt').write_bytes(raw)
                    digest = hashlib.sha256(raw).hexdigest()
                    report['parents'][0]['source']['sha256'] = digest
                    audit['source_sha256']['seed.txt'] = digest
                elif mutation in ('factor', 'partition'):
                    groups = report['parents'][0]['covers'][0]
                    if mutation == 'factor':
                        groups[0] = dict(axis=0, indices=[0, 1, 2, 3])
                    else:
                        groups[-1]['indices'] = [0]
                    audit['covers'][0]['sha256'] = json_digest(groups)
                put(scan/'report.json', report)
                if mutation != 'stale':
                    audit['report_sha256'] = hashlib.sha256((scan/'report.json').read_bytes()).hexdigest()
                put(scan/'independent-audit.json', audit)
                with self.assertRaises(ValueError):
                    extend(*prior, [], [], root/'out', maximum=2, parent_cover_roots=[scan])

    def prior(self, root):
        inputs, plan = root / 'inputs.json', root / 'plan.json'
        put(inputs, dict(complete=True, field='GF(2)', record_claim=False, parents=[]))
        shapes = list(combinations_with_replacement(range(1, 5), 3))
        put(plan, dict(complete=True, field='GF(2)', record_claim=False, model_shapes=shapes,
            baseline_recipes=[dict(kind='naive', rank=a*b*c) for a, b, c in shapes]))
        return inputs, plan

    def products(self, root, entries):
        root.mkdir()
        tensors = []
        for shape, terms, suffix in entries:
            raw = body(terms)
            digest = hashlib.sha256(raw).hexdigest()
            directory = root / suffix
            directory.mkdir(exist_ok=True)
            path = directory / ('x'.join(map(str, shape)) + '-' + digest + '.txt')
            path.write_bytes(raw)
            tensors.append(dict(path=str(path.relative_to(root)), shape=shape, sha256=digest))
        put(root / 'report.json', dict(complete=True, field='GF(2)', record_claim=False,
            tensors=tensors, recipes=[], outputs=[], materialized_targets=0))
        put(root / 'independent-audit.json', verify_products(root, 1))
        return root

    def test_literal_states_not_equal_rank_or_signature(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d).resolve()
            args = self.prior(root)
            n, alt = naive((2, 2, 2)), alternate()
            signature = lambda ts: [sorted(Counter(t[a] for t in ts).values()) for a in range(3)]
            self.assertEqual(signature(n), signature(alt))
            self.assertNotEqual(identity((2, 2, 2), n), identity((2, 2, 2), alt))
            source = self.products(root / 'products', [([2, 2, 2], n, 'first'),
                ([2, 2, 2], alt, 'second'), ([2, 2, 2], n, 'duplicate')])
            report = extend(*args, [source], [], root / 'out', maximum=4)
            self.assertEqual(report['parents'], 2)
            self.assertEqual(report['added'], {'composition_audit': 2})
            self.assertFalse(report['actual_price_improvements'])
            self.assertTrue(report['screen_only'])
            admissions = json.loads((root / 'out/admissions.json').read_text())
            self.assertEqual(sum(a['duplicate'] for a in admissions), 1)
            with self.assertRaisesRegex(ValueError, 'output must not exist'):
                extend(*args, [source], [], root / 'out', maximum=4)

    def test_closed_plan_reuse_keeps_states_and_matches_full_control(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            args = self.prior(root)
            source = self.products(root / 'first', [([2, 2, 2], naive((2, 2, 2)), 'tensor')])
            initial = extend(*args, [source], [], root / 'initial', maximum=4)
            self.assertFalse(initial['pricing_reuse']['used'])
            source = self.products(root / 'next', [([2, 2, 2], alternate(), 'tensor')])
            prior = (root / 'initial/inputs.json', root / 'initial/report.json')
            reused = extend(*prior, [source], [], root / 'reused', maximum=4)
            control = extend(*prior, [source], [], root / 'control', maximum=4, reuse_priced_expressions=False)
            self.assertTrue(reused['pricing_reuse']['used'])
            self.assertEqual(reused['pricing_reuse']['covered_axes'], 3)
            self.assertEqual(reused['parents'], 2)
            self.assertEqual(reused['evaluated_bud_expressions'], 0)
            for key in ('model_shapes', 'baseline_recipes', 'actual_price_improvements',
                        'bud_expressions', 'mixed_bud_expressions'):
                self.assertEqual(json.loads(json.dumps(reused[key])), json.loads(json.dumps(control[key])))
            for mutation in ('engine', 'table', 'parents'):
                inputs = json.loads(prior[0].read_bytes())
                plan = json.loads(prior[1].read_bytes())
                if mutation == 'engine':
                    plan['pricing_certificate']['engine_sha256'] = '0'*64
                elif mutation == 'table':
                    plan['baseline_recipes'][0]['rank'] += 1
                else:
                    inputs['parents'][0]['provenance'] = 'modified'
                a, b = root / f'{mutation}-inputs.json', root / f'{mutation}-plan.json'
                put(a, inputs); put(b, plan)
                fallback = extend(a, b, [source], [], root / mutation, maximum=4)
                self.assertFalse(fallback['pricing_reuse']['used'])

    def test_new_expression_does_not_reuse_closed_plan(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            args = self.prior(root)
            source = self.products(root / 'first', [([2, 2, 2], naive((2, 2, 2)), 'tensor')])
            extend(*args, [source], [], root / 'initial', maximum=4)
            strassen = [(9,9,9),(12,1,12),(1,10,10),(8,5,5),(3,8,3),(5,3,8),(10,12,1)]
            source = self.products(root / 'next', [([2, 2, 2], strassen, 'tensor')])
            result = extend(root / 'initial/inputs.json', root / 'initial/report.json',
                            [source], [], root / 'out', maximum=4)
            self.assertFalse(result['pricing_reuse']['used'])
            self.assertTrue(result['actual_price_improvements'])

    def test_source_and_shape_changes_rejected(self):
        for mutation in ('report', 'bytes', 'shape', 'proof'):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as d:
                root = Path(d).resolve()
                args = self.prior(root)
                source = self.products(root / 'products', [([2, 2, 2], naive((2, 2, 2)), 'tensor')])
                if mutation == 'report':
                    with (source / 'report.json').open('a') as stream:
                        stream.write(' ')
                elif mutation == 'bytes':
                    next((source / 'tensor').glob('*.txt')).write_bytes(body(alternate()))
                else:
                    audit = json.loads((source / 'independent-audit.json').read_text())
                    audit['results'][0]['target' if mutation == 'shape' else 'sha256'] = (
                        '2x2x3' if mutation == 'shape' else '0'*64)
                    put(source / 'independent-audit.json', audit)
                with self.assertRaises(ValueError):
                    extend(*args, [source], [], root / 'out', maximum=4)

    def test_trivial_and_out_of_range_sources_are_audited_but_not_parents(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d).resolve()
            args = self.prior(root)
            source = self.products(root / 'products', [([1, 1, 1], [(1, 1, 1)], 'trivial'),
                ([2, 2, 5], naive((2, 2, 5)), 'large')])
            report = extend(*args, [source], [], root / 'out', maximum=4)
            self.assertEqual(report['parents'], 0)
            admissions = json.loads((root / 'out/admissions.json').read_text())
            self.assertEqual({a['skip'] for a in admissions},
                             {'non_decreasing_dependency', 'outside_maximum'})

    def test_verified_walk_endpoints_are_retained(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d).resolve()
            args = self.prior(root)
            source = root / 'walk'
            source.mkdir()
            ParentOnlyWalkTest().fixture(source)
            alt = alternate()
            raw = body(alt)
            (source / 'study/walk/end-0.txt').write_bytes(raw)
            study = json.loads((source / 'study/report.json').read_text())
            study['arms'][0]['trials'][0]['end_parent'] = dict(rank=len(alt),
                density=sum(v.bit_count() for t in alt for v in t), sha256=hashlib.sha256(raw).hexdigest())
            put(source / 'study/report.json', study)
            put(source / 'independent-audit.json', verify_walk(source, 1))
            report = extend(*args, [], [source], root / 'out', maximum=4)
            self.assertEqual(report['added'], {'walk_audit': 2})
            admissions = json.loads((root / 'out/admissions.json').read_text())
            end = next(a for a in admissions if a['path'] == 'study/walk/end-0.txt')
            self.assertFalse(end['duplicate'])
            self.assertIsNotNone(end['parent'])

    def observer_walk(self, root, sidecar=True):
        root.mkdir()
        report, _ = observer_fixture.ObserverWalkTest().fixture(root)
        row = report['rows'][0]
        terms = alternate()
        raw = body(terms)
        (root/'alternate.txt').write_bytes(raw)
        entry = dict(shape=[2, 2, 2], path='alternate.txt', rank=len(terms),
                     sha256=hashlib.sha256(raw).hexdigest())
        if sidecar:
            row['trials'][0]['observers'][0]['winner'] = entry
            row['trials'][0]['observers'][0]['native']['bits'] = str(sum(v.bit_count() for t in terms for v in t))
        else:
            row['contexts'] = row['summary'] = []
            row['trials'][0]['observers'] = row['trials'][0]['rank_winner_context_costs'] = []
            row['trials'][0]['endpoint'] = entry
            price = b'\n'.join((root/'prices.txt').read_bytes().splitlines()[:4])+b'\n'
            (root/'prices.txt').write_bytes(price)
            row['prices']['sha256'] = hashlib.sha256(price).hexdigest()
        put(root/'report.json', report)
        put(root/'independent-audit.json', verify_observers(root, root/'plan.json'))
        return root

    def test_observer_and_rank_only_admission_preserves_literal_states(self):
        for sidecar in (False, True):
            with self.subTest(sidecar=sidecar), tempfile.TemporaryDirectory() as name:
                root = Path(name).resolve()
                args = self.prior(root)
                source = self.observer_walk(root/'walk', sidecar)
                result = extend(*args, [], [], root/'out', maximum=4, observer_walk_roots=[source])
                self.assertEqual(result['added'], {'observer_walk_audit': 2})
                admissions = json.loads((root/'out/admissions.json').read_text())
                alternate_row = next(r for r in admissions if r['path'] == 'alternate.txt')
                self.assertFalse(alternate_row['duplicate'])
                self.assertIsNotNone(alternate_row['parent'])
                self.assertEqual(alternate_row['origin']['role'], 'observer' if sidecar else 'endpoint')
                self.assertEqual(alternate_row['origin']['trial'], 0)
                self.assertEqual(alternate_row['origin']['cell'], 'one')

    def test_observer_origins_retain_all_occurrences_without_classifying_by_index(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name).resolve()
            args = self.prior(root)
            source = self.observer_walk(root/'walk')
            report = json.loads((source/'report.json').read_text())
            row = report['rows'][0]
            row.update(cohort='prior_rank_matched', parent_index=999999)
            second = copy.deepcopy(row)
            second.update(cell='two', cohort='projected', parent_index=1)
            report['rows'].append(second)
            report['attempts'] *= 2
            put(source/'report.json', report)
            put(source/'independent-audit.json', verify_observers(source, source/'plan.json'))
            before = copy.deepcopy(report)
            entries = list(observer_walk_entries(report))
            self.assertEqual(report, before)
            self.assertEqual(len(entries), 8)
            result = extend(*args, [], [], root/'out', maximum=4, observer_walk_roots=[source])
            self.assertEqual(result['parents'], 2)
            admissions = json.loads((root/'out/admissions.json').read_text())
            self.assertEqual(len(admissions), 8)
            self.assertEqual(sum(a['duplicate'] for a in admissions), 6)
            shared = [a for a in admissions if a['path'] == 'alternate.txt']
            self.assertEqual(len({a['identity'] for a in shared}), 1)
            self.assertEqual([a['origin']['reported_cohort'] for a in shared],
                             ['prior_rank_matched', 'projected'])
            self.assertEqual([a['origin']['reported_parent_index'] for a in shared], [999999, 1])
            for a in admissions:
                origin = a['origin']
                self.assertEqual(origin['source_path'], row['source']['path'])
                self.assertEqual(origin['source_sha256'], row['source']['sha256'])
                self.assertEqual(origin['cell'], report['rows'][origin['row']]['cell'])
                self.assertNotIn('cohort', a)
            self.assertEqual({a['origin']['role'] for a in admissions},
                             {'source', 'winner', 'endpoint', 'observer'})
            self.assertEqual([a['origin']['observer'] for a in shared], [0, 0])

    def test_observer_admission_rejects_stale_artifacts(self):
        for mutation in ('report', 'tensor', 'prices', 'proof', 'attempts', 'cells', 'shape'):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as name:
                root = Path(name).resolve()
                args = self.prior(root)
                source = self.observer_walk(root/'walk')
                audit = json.loads((source/'independent-audit.json').read_text())
                if mutation in ('report', 'tensor', 'prices'):
                    path = source/({'report': 'report.json', 'tensor': 'alternate.txt', 'prices': 'prices.txt'}[mutation])
                    path.write_bytes(path.read_bytes()+b'\n')
                elif mutation == 'proof':
                    for result in audit['results']:
                        result['sha256'] = '0'*64
                elif mutation == 'shape':
                    report = json.loads((source/'report.json').read_text())
                    report['rows'][0]['trials'][0]['observers'][0]['winner']['shape'] = [2, 2, 3]
                    put(source/'report.json', report)
                    audit['report_sha256'] = hashlib.sha256((source/'report.json').read_bytes()).hexdigest()
                else:
                    audit[mutation] += 1
                put(source/'independent-audit.json', audit)
                with self.assertRaises(ValueError):
                    extend(*args, [], [], root/'out', maximum=4, observer_walk_roots=[source])

    def test_improved_shapes_round_trip_as_json_lists(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d).resolve()
            args = self.prior(root)
            strassen = [(9,9,9),(12,1,12),(1,10,10),(8,5,5),
                        (3,8,3),(5,3,8),(10,12,1)]
            source = self.products(root/'products', [([2,2,2],strassen,'strassen')])
            report = extend(*args,[source],[],root/'out',maximum=4)
            saved = json.loads((root/'out/report.json').read_text())
            self.assertEqual(json.loads(json.dumps(report)),saved)
            row = next(r for r in saved['actual_price_improvements'] if r['shape']==[2,2,2])
            self.assertEqual((row['baseline'],row['rank']),(8,7))
            self.assertEqual(saved['baseline_recipes'],report['baseline_recipes'])

    def projections(self, root):
        root.mkdir()
        source_shape = (2, 3, 2)
        terms = naive(source_shape)
        (u, v, w), (_, vv, ww) = terms[:2]
        terms[:2] = [(u, v ^ vv, w), (u, vv, w ^ ww)]
        from verify_coordinate_projections import project_grid
        parent_data = body(terms)
        (root / 'parent.txt').write_bytes(parent_data)
        outputs = []
        for i, middle in enumerate(([0, 1], [1, 2])):
            keep = [[0, 1], middle, [0, 1]]
            child = project_grid(source_shape, terms, keep)
            data = body(child)
            name = f'child-{i}.txt'
            (root / name).write_bytes(data)
            outputs.append(dict(shape=[2, 2, 2], rank=len(child), baseline=8,
                improves_local=False, keep=keep, parent_shape=list(source_shape),
                parent_path='parent.txt', parent_sha256=hashlib.sha256(parent_data).hexdigest(),
                path=name, sha256=hashlib.sha256(data).hexdigest()))
        put(root / 'report.json', dict(complete=True, field='GF(2)', record_claim=False,
            selected_parents=1, parents_done=1, views=2, rows=[dict(views=2)], outputs=outputs))
        put(root / 'independent-audit.json', verify_projection(root, 1))
        return root

    def test_projection_admission_preserves_distinct_representations(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d).resolve()
            args = self.prior(root)
            source = self.projections(root / 'projections')
            report = extend(*args, [], [], root / 'out', maximum=4, projection_roots=[source])
            self.assertEqual({'projection_audit': 2}, report['added'])
            parents = json.loads((root / 'out/inputs.json').read_text())['parents']
            self.assertEqual(2, len({p['identity'] for p in parents}))
            self.assertEqual({8}, {p['rank'] for p in parents})

    def test_projection_admission_rejects_stale_bytes_and_proofs(self):
        for mutation in ('report', 'parent', 'child', 'proof', 'count'):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as d:
                root = Path(d).resolve()
                args = self.prior(root)
                source = self.projections(root / 'projections')
                if mutation == 'report':
                    (source / 'report.json').write_bytes((source / 'report.json').read_bytes() + b' ')
                elif mutation in ('parent', 'child'):
                    path = source / ('parent.txt' if mutation == 'parent' else 'child-0.txt')
                    path.write_bytes(path.read_bytes() + b'\n')
                else:
                    audit = json.loads((source / 'independent-audit.json').read_text())
                    if mutation == 'proof':
                        # The two child tensors share a shape, but require their own proof digests.
                        for result in audit['results']:
                            if result['target'] == '2x2x2':
                                result['sha256'] = '0'*64
                    else:
                        audit['outputs'] += 1
                    put(source / 'independent-audit.json', audit)
                with self.assertRaises(ValueError):
                    extend(*args, [], [], root / 'out', maximum=4, projection_roots=[source])


if __name__ == '__main__':
    unittest.main()
