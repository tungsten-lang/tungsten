"""The reusable Ruby producer must feed the independent Python cover checker."""
import hashlib
from itertools import combinations_with_replacement, product
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from verify_parent_cover_scan import verify


@unittest.skipUnless(shutil.which('ruby'), 'Ruby producer required')
class ScanParentCoversIntegrationTest(unittest.TestCase):
    def test_cli_full_scale_domain_and_independent_replay(self):
        command = Path(__file__).resolve().parents[3]/'bits/tungsten-metaflip/tools/scan_parent_covers.rb'
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            terms = [(1 << (i*2+j), 1 << (j*2+k), 1 << (i*2+k))
                     for i,j,k in product(range(2), repeat=3)]
            body = ('8\n'+''.join(' '.join(map(str,t))+'\n' for t in terms)).encode()
            source = root/'seed.txt'; source.write_bytes(body)
            canonical = '2x2x2\n'+''.join(' '.join(map(str,t))+'\n' for t in sorted(terms))
            parent = dict(shape=[2,2,2], path=str(source), rank=8,
                sha256=hashlib.sha256(body).hexdigest(), identity=hashlib.sha256(canonical.encode()).hexdigest(),
                signature=[[2]*4 for _ in range(3)], mixed_partitions=[])
            common = dict(complete=True, field='GF(2)', record_claim=False)
            shapes = list(map(list, combinations_with_replacement(range(1,5), 3)))
            (root/'inputs.json').write_text(json.dumps(dict(common, parents=[parent])))
            (root/'report.json').write_text(json.dumps(dict(common, model_shapes=shapes,
                baseline_recipes=[dict(rank=a*b*c) for a,b,c in shapes])))
            args = ['ruby', str(command), '--inputs', str(root/'inputs.json'), '--plan', str(root/'report.json'),
                    '--output', str(root/'scan'), '--all', '2x2x2', '--max-leaf', '4', '--seconds', '20']
            result = subprocess.run(args, capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stderr)
            report = json.loads((root/'scan/report.json').read_text())
            audit = verify(root/'scan', root/'inputs.json', root/'report.json')
            self.assertEqual((audit['parents'], audit['cases'], audit['tensors']), (1,8,1))
            self.assertTrue(report['all_cases_attempted'])
            self.assertFalse(audit['search_optimality_certified'])
            self.assertFalse(audit['products_materialized'])
            self.assertTrue(audit['family_selection_verified'])
            report_path = root/'scan/report.json'
            original = report_path.read_bytes()
            for key, value in [('family_parents', 2), ('selected_parents', 2),
                               ('sampling_only', 0), ('shape', [1,2,2])]:
                with self.subTest(mutation=key):
                    changed = json.loads(original)
                    changed['selection']['families'][0][key] = value
                    report_path.write_text(json.dumps(changed))
                    with self.assertRaises(AssertionError):
                        verify(root/'scan', root/'inputs.json', root/'report.json')
            report_path.write_bytes(original)
            rerun = subprocess.run(args, capture_output=True, text=True, timeout=30)
            self.assertNotEqual(rerun.returncode, 0)
            self.assertIn('output already exists', rerun.stderr)


if __name__ == '__main__':
    unittest.main()
