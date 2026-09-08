import copy
import hashlib
from itertools import product
import json
from pathlib import Path
import tempfile
import unittest

from verify_parent_cover_scan import verify


class ParentCoverScanTest(unittest.TestCase):
    def fixture(self, root):
        terms = [(1 << (i*2+j), 1 << (j*2+k), 1 << (i*2+k))
                 for i, j, k in product(range(2), repeat=3)]
        body = ('8\n'+''.join(' '.join(map(str, t))+'\n' for t in terms)).encode()
        (root/'seed.txt').write_bytes(body)
        digest = hashlib.sha256(body).hexdigest()
        canonical = '2x2x2\n'+''.join(' '.join(map(str, t))+'\n' for t in sorted(terms))
        identity = hashlib.sha256(canonical.encode()).hexdigest()
        entry = dict(path='seed.txt', shape=[2, 2, 2], rank=8, sha256=digest)
        prior = dict(entry, path=str(root/'seed.txt'), identity=identity,
                     signature=[[2]*4 for _ in range(3)], mixed_partitions=[])
        inputs = dict(complete=True, field='GF(2)', record_claim=False, parents=[prior])
        shapes = [[1, 1, 1], [1, 1, 2], [1, 2, 2], [2, 2, 2]]
        plan = dict(complete=True, field='GF(2)', record_claim=False,
                    model_shapes=shapes, baseline_recipes=[dict(rank=1 << i) for i in range(4)])
        covers = [[dict(elementary_shape=[1, 2, 2], indices=list(range(4)))] +
                  [dict(axis=0, indices=[i]) for i in range(4, 8)]]
        parent = dict(index=0, identity=identity, source=entry, shape=[2, 2, 2], rank=8,
                      prior_mixed_partitions=0, covers=covers)
        row = dict(parent=0, scale=[1, 1, 1], target=[2, 2, 2], pure_rank=8, local_rank=8,
                   cover=0, rank=8, improved=False,
                   packing=dict(formula_rank=8, exact_within_model=True, record_claim=False))
        report = dict(complete=True, field='GF(2)', record_claim=False, limits=dict(max_leaf=2),
                      requested_parents=1, requested_cases=1, parents=[parent], rows=[row],
                      direct_improvements=[], all_cases_attempted=True, all_exact_within_model=True)
        self.write(root, report, inputs, plan)
        return report, inputs, plan

    def write(self, root, report, inputs, plan):
        for name, value in (('inputs.json', inputs), ('plan.json', plan)):
            (root/name).write_text(json.dumps(value)+'\n')
        report['source_sha256'] = {
            '/historical/inputs.json': hashlib.sha256((root/'inputs.json').read_bytes()).hexdigest(),
            '/historical/report.json': hashlib.sha256((root/'plan.json').read_bytes()).hexdigest()}
        (root/'report.json').write_text(json.dumps(report)+'\n')

    def check(self, root):
        return verify(root, root/'inputs.json', root/'plan.json')

    def test_complete_grid_cover_replay_and_relocation(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            report, inputs, plan = self.fixture(root)
            inputs['parents'][0]['path'] = '/old/location/no-longer-present.txt'
            self.write(root, report, inputs, plan)
            result = self.check(root)
            self.assertEqual((result['parents'], result['cases'], result['tensors']), (1, 1, 1))
            self.assertEqual(len(result['covers']), 1)
            self.assertFalse(result['search_optimality_certified'])
            self.assertFalse(result['products_materialized'])

    def test_mutated_partition_and_accounting_fail_closed(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            original, inputs, plan = self.fixture(root)
            for mutation in ('overlap', 'grid_order', 'wrong_axis', 'identity', 'score', 'pure',
                             'local', 'scale', 'duplicate', 'count', 'claim', 'bool', 'escape'):
                with self.subTest(mutation=mutation):
                    r = copy.deepcopy(original)
                    p, row = r['parents'][0], r['rows'][0]
                    if mutation == 'overlap': p['covers'][0][-1]['indices'] = [0]
                    elif mutation == 'grid_order': p['covers'][0][0]['indices'] = [0, 2, 1, 3]
                    elif mutation == 'wrong_axis': p['covers'][0][0] = dict(axis=0, indices=[0, 1, 2, 3])
                    elif mutation == 'identity': p['identity'] = '0'*64
                    elif mutation == 'score': row['rank'] = row['packing']['formula_rank'] = 7
                    elif mutation == 'pure': row['pure_rank'] = 9
                    elif mutation == 'local': row['local_rank'] = 9
                    elif mutation == 'scale': row['scale'] = [2, 1, 1]
                    elif mutation == 'duplicate': r['rows'].append(copy.deepcopy(row))
                    elif mutation == 'count': r['requested_cases'] = 2
                    elif mutation == 'claim': r['record_claim'] = True
                    elif mutation == 'bool': row['parent'] = False
                    elif mutation == 'escape': p['source']['path'] = '../seed.txt'
                    self.write(root, r, inputs, plan)
                    with self.assertRaises((AssertionError, ValueError)):
                        self.check(root)

    def test_incomplete_optimizer_is_not_promoted_to_optimality(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            report, inputs, plan = self.fixture(root)
            report['rows'][0]['packing']['exact_within_model'] = False
            report['all_exact_within_model'] = False
            self.write(root, report, inputs, plan)
            self.assertTrue(self.check(root)['complete'])
            row = report['rows'][0]
            for key in ('cover', 'rank', 'packing'):
                del row[key]
            row['timed_out'] = True
            self.write(root, report, inputs, plan)
            self.assertTrue(self.check(root)['complete'])

    def test_invalid_tensor_rejected_even_with_rebound_metadata(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            report, inputs, plan = self.fixture(root)
            lines = (root/'seed.txt').read_text().splitlines()
            lines[5] = '3 1 4'
            body = ('\n'.join(lines)+'\n').encode()
            (root/'seed.txt').write_bytes(body)
            digest = hashlib.sha256(body).hexdigest()
            terms = sorted(tuple(map(int, line.split())) for line in lines[1:])
            identity = hashlib.sha256(('2x2x2\n'+''.join(' '.join(map(str, t))+'\n' for t in terms)).encode()).hexdigest()
            report['parents'][0]['source']['sha256'] = inputs['parents'][0]['sha256'] = digest
            report['parents'][0]['identity'] = inputs['parents'][0]['identity'] = identity
            # Singletons impose no equality assumptions; the full tensor gate
            # must catch the wrong polynomial, not a coincidental group check.
            report['parents'][0]['covers'] = [[dict(axis=0, indices=[i]) for i in range(8)]]
            self.write(root, report, inputs, plan)
            with self.assertRaises(ValueError):
                self.check(root)


if __name__ == '__main__':
    unittest.main()
