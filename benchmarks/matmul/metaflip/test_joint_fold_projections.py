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

from fold_projection_scan import JointFoldCache
from pair_reduction_scan import reduce_pairs
from projection_composition_scan import text
from refine_fold_projections import fold_family, scan_map
from test_fold_projection_scan import walked
from test_projection_variant_portfolio import expansion, naive
from verify_coordinate_projections import project_grid
from verify_reduced_coordinate_projections import verify as verify_seed
from verify_refined_fold_projections import project_joint_fold_grid, project_reduced_fold, verify


class JointFoldProjectionTest(unittest.TestCase):
    def test_all_joint_sides_and_cache_prefix_switches(self):
        shape=(3,3,3); keep=[[0,2],[0,1],[1,2]]
        for seed in (12,31):
            terms=walked(shape,seed); cache=JointFoldCache(shape,terms,keep)
            count,family=fold_family(shape,keep,1,3); family=list(family)
            self.assertEqual(count,125)
            expected=expansion(naive((2,2,2)))
            for folds in family+list(reversed(family)):
                child=cache.restrict(folds)
                self.assertEqual(child,project_joint_fold_grid(dict(parent_shape=shape,keep=keep,folds=folds),terms))
                self.assertEqual(expansion(child),expected)
                self.assertLessEqual(len(cache.caches),3)
                self.assertLessEqual(len(cache.tokens),2)

    def test_cleanup_minimum_and_every_order(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory); shape=(3,3,3); keep=[[0,1],[0,2],[0,1,2]]
            terms=walked(shape,31); raw=text(terms); path=root/'source.txt'; path.write_bytes(raw)
            entry=dict(shape=shape,path=str(path),sha256=hashlib.sha256(raw).hexdigest(),rank=len(terms))
            for order in permutations(range(3)):
                expected=[]
                for folds in fold_family(shape,keep,2,2)[1]:
                    child=project_joint_fold_grid(dict(parent_shape=shape,keep=keep,folds=folds),terms)
                    expected.append((len(child),len(reduce_pairs(child,order)[0])))
                result=scan_map(entry,keep,12,2,order,max_axes=2)
                self.assertEqual([(r['raw_rank'],r['rank']) for r in result['trials']],expected)
                self.assertEqual(result['winner']['rank'],min(r for _,r in expected))
                self.assertFalse(result['raw_rank_pruning'])
                row=json.loads(json.dumps(dict(result['winner'],parent_shape=shape)))
                self.assertEqual(project_reduced_fold(row,terms),result['winner']['terms'])

    def test_limits_precede_allocation_and_repeated_axes_rejected(self):
        shape=(20,24,28); keep=[list(range(19)),list(range(24)),list(range(27))]
        count,family=fold_family(shape,keep,1,2)
        self.assertEqual(count,2145); self.assertEqual(len(list(family)),count)
        with patch('refine_fold_projections.JointFoldCache',side_effect=AssertionError('allocated')):
            with self.assertRaisesRegex(ValueError,'2145 views'):
                scan_map(dict(shape=shape,path='missing'),keep,1,max_axes=2)
        for axes in (0,4,True):
            with self.assertRaises(ValueError): fold_family(shape,keep,1,axes)
        small=(3,3,3); coords=[[0,1],[0,1],[0,1,2]]; terms=walked(small,31)
        good=dict(dimension=0,factor=0,mask=1)
        for folds in ([good,good],[dict(dimension=0,factor=1,mask=1)],
                      [dict(dimension=0,factor=0,mask=4)],[dict(dimension=2,factor=2,mask=1)]):
            with self.assertRaises(ValueError): JointFoldCache(small,terms,coords).restrict(folds)
            with self.assertRaises(AssertionError):
                project_joint_fold_grid(dict(parent_shape=small,keep=coords,folds=folds),terms)
        with self.assertRaises(ValueError): JointFoldCache(small,terms,[[0],[0,1],[0,1,2]])

    def test_identity_control_replays_duplicate_parity(self):
        shape=(2,2,2); keep=[list(range(n)) for n in shape]
        terms=naive(shape); terms+=terms[:1]*2
        actual=JointFoldCache(shape,terms,keep).restrict([])
        self.assertEqual(actual,project_joint_fold_grid(dict(parent_shape=shape,keep=keep,folds=[]),terms))

    def test_joint_cli_and_metadata_mutations(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory); seed=root/'seed'; seed.mkdir()
            shape=[3,3,3]; keep=[[0,1],[0,2],[0,1,2]]; target=[2,2,3]
            terms=walked(shape,31); raw=project_grid(shape,terms,keep); child,trace=reduce_pairs(raw)
            source=text(terms); data=text(child)
            (seed/'parent.txt').write_bytes(source); (seed/'child.txt').write_bytes(data)
            row=dict(parent_shape=shape,shape=target,keep=keep,rank=len(child),raw_rank=len(raw),
                reduction_order=[0,1,2],reduction_trace=trace,baseline=len(child),improves_local=False,
                parent_path='parent.txt',parent_sha256=hashlib.sha256(source).hexdigest(),
                path='child.txt',sha256=hashlib.sha256(data).hexdigest())
            report=dict(complete=True,field='GF(2)',record_claim=False,selected_parents=1,parents_done=1,
                projection_kind='coordinate_then_shared_pair_reduction',limits=dict(pair_order=[0,1,2]),
                views=1,rows=[dict(views=1)],outputs=[row])
            (seed/'report.json').write_text(json.dumps(report))
            (seed/'independent-audit.json').write_text(json.dumps(verify_seed(seed,1)))
            plan=root/'plan.json'; plan.write_text(json.dumps(dict(complete=True,field='GF(2)',record_claim=False,
                model_shapes=[target],baseline_recipes=[dict(rank=12,kind='naive')])))
            out=root/'out'; args=[sys.executable,'-B',str(Path(__file__).with_name('refine_fold_projections.py')),
                '--seed',str(seed)+':0','--prices',str(plan),'--output',str(out),'--max-folded-axes','2']
            result=subprocess.run(args,text=True,capture_output=True,timeout=30)
            self.assertEqual(result.returncode,0,result.stderr)
            audit=verify(out,1); self.assertEqual(audit['tensors'],2)
            self.assertFalse(audit['search_exhaustion_checked'])
            original=json.loads((out/'report.json').read_bytes())
            for change in ('repeated','mode','order','rank','mask_limit'):
                altered=copy.deepcopy(original); row=altered['outputs'][0]
                if change=='repeated': row['folds']=[dict(dimension=0,factor=0,mask=1)]*2
                elif change=='mode': altered['projection_kind']='bounded_fold_then_shared_pair_reduction'
                elif change=='order': row['reduction_order']=[2,1,0]
                elif change=='rank': row['raw_rank']+=1
                else: row['folds']=[dict(dimension=0,factor=0,mask=3)]
                (out/'report.json').write_text(json.dumps(altered))
                with self.assertRaises(AssertionError): verify(out,1)


if __name__=='__main__': unittest.main()
