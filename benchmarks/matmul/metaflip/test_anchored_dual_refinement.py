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

from dual_projection_scan import anchored_dual_family, dual_maps
from pair_reduction_scan import reduce_pairs
from projection_composition_scan import text
from refine_fold_projections import fold_family, refinement_family, run, scan_map
from test_fold_projection_scan import walked
from test_projection_variant_portfolio import expansion, naive
import test_reduced_coordinate_projections as coordinate_tests
from verify_reduced_coordinate_projections import verify as verify_seed
from verify_refined_fold_projections import project_anchored_dual, project_reduced_fold, verify


class AnchoredDualRefinementTest(unittest.TestCase):
    def test_all_anchors_cover_exactly_all_small_weight_odd_kernel_pairs(self):
        shape=(2,3,2); keep=[[0,1],[0,1],[0,1]]
        count,family=anchored_dual_family(shape,keep,True)
        pairs={(1<<2,1<<2)}
        for dual in family:
            if dual is not None:pairs.add((dual['u'],dual['v']))
        expected={(u,v) for u in range(1,8) for v in range(1,8)
                  if u.bit_count()<=2 and v.bit_count()<=2 and (u & v).bit_count()%2}
        self.assertEqual(pairs,expected); self.assertEqual(count,len(expected))
        self.assertEqual(anchored_dual_family((20,24,29),[list(range(20)),list(range(23)),list(range(29))],True)[0],13272)
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory); terms=walked(shape,19); raw=text(terms); path=root/'source.txt'; path.write_bytes(raw)
            entry=dict(shape=shape,path=str(path),rank=len(terms),sha256=hashlib.sha256(raw).hexdigest())
            result=scan_map(entry,keep,8,dual_kernels=True,all_dual_anchors=True)
            self.assertEqual(result['views'],count)
            for dual in (r['dual'] for r in result['trials'] if r['dual'] is not None):
                anchor=(dual['u'] & dual['v']).bit_length()-1
                seed=copy.deepcopy(keep); seed[1]=[i for i in range(3) if i!=anchor]
                actual=copy.deepcopy(seed); actual[1]=list(dual_maps(3,dual['u'],dual['v'])[0])
                row=dict(parent_shape=shape,keep=actual,seed_keep=seed,dual_anchor=anchor,dual=dual)
                self.assertEqual(expansion(project_anchored_dual(row,terms)),expansion(naive((2,2,2))))

    def test_shell_count_matches_equal_budget_one_sided_family(self):
        for shape,keep in (((20,24,28),[list(range(19)),list(range(24)),list(range(27))]),
                           ((3,3,3),[[0,2],[0,1,2],[1,2]])):
            count,family=anchored_dual_family(shape,keep); family=list(family)
            self.assertEqual(count,len(family))
            self.assertEqual(count,fold_family(shape,keep,2)[0])
            for dual in family[1:]:
                d,u,v=(dual[k] for k in ('dimension','u','v'))
                anchor,=set(range(shape[d]))-set(keep[d])
                self.assertEqual(u & v,1 << anchor)
                self.assertLessEqual(u.bit_count(),2); self.assertLessEqual(v.bit_count(),2)
        with patch('dual_projection_scan.DualProjectionCache',side_effect=AssertionError('allocated')):
            with self.assertRaisesRegex(ValueError,'1137 views'):
                scan_map(dict(shape=(20,24,28),path='missing'),
                    [list(range(19)),list(range(24)),list(range(27))],1,max_views=1000,dual_kernels=True)
        for weight,axes in ((2,1),(1,2),(True,1),(1,True)):
            with self.assertRaises(ValueError): refinement_family((3,3,3),[[0,1]]*3,weight,axes,True)

    def test_every_shell_pair_and_cleanup_order_with_changing_canonical_pivot(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory); shape=(3,3,3); seed=[[0,2],[0,1,2],[0,1]]
            terms=walked(shape,31); raw=text(terms); path=root/'source.txt'; path.write_bytes(raw)
            entry=dict(shape=shape,path=str(path),rank=len(terms),sha256=hashlib.sha256(raw).hexdigest())
            changed_pivot=False
            for order in permutations(range(3)):
                expected=[]
                for dual in anchored_dual_family(shape,seed)[1]:
                    keep=copy.deepcopy(seed); anchor=None
                    if dual is not None:
                        d,u,v=(dual[k] for k in ('dimension','u','v'))
                        keep[d]=list(dual_maps(shape[d],u,v)[0]); anchor=(u & v).bit_length()-1
                    changed_pivot |= keep!=seed
                    row=dict(parent_shape=shape,keep=keep,seed_keep=seed,dual_anchor=anchor,dual=dual)
                    child=project_anchored_dual(row,terms)
                    self.assertEqual(expansion(child),expansion(naive((2,3,2))))
                    expected.append((len(child),len(reduce_pairs(child,order)[0])))
                result=scan_map(entry,seed,12,order=order,dual_kernels=True)
                self.assertEqual([(t['raw_rank'],t['rank']) for t in result['trials']],expected)
                self.assertEqual(result['winner']['rank'],min(r for _,r in expected))
                self.assertFalse(result['raw_rank_pruning'])
                row=json.loads(json.dumps(dict(result['winner'],parent_shape=shape)))
                self.assertEqual(project_reduced_fold(row,terms),result['winner']['terms'])
            self.assertTrue(changed_pivot)

    def seed(self,root):
        source,_=coordinate_tests.ReducedCoordinateProjectionTest().run_cli(root)
        (source/'independent-audit.json').write_text(json.dumps(verify_seed(source,1)))
        return source

    def test_cli_complete_audit_and_mutated_shell_metadata(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory); seed=self.seed(root); output=root/'dual'
            args=[sys.executable,'-B',str(Path(__file__).with_name('refine_fold_projections.py')),
                '--seed',str(seed)+':0','--prices',str(root/'plan.json'),'--output',str(output),'--dual-kernels']
            result=subprocess.run(args,text=True,capture_output=True,timeout=30)
            self.assertEqual(result.returncode,0,result.stderr)
            audit=verify(output,1); self.assertEqual(audit['tensors'],2)
            self.assertFalse(audit['search_exhaustion_checked'])
            original=json.loads((output/'report.json').read_bytes())
            self.assertIn(str(Path(__file__).with_name('dual_projection_scan.py').resolve()),original['source_sha256'])
            for change in ('anchor','weight','kind','raw_rank','seed_keep','order'):
                altered=copy.deepcopy(original); row=altered['outputs'][0]
                if change=='anchor': row['dual_anchor']=-1
                elif change=='weight': row['dual']=dict(dimension=0,u=7,v=1)
                elif change=='kind': altered['projection_kind']='bounded_fold_then_shared_pair_reduction'
                elif change=='raw_rank': row['raw_rank']+=1
                elif change=='seed_keep': row['seed_keep'][0]=[]
                else: row['reduction_order']=[2,1,0]
                (output/'report.json').write_text(json.dumps(altered))
                with self.assertRaises(AssertionError): verify(output,1)
            self.assertNotEqual(subprocess.run(args,text=True,capture_output=True,timeout=30).returncode,0)

    def test_rebound_invalid_source_is_rejected_by_full_tensor_check(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory); seed=self.seed(root)
            report=json.loads((seed/'report.json').read_bytes()); audit=json.loads((seed/'independent-audit.json').read_bytes())
            row=report['outputs'][0]; raw=text(walked(row['parent_shape'],31)[:-1])
            (seed/row['parent_path']).write_bytes(raw); row['parent_sha256']=hashlib.sha256(raw).hexdigest()
            audit['source_sha256'][row['parent_path']]=row['parent_sha256']
            body=json.dumps(report).encode(); (seed/'report.json').write_bytes(body)
            audit['report_sha256']=hashlib.sha256(body).hexdigest()
            (seed/'independent-audit.json').write_text(json.dumps(audit))
            run([(seed,0)],root/'plan.json',root/'invalid',dual_kernels=True)
            with self.assertRaisesRegex(ValueError,'tensor mismatch'): verify(root/'invalid',1)


if __name__=='__main__': unittest.main()
