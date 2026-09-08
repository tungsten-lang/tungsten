import copy
from contextlib import redirect_stderr, redirect_stdout
import hashlib
import io
from itertools import combinations, permutations
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from extend_composition_parents import identity
from joint_dual_projection_scan import changed_dimensions, kernel_pairs, main, scan
from projection_composition_scan import text
from test_fold_projection_scan import walked
from test_projection_variant_portfolio import expansion, naive
from verify_joint_dual_projections import project_joint_grid, verify


class JointDualProjectionTest(unittest.TestCase):
    def test_complete_pairs_dense_replay_and_tensor_identity(self):
        shape = (3, 3, 3)
        terms = walked(shape, 14)
        for dims in combinations(range(3), 2):
            target = tuple(2 if i in dims else 3 for i in range(3))
            result = scan(shape, terms, target, len(terms), cpu_limit=60)
            self.assertTrue(result['complete'])
            self.assertFalse(result['intermediate_rank_pruning'])
            self.assertEqual(result['views'], 28*28)
            self.assertEqual(result['counts']['coordinate'], 9)
            self.assertEqual(result['counts']['single_dual'], 150)
            self.assertEqual(result['counts']['joint_dual'], 625)
            self.assertEqual(sum(sum(h.values()) for h in result['rank_histograms'].values()), 784)
            identities = set()
            for row in result['rows']:
                metadata = dict(row, parent_shape=list(shape))
                self.assertEqual(row['terms'], project_joint_grid(metadata, terms))
                self.assertEqual(expansion(row['terms']), expansion(naive(target)))
                self.assertNotIn(row['identity'], identities)
                identities.add(row['identity'])
            # A high intermediate rank is never used as a rejection gate.
            self.assertTrue(any(r['intermediate_rank'] > len(naive(target)) for r in result['rows']))

    def test_literal_prior_dedup_and_finite_budget(self):
        terms = walked((3, 3, 3), 3)
        first = scan((3, 3, 3), terms, (2, 2, 3), 100)
        prior = {r['identity'] for r in first['rows']}
        replay = scan((3, 3, 3), terms, (2, 2, 3), 100, prior=prior)
        self.assertTrue(replay['complete'])
        self.assertEqual(replay['rows'], [])
        self.assertEqual(replay['counts']['prior_identity_views'], 784)
        with patch('joint_dual_projection_scan.time.process_time', side_effect=(0.0, 2.0, 2.0)):
            stopped = scan((3, 3, 3), terms, (2, 2, 3), 100, cpu_limit=1.0)
        self.assertFalse(stopped['complete'])
        self.assertEqual(stopped['views'], 0)
        self.assertEqual(stopped['rows'], [])

    def test_cleanup_precedes_rank_gate_and_dense_replay(self):
        shape, target = (3, 3, 3), (2, 2, 3)
        terms = walked(shape, 14)
        rescued = None
        for order in permutations(range(3)):
            report = scan(shape, terms, target, 100, pair_order=order)
            self.assertTrue(report['complete'])
            for row in report['rows']:
                self.assertEqual(row['terms'], project_joint_grid(dict(row, parent_shape=list(shape)), terms))
                self.assertEqual(expansion(row['terms']), expansion(naive(target)))
                if row['raw_rank'] > row['rank']:
                    rescued = row
        self.assertIsNotNone(rescued)
        tight = scan(shape, terms, target, rescued['rank'], pair_order=rescued['reduction_order'])
        self.assertIn(rescued['identity'], {r['identity'] for r in tight['rows']})
        for bad in ((0, 0, 1), (0, 1, True), (0, 1), (0, 1, 3)):
            with self.assertRaises(ValueError):
                scan(shape, terms, target, 100, pair_order=bad)

    def test_invalid_dimensions_and_allowances(self):
        for shape, target in (((3, 3, 3), (2, 3, 3)), ((3, 3, 3), (2, 2, 2)),
                              ((4, 4, 4), (2, 3, 4)), ((True, 3, 3), (2, 2, 3)),
                              ((9, 9, 3), (8, 8, 3))):
            with self.assertRaises(ValueError):
                changed_dimensions(shape, target)
        for n in (True, 1, 9):
            with self.assertRaises(ValueError):
                kernel_pairs(n)
        for kw in (dict(slack=-1), dict(slack=True), dict(cpu_limit=0), dict(cpu_limit=float('nan'))):
            with self.assertRaises(ValueError):
                scan((3, 3, 3), naive((3, 3, 3)), (2, 2, 3), 12, **kw)

    def fixture(self, root, terms, rows):
        source = text(terms)
        (root/'parent.txt').write_bytes(source)
        parent = dict(parent_path='parent.txt', parent_shape=[3, 3, 3],
                      parent_sha256=hashlib.sha256(source).hexdigest())
        outputs = []
        for i, original in enumerate(rows):
            row = copy.deepcopy(original)
            raw = text(row.pop('terms'))
            name = f'child-{i}.txt'
            (root/name).write_bytes(raw)
            row.update(parent, path=name, sha256=hashlib.sha256(raw).hexdigest(),
                       improves_local=row['rank'] < row['baseline'])
            outputs.append(row)
        report = dict(complete=True, field='GF(2)', record_claim=False,
            projection_kind='joint_canonical_dual_kernel', selected_parents=1,
            parents_done=1, rows=[dict(parent, complete=True, views=784, planned_views=784)],
            views=784, outputs=outputs)
        (root/'report.json').write_text(json.dumps(report))
        return report

    def test_independent_report_and_metadata_mutations(self):
        terms = walked((3, 3, 3), 17)
        result = scan((3, 3, 3), terms, (2, 2, 3), 100)
        selected = next(r for r in result['rows'] if r['control_kind'] == 'joint_dual')
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            report = self.fixture(root, terms, [selected])
            self.assertEqual(verify(root)['tensors'], 2)
            for duals in ([selected['duals'][0]]*2, list(reversed(selected['duals'])),
                          [dict(selected['duals'][0], u=0), selected['duals'][1]],
                          [dict(selected['duals'][0], dimension=True), selected['duals'][1]]):
                bad = copy.deepcopy(report)
                bad['outputs'][0]['duals'] = duals
                (root/'report.json').write_text(json.dumps(bad))
                with self.assertRaises(AssertionError):
                    verify(root)
            for key, value in (('control_kind', 'coordinate'), ('intermediate_rank', 0)):
                bad = copy.deepcopy(report)
                bad['outputs'][0][key] = value
                (root/'report.json').write_text(json.dumps(bad))
                with self.assertRaises(AssertionError):
                    verify(root)

    def test_negative_scan_source_is_still_checked(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            terms = naive((3, 3, 3))
            self.fixture(root, terms, [])
            result = verify(root)
            self.assertEqual(result['outputs'], 0)
            self.assertEqual(result['tensors'], 1)
            self.assertEqual(result['selected_source_tensors_checked'], 1)
            terms[0] = (1, 1, 2)
            self.fixture(root, terms, [])
            with self.assertRaises((AssertionError, ValueError)):
                verify(root)

    def cli_fixture(self, root):
        terms = naive((3, 3, 3))
        raw = text(terms)
        source = root/'source.txt'
        source.write_bytes(raw)
        common = dict(complete=True, field='GF(2)', record_claim=False)
        inputs = dict(common, parents=[dict(shape=[3, 3, 3], rank=len(terms), path=str(source),
            sha256=hashlib.sha256(raw).hexdigest(), identity=identity((3, 3, 3), terms))])
        (root/'inputs.json').write_text(json.dumps(inputs))
        (root/'prices.json').write_text(json.dumps(dict(common,
            model_shapes=[[2, 2, 3]], baseline_recipes=[dict(rank=12)])))
        return ['joint_dual_projection_scan.py', '--inputs', str(root/'inputs.json'),
                '--prices', str(root/'prices.json'), '--output', str(root/'out'),
                '--job', '0:2x2x3', '--pair-order', '0,1,2']

    def test_cli_report_replays(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with patch('sys.argv', self.cli_fixture(root)), redirect_stdout(io.StringIO()):
                main()
            report = json.loads((root/'out/report.json').read_text())
            self.assertTrue(report['complete'])
            self.assertEqual(report['views'], 784)
            self.assertEqual(report['limits']['pair_order'], [0, 1, 2])
            self.assertTrue(report['outputs'])
            self.assertEqual(verify(root/'out')['outputs'], len(report['outputs']))

    def test_cli_refuses_overwrite(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            argv = self.cli_fixture(root)
            (root/'out').mkdir()
            (root/'out/marker').write_text('keep')
            with patch('sys.argv', argv), redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit):
                    main()
            self.assertEqual(list((root/'out').iterdir()), [root/'out/marker'])
            self.assertEqual((root/'out/marker').read_text(), 'keep')

    def test_cli_stale_source_stays_incomplete(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            argv = self.cli_fixture(root)
            (root/'source.txt').write_bytes(b'1\n1 1 1\n')
            with patch('sys.argv', argv):
                with self.assertRaisesRegex(ValueError, 'source hash mismatch'):
                    main()
            self.assertFalse(json.loads((root/'out/report.json').read_text())['complete'])
            with self.assertRaises(AssertionError):
                verify(root/'out')


if __name__ == '__main__':
    unittest.main()
