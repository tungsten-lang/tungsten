import copy
import hashlib
from itertools import permutations
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from pair_reduction_scan import reduce_pairs
from projection_composition_scan import text
from refine_fold_projections import fold_family, run, scan_map
from test_fold_projection_scan import walked
from test_projection_variant_portfolio import expansion, naive
import test_reduced_coordinate_projections as coordinate_tests
from verify_fold_projections import project_fold_grid
from verify_reduced_coordinate_projections import verify as verify_seed
from verify_refined_fold_projections import project_reduced_fold, verify


class RefinedFoldProjectionTest(unittest.TestCase):
    def test_count_guard_before_parent_read_or_cache_allocation(self):
        shape = (32, 32, 32); keep = [list(range(31)) for _ in shape]
        count, family = fold_family(shape, keep, 2)
        self.assertEqual(count, 2977)
        self.assertEqual(len(list(family)), count)
        with patch('refine_fold_projections.FoldCache', side_effect=AssertionError('cache allocated')):
            with self.assertRaisesRegex(ValueError, '2977 views'):
                scan_map(dict(shape=shape, path='missing'), keep, 1, max_weight=2)
        for bad in (-1, 4, True):
            with self.assertRaises(ValueError): fold_family(shape, keep, bad)
        with self.assertRaises(ValueError):
            scan_map(dict(shape=shape), keep, 1, order=(0, 0, 2))

    def test_cleanup_of_every_mask_precedes_selection_all_orders(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); shape = (3, 3, 3)
            terms = walked(shape, 31); raw = text(terms); path = root/'parent.txt'; path.write_bytes(raw)
            entry = dict(shape=shape, path=str(path), sha256=hashlib.sha256(raw).hexdigest(), rank=len(terms))
            keep = [[0, 1], [0, 2], [0, 1, 2]]
            for order in permutations(range(3)):
                expected = []
                for fold in fold_family(shape, keep, 2)[1]:
                    child = project_fold_grid(dict(parent_shape=shape, keep=keep, fold=fold), terms)
                    expected.append((len(child), len(reduce_pairs(child, order)[0])))
                result = scan_map(entry, keep, 18, 2, order)
                self.assertEqual(result['views'], len(expected))
                self.assertFalse(result['raw_rank_pruning'])
                self.assertEqual([(r['raw_rank'], r['rank']) for r in result['trials']], expected)
                winner = result['winner']
                self.assertEqual(winner['rank'], min(rank for _, rank in expected))
                row = json.loads(json.dumps(dict(winner, parent_shape=shape)))
                self.assertEqual(project_reduced_fold(row, terms), winner['terms'])
                self.assertEqual(expansion(winner['terms']), expansion(naive((2, 2, 3))))

    def seed(self, root):
        output, _ = coordinate_tests.ReducedCoordinateProjectionTest().run_cli(root)
        (output/'independent-audit.json').write_text(json.dumps(verify_seed(output, 1)))
        return output

    def test_complete_cli_audit_and_mutations(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); seed = self.seed(root); output = root/'refined'
            args = [sys.executable, '-B', str(Path(__file__).with_name('refine_fold_projections.py')),
                    '--seed', str(seed)+':0', '--prices', str(root/'plan.json'), '--output', str(output)]
            result = subprocess.run(args, text=True, capture_output=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stderr)
            audit = verify(output, 1)
            self.assertEqual(audit['tensors'], 2)
            self.assertFalse(audit['search_exhaustion_checked'])
            report = json.loads((output/'report.json').read_bytes())
            for field in ('raw_rank', 'order', 'fold', 'trace', 'kind'):
                changed = copy.deepcopy(report); row = changed['outputs'][0]
                if field == 'raw_rank': row['raw_rank'] += 1
                elif field == 'order': row['reduction_order'] = [2, 1, 0]
                elif field == 'fold': row['fold'] = dict(dimension=0, factor=1, mask=1)
                elif field == 'trace': row['reduction_trace'].append(dict(axis=0, before=5, after=1))
                else: changed['projection_kind'] = 'unverified'
                (output/'report.json').write_text(json.dumps(changed))
                with self.assertRaises(AssertionError): verify(output, 1)
            self.assertNotEqual(subprocess.run(args, text=True, capture_output=True, timeout=30).returncode, 0)

    def test_stale_seed_and_mutated_tensor_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); seed = self.seed(root)
            original = (seed/'report.json').read_bytes()
            (seed/'report.json').write_bytes(original+b' ')
            with self.assertRaisesRegex(ValueError, 'stale seed audit'):
                run([(seed, 0)], root/'plan.json', root/'bad')
            self.assertFalse((root/'bad').exists())
            (seed/'report.json').write_bytes(original)
            row = json.loads(original)['outputs'][0]
            (seed/row['path']).write_bytes(b'1\nR 1 1 1\n')
            with self.assertRaisesRegex(ValueError, 'seed tensor changed'):
                run([(seed, 0)], root/'plan.json', root/'changed')

    def test_rebound_hashes_still_cannot_admit_invalid_tensor(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); seed = self.seed(root)
            report = json.loads((seed/'report.json').read_bytes()); audit = json.loads((seed/'independent-audit.json').read_bytes())
            row = report['outputs'][0]
            terms = walked(row['parent_shape'], 31)[:-1]; raw = text(terms)
            (seed/row['parent_path']).write_bytes(raw)
            row['parent_sha256'] = hashlib.sha256(raw).hexdigest()
            audit['source_sha256'][row['parent_path']] = row['parent_sha256']
            body = json.dumps(report).encode(); (seed/'report.json').write_bytes(body)
            audit['report_sha256'] = hashlib.sha256(body).hexdigest()
            (seed/'independent-audit.json').write_text(json.dumps(audit))
            run([(seed, 0)], root/'plan.json', root/'invalid')
            with self.assertRaisesRegex(ValueError, 'tensor mismatch'): verify(root/'invalid', 1)


if __name__ == '__main__': unittest.main()
