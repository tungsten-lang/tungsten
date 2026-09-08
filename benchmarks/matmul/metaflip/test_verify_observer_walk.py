import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from verify_observer_walk import verify


class ObserverWalkTest(unittest.TestCase):
    def fixture(self, root):
        terms = [(1 << (i*2+j), 1 << (j*2+k), 1 << (i*2+k))
                 for i in range(2) for j in range(2) for k in range(2)]
        body = ('8\n'+''.join(' '.join(map(str, t))+'\n' for t in terms)).encode()
        (root/'tensor.txt').write_bytes(body)
        entry = dict(path='tensor.txt', shape=[2, 2, 2], rank=8, sha256=hashlib.sha256(body).hexdigest())
        table = [list(range(11)) for _ in range(3)]
        price = ('10\n'+''.join(' '.join(map(str, t))+'\n' for t in table)+'observers 1\n'+
                 ''.join(' '.join(map(str, t))+'\n' for t in table)).encode()
        (root/'prices.txt').write_bytes(price)
        totals = dict(strategy='walk', trials='1', chunks='2', steps='7', observe_every='3',
                      attempted='14', observations='6', held_terms='0', held_cost='0',
                      holdout_cancellations='0', initial='8', density_slack='4')
        native = dict(trial='0', rank='8', score='8', bits='24')
        observer = dict(observer=0, native=dict(native, observer='0', trial='0'), winner=entry)
        trial = dict(trial=0, native=native, winner=entry, endpoint=entry, observers=[observer],
                     rank_winner_context_costs=[8])
        summary = dict(target=[2, 2, 2], initial=8, rank_observer=8, context_observer=8,
                       reference=9, below_reference=True)
        row = dict(cell='one', shape=[2, 2, 2], source=entry, trials=[trial], totals=totals,
                   prices=dict(path='prices.txt', sha256=hashlib.sha256(price).hexdigest()),
                   contexts=[dict(scale=[1, 1, 1], target=[2, 2, 2], reference=9, prices=table)],
                   summary=[summary])
        report = dict(complete=True, field='GF(2)', record_claim=False, trials=1, chunks=2, steps=7,
                      observe_every=3, debt=2, density_slack=4, rows=[row], attempts=14)
        plan = dict(complete=True, field='GF(2)', record_claim=False,
                    model_shapes=[[1, 1, k] for k in range(1, 11)],
                    baseline_recipes=[dict(kind='naive', rank=k) for k in range(1, 11)])
        (root/'report.json').write_text(json.dumps(report))
        (root/'plan.json').write_text(json.dumps(plan))
        return report, plan

    def test_replay_and_partial_observation_spans(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            self.fixture(root)
            result = verify(root, root/'plan.json')
            self.assertEqual((result['attempts'], result['tensors'], result['cells']), (14, 1, 1))
            self.assertFalse(result['record_claim'] or result['products_materialized'])
            self.assertFalse(result['references_revalidated'] or result['price_plan_leaves_reverified'])

    def test_rank_only_control_without_sidecars(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            report, _ = self.fixture(root)
            row = report['rows'][0]
            row['contexts'] = row['summary'] = []
            row['trials'][0]['observers'] = row['trials'][0]['rank_winner_context_costs'] = []
            for suffix in (b'', b'grids 1 1 1\n', b'observers 0\n'):
                price = b'\n'.join((root/'prices.txt').read_bytes().splitlines()[:4])+b'\n'+suffix
                (root/'prices.txt').write_bytes(price)
                row['prices']['sha256'] = hashlib.sha256(price).hexdigest()
                (root/'report.json').write_text(json.dumps(report))
                if suffix:
                    with self.assertRaises(AssertionError):
                        verify(root, root/'plan.json')
                else:
                    result = verify(root, root/'plan.json')
                    self.assertEqual((result['attempts'], result['tensors'], result['rows']), (14, 1, []))

    def test_mutated_fields_fail_closed(self):
        for mutation in ('score', 'rank', 'density', 'observer_id', 'trial_id', 'primary_id', 'summary', 'target',
                         'source_shape', 'attempts', 'observations', 'duplicate_cell', 'plan', 'price', 'path'):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as name:
                root = Path(name)
                report, plan = self.fixture(root)
                row = report['rows'][0]
                observer = row['trials'][0]['observers'][0]
                if mutation == 'score': observer['native']['score'] = '7'
                elif mutation == 'rank': observer['native']['rank'] = '7'
                elif mutation == 'density': observer['native']['bits'] = '23'
                elif mutation == 'observer_id': observer['observer'] = 1
                elif mutation == 'trial_id': row['trials'][0]['trial'] = 1
                elif mutation == 'primary_id': row['trials'][0]['native']['trial'] = '1'
                elif mutation == 'summary': row['summary'][0]['context_observer'] = 7
                elif mutation == 'target': row['contexts'][0]['target'] = [2, 2, 3]
                elif mutation == 'source_shape': row['source']['shape'] = [2, 2, 3]
                elif mutation == 'attempts': row['totals']['attempted'] = '13'
                elif mutation == 'observations': row['totals']['observations'] = '4'
                elif mutation == 'duplicate_cell': report['rows'].append(copy.deepcopy(row))
                elif mutation == 'plan': plan['baseline_recipes'][0]['rank'] = 2
                elif mutation == 'price':
                    row['contexts'][0]['prices'][0][1] = 2
                    lines = (root/'prices.txt').read_text().splitlines()[:5]
                    lines += [' '.join(map(str, t)) for t in row['contexts'][0]['prices']]
                    price = ('\n'.join(lines)+'\n').encode()
                    (root/'prices.txt').write_bytes(price)
                    row['prices']['sha256'] = hashlib.sha256(price).hexdigest()
                elif mutation == 'path': row['source']['path'] = '../escape.txt'
                (root/'report.json').write_text(json.dumps(report))
                (root/'plan.json').write_text(json.dumps(plan))
                with self.assertRaises((AssertionError, ValueError)):
                    verify(root, root/'plan.json')

    def test_invalid_tensor_with_updated_hash_is_rejected(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            report, plan = self.fixture(root)
            raw = (root/'tensor.txt').read_bytes().replace(b'1 1 1\n', b'1 1 2\n', 1)
            (root/'tensor.txt').write_bytes(raw)
            # All fixture entries share this object; repair their hashes to
            # ensure failure comes from full tensor reconstruction, not pinning.
            report['rows'][0]['source']['sha256'] = hashlib.sha256(raw).hexdigest()
            (root/'report.json').write_text(json.dumps(report))
            with self.assertRaises(ValueError):
                verify(root, root/'plan.json')

    def test_run_flags_and_native_density_echo_must_agree(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            original, _ = self.fixture(root)
            original['rng_seed'] = 19
            # Old locations are legal after moving a bundle; numeric settings
            # and shape are still checked against the complete run report.
            original['rows'][0]['command'] = ['old/binary', 'old/input', '2x2x2', 'old/prices',
                '1', '2', '7', 'walk', '19', 'old/output', '2', '4', '3']
            for mutation in (None, 'echo', 'density', 'debt', 'bool', 'seed', 'shape', 'mode', 'steps', 'extra'):
                with self.subTest(mutation=mutation):
                    report = copy.deepcopy(original)
                    row = report['rows'][0]
                    if mutation == 'echo': row['totals']['density_slack'] = '16'
                    elif mutation == 'density': report['density_slack'] = 16
                    elif mutation == 'debt': report['debt'] = 3
                    elif mutation == 'bool': report['debt'] = True
                    elif mutation == 'seed': row['command'][8] = '20'
                    elif mutation == 'shape': row['command'][2] = '2x2x3'
                    elif mutation == 'mode': row['command'][7] = 'anneal'
                    elif mutation == 'steps': row['command'][6] = '8'
                    elif mutation == 'extra': row['command'].append('holdout.txt')
                    (root/'report.json').write_text(json.dumps(report))
                    if mutation is None:
                        self.assertTrue(verify(root, root/'plan.json')['complete'])
                    else:
                        with self.assertRaises(AssertionError):
                            verify(root, root/'plan.json')


if __name__ == '__main__':
    unittest.main()
