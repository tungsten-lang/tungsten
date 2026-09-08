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

from dual_projection_scan import dual_maps, dual_neighborhood
from pair_reduction_scan import reduce_pairs
from projection_composition_scan import text
from refine_fold_projections import refinement_family, run, scan_map
from test_fold_projection_scan import walked
from test_projection_variant_portfolio import expansion, naive
from verify_dual_projections import project_dual_grid, verify as verify_seed
from verify_refined_fold_projections import project_reduced_fold, verify


class DualNeighborhoodTest(unittest.TestCase):
    def test_exact_small_bit_ball_and_preflight_guards(self):
        for n in (2,3,4):
            shape=(n,2,2)
            for u,v in ((1,1),(3,1),(1,3)):
                keep=[list(dual_maps(n,u,v)[0]),[0,1],[0,1]]
                center=dict(dimension=0,u=u,v=v)
                for radius in (1,2,3):
                    count,family=dual_neighborhood(shape,keep,center,radius); rows=list(family)
                    expected={(a,b) for a in range(1,1<<n) for b in range(1,1<<n)
                              if (a&b).bit_count()%2 and (a^u).bit_count()+(b^v).bit_count()<=radius}
                    self.assertEqual(rows[0],center)
                    self.assertEqual(count,len(rows)); self.assertEqual(count,len(expected))
                    self.assertEqual({(r['u'],r['v']) for r in rows},expected)
        center=dict(dimension=1,u=69632,v=4352)
        keep=[list(range(20)),list(dual_maps(24,center['u'],center['v'])[0]),list(range(29))]
        count,_=dual_neighborhood((20,24,29),keep,center,2)
        with patch('dual_projection_scan.DualProjectionCache',side_effect=AssertionError('allocated')):
            with self.assertRaisesRegex(ValueError,f'{count} views'):
                scan_map(dict(shape=(20,24,29),path='missing'),keep,7430,max_views=count-1,
                         dual_center=center,dual_edit_radius=2)
        for radius in (0,4,True):
            with self.assertRaises(ValueError): dual_neighborhood((20,24,29),keep,center,radius)
        for options in (dict(dual_kernels=True),dict(all_dual_anchors=True),dict(max_weight=2),dict(max_axes=2)):
            args=dict(shape=(20,24,29),keep=keep,max_weight=1,max_axes=1,dual_kernels=False,
                      dual_center=center,dual_edit_radius=2); args.update(options)
            with self.assertRaises(ValueError): refinement_family(**args)
        bad=copy.deepcopy(center); bad['u']=bad['v']^1
        with self.assertRaises(ValueError): dual_neighborhood((20,24,29),keep,bad,2)

    def test_all_candidates_and_cleanup_orders_replay(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory); shape=(3,3,3); terms=walked(shape,19); raw=text(terms)
            path=root/'source.txt'; path.write_bytes(raw)
            entry=dict(shape=shape,path=str(path),rank=len(terms),sha256=hashlib.sha256(raw).hexdigest())
            for dimension in range(3):
                center=dict(dimension=dimension,u=7,v=7)
                keep=[list(range(3)) for _ in shape]; keep[dimension]=[1,2]
                for order in permutations(range(3)):
                    result=scan_map(entry,keep,18,order=order,dual_center=center,dual_edit_radius=2)
                    expected=[]
                    for trial in result['trials']:
                        dual=trial['dual']; actual=copy.deepcopy(keep)
                        actual[dimension]=list(dual_maps(3,dual['u'],dual['v'])[0])
                        child=project_dual_grid(dict(parent_shape=shape,keep=actual,dual=dual),terms)
                        self.assertEqual(expansion(child),expansion(naive(tuple(map(len,keep)))))
                        expected.append((len(child),len(reduce_pairs(child,order)[0])))
                    self.assertEqual(expected,[(r['raw_rank'],r['rank']) for r in result['trials']])
                    self.assertEqual(result['control'],dict(raw_rank=expected[0][0],rank=expected[0][1]))
                    row=json.loads(json.dumps(dict(result['winner'],parent_shape=shape)))
                    self.assertEqual(project_reduced_fold(row,terms),result['winner']['terms'])
                    self.assertFalse(result['raw_rank_pruning'])

    def seed(self,root):
        source=root/'seed'; source.mkdir(); shape=(3,3,3); terms=walked(shape,12)
        keep=[[1,2],[0,1,2],[0,1,2]]; dual=dict(dimension=0,u=3,v=5)
        child=project_dual_grid(dict(parent_shape=shape,keep=keep,dual=dual),terms)
        a,b=text(terms),text(child); (source/'parent.txt').write_bytes(a); (source/'child.txt').write_bytes(b)
        row=dict(parent_shape=shape,shape=[2,3,3],keep=keep,dual=dual,
                 parent_path='parent.txt',parent_sha256=hashlib.sha256(a).hexdigest(),
                 path='child.txt',sha256=hashlib.sha256(b).hexdigest(),rank=len(child),baseline=len(child),improves_local=False)
        report=dict(complete=True,field='GF(2)',record_claim=False,projection_kind='canonical_dual_kernel',
                    selected_parents=1,parents_done=1,rows=[dict(views=1)],views=1,outputs=[row])
        (source/'report.json').write_text(json.dumps(report))
        (source/'independent-audit.json').write_text(json.dumps(verify_seed(source,1)))
        (root/'plan.json').write_text(json.dumps(dict(complete=True,field='GF(2)',record_claim=False,
            model_shapes=[[2,3,3]],baseline_recipes=[dict(rank=len(child))])))
        return source

    def test_cli_audit_mutations_and_neighborhood_chaining(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory); seed=self.seed(root); output=root/'out'
            args=[sys.executable,'-B',str(Path(__file__).with_name('refine_fold_projections.py')),
                '--seed',str(seed)+':0','--prices',str(root/'plan.json'),'--output',str(output),'--dual-edit-radius','2']
            result=subprocess.run(args,capture_output=True,text=True,timeout=30)
            self.assertEqual(result.returncode,0,result.stderr)
            audit=verify(output,1); self.assertFalse(audit['search_exhaustion_checked'])
            original=json.loads((output/'report.json').read_bytes())
            (output/'independent-audit.json').write_text(json.dumps(audit))
            second=root/'second'; run([(output,0)],root/'plan.json',second,dual_edit_radius=1)
            self.assertTrue(verify(second,1)['complete'])
            for change in ('radius','center','dimension','anchor','mode','rank','keep'):
                altered=copy.deepcopy(original); row=altered['outputs'][0]
                if change=='radius': altered['limits']['dual_edit_radius']=0
                elif change=='center': row['dual_center']['u']=0
                elif change=='dimension': row['dual_center']['dimension']=1
                elif change=='anchor': row['dual_anchor']=0
                elif change=='mode': altered['projection_kind']='anchored_dual_then_shared_pair_reduction'; altered['limits']['dual_kernel_extra_bits']=1
                elif change=='rank': row['raw_rank']+=1
                else: row['seed_keep'][1]=[0,1]
                (output/'report.json').write_text(json.dumps(altered))
                with self.assertRaises((AssertionError,KeyError)): verify(output,1)
            self.assertNotEqual(subprocess.run(args,capture_output=True,text=True,timeout=30).returncode,0)

    def test_valid_but_distant_pair_rejected_by_edit_budget(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory); seed=self.seed(root); output=root/'out'
            run([(seed,0)],root/'plan.json',output,dual_edit_radius=2)
            report=json.loads((output/'report.json').read_bytes()); row=report['outputs'][0]
            target=row['dual']; center=next(dict(dimension=0,u=u,v=v) for u in range(1,8) for v in range(1,8)
                if (u&v).bit_count()%2 and (u^target['u']).bit_count()+(v^target['v']).bit_count()>2)
            row['dual_center']=center; row['seed_keep'][0]=list(dual_maps(3,center['u'],center['v'])[0])
            (output/'report.json').write_text(json.dumps(report))
            with self.assertRaises(AssertionError): verify(output,1)


if __name__=='__main__': unittest.main()
