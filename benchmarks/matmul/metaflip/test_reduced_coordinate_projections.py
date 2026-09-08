import copy
import hashlib
from itertools import combinations_with_replacement, permutations, product
import json
from math import prod
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from extend_composition_parents import identity
from pair_reduction_scan import reduce_pairs
from projection_composition_scan import families, scan_parent, text
from test_fold_projection_scan import walked
from test_projection_variant_portfolio import expansion, naive
from verify_coordinate_projections import project_grid
from verify_reduced_coordinate_projections import project_reduced_grid, verify


class ReducedCoordinateProjectionTest(unittest.TestCase):
    def fixture(self,root,invalid=False):
        shape=(3,3,3); terms=walked(shape,31)
        if invalid:terms=terms[:-1]
        raw=text(terms); path=root/'parent.txt'; path.write_bytes(raw)
        entry=dict(id=0,path=str(path),shape=shape,rank=len(terms),
            sha256=hashlib.sha256(raw).hexdigest(),identity=identity(shape,terms))
        return entry,terms

    def test_cleanup_precedes_minimum_selection_and_does_not_raw_rank_prune(self):
        with tempfile.TemporaryDirectory() as directory:
            entry,terms=self.fixture(Path(directory))
            control=scan_parent((entry,[],1000),max_deleted_axes=1)
            after=scan_parent((entry,[],1000),max_deleted_axes=1,pair_order=(0,1,2))
            before_row=next(r for r in control['rows'] if r['shape']==(3,2,3))
            after_row=next(r for r in after['rows'] if r['shape']==(3,2,3))
            self.assertEqual(before_row['rank'],19)
            self.assertEqual(len(reduce_pairs(before_row['terms'])[0]),19)
            self.assertEqual((after_row['raw_rank'],after_row['rank']),(20,18))
            self.assertEqual(after_row['keep'],((0,1,2),(0,2),(0,1,2)))
            self.assertFalse(after['raw_rank_pruning'])
            self.assertGreater(after['pair_reduced_views'],0)
            self.assertEqual(after['views'],control['views'])
            self.assertNotIn('raw_rank',before_row)
            self.assertEqual(expansion(after_row['terms']),expansion(naive(after_row['shape'])))

    def test_all_orders_choose_the_post_cleanup_minimum_with_independent_replay(self):
        with tempfile.TemporaryDirectory() as directory:
            entry,terms=self.fixture(Path(directory))
            for order in permutations(range(3)):
                expected={}
                for _,axes,_ in families(entry['shape'],[],1000,2):
                    for keep in product(*axes):
                        child=project_grid(entry['shape'],terms,[list(k) for k in keep])
                        rank=len(reduce_pairs(child,order)[0]); shape=tuple(map(len,keep))
                        expected[shape]=min(expected.get(shape,(10**9,())),(rank,keep))
                result=scan_parent((entry,[],1000),max_deleted_axes=2,pair_order=order)
                for row in result['rows']:
                    self.assertEqual((row['rank'],row['keep']),expected[row['shape']])
                    wire=json.loads(json.dumps(dict(row,parent_shape=entry['shape'])))
                    self.assertEqual(project_reduced_grid(wire,terms),row['terms'])
                    self.assertEqual(expansion(row['terms']),expansion(naive(row['shape'])))
            for bad in ((0,1),(0,0,2),(0,1,True),(0,1,3)):
                with self.assertRaises(ValueError):scan_parent((entry,[],1000),pair_order=bad)

    def run_cli(self,root,invalid=False):
        entry,_=self.fixture(root)
        inputs=root/'inputs.json'; plan=root/'plan.json'; output=root/'out'
        shapes=list(combinations_with_replacement(range(1,4),3))
        inputs.write_text(json.dumps(dict(complete=True,field='GF(2)',record_claim=False,parents=[entry])))
        plan.write_text(json.dumps(dict(complete=True,field='GF(2)',record_claim=False,model_shapes=shapes,
            baseline_recipes=[dict(kind='naive',rank=prod(s)) for s in shapes])))
        if invalid:
            entry,_=self.fixture(root,True)
            inputs.write_text(json.dumps(dict(complete=True,field='GF(2)',record_claim=False,parents=[entry])))
        args=[sys.executable,'-B',str(Path(__file__).with_name('projection_composition_scan.py')),
            '--inputs',str(inputs),'--prices',str(plan),'--output',str(output),
            '--max-deleted-axes','1','--pair-order','0,1,2','--workers','1']
        result=subprocess.run(args,text=True,capture_output=True,timeout=30)
        self.assertEqual(result.returncode,0,result.stderr)
        return output,args

    def test_cli_complete_audit_and_metadata_mutations(self):
        with tempfile.TemporaryDirectory() as directory:
            output,args=self.run_cli(Path(directory))
            report=json.loads((output/'report.json').read_bytes())
            self.assertIn(str(Path(__file__).with_name('pair_reduction_scan.py').resolve()),report['source_sha256'])
            checked=verify(output,1)
            self.assertEqual(checked['outputs'],3)
            self.assertFalse(checked['search_exhaustion_checked'])
            index=next(i for i,r in enumerate(report['outputs']) if r['reduction_trace'])
            for mutation in ('raw_rank','trace','order','kind'):
                changed=copy.deepcopy(report); row=changed['outputs'][index]
                if mutation=='raw_rank':row['raw_rank']+=1
                elif mutation=='trace':row['reduction_trace'][0]['after']+=1
                elif mutation=='order':row['reduction_order']=[1,0,2]
                else:changed['projection_kind']='ordinary'
                (output/'report.json').write_text(json.dumps(changed))
                with self.assertRaises(AssertionError):verify(output,1)
            self.assertNotEqual(subprocess.run(args,text=True,capture_output=True,timeout=30).returncode,0)

    def test_rebound_source_hash_cannot_hide_an_invalid_tensor(self):
        with tempfile.TemporaryDirectory() as directory:
            output,_=self.run_cli(Path(directory),invalid=True)
            with self.assertRaisesRegex(ValueError,'tensor mismatch'):verify(output,1)


if __name__=='__main__':unittest.main()
