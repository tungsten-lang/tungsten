import itertools
import random
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from collections import Counter

from projection_composition_scan import ProjectionCache, families, scan_parent, text, validate_keep
from extend_composition_parents import identity

EDGES=((0,1),(1,2),(0,2))


def naive(shape):
    n,m,p=shape
    return [(1<<(i*m+j),1<<(j*p+k),1<<(i*p+k)) for i,j,k in itertools.product(range(n),range(m),range(p))]


def direct(shape,terms,keep):
    counts=Counter()
    for term in terms:
        result=[]
        for word,(a,b) in zip(term,EDGES):
            out=0
            for i,old_i in enumerate(keep[a]):
                for j,old_j in enumerate(keep[b]):
                    out|=((word>>(old_i*shape[b]+old_j))&1)<<(i*len(keep[b])+j)
            result.append(out)
        if all(result):counts[tuple(result)]+=1
    return sorted(t for t,n in counts.items() if n%2)


class ProjectionCompositionTest(unittest.TestCase):
    def test_all_nonempty_restrictions_of_small_naive_tensor(self):
        shape=(2,3,2);terms=naive(shape);cache=ProjectionCache(shape,terms)
        choices=[sum((list(itertools.combinations(range(n),k)) for k in range(1,n+1)),[]) for n in shape]
        for keep in itertools.product(*choices):
            actual=cache.restrict(keep,True)
            self.assertEqual(actual,sorted(naive(tuple(map(len,keep)))))
            self.assertEqual(cache.restrict(keep),len(actual))

    def test_matches_independent_bit_grid_with_duplicates_and_zeros(self):
        rng=random.Random(949907)
        for _ in range(150):
            shape=(3,4,5)
            terms=[tuple(rng.randrange(1<<(shape[a]*shape[b])) for a,b in EDGES) for _ in range(24)]
            terms+=terms[:3]
            keep=tuple(tuple(sorted(rng.sample(range(n),rng.randrange(1,n+1)))) for n in shape)
            cache=ProjectionCache(shape,terms);expected=direct(shape,terms,keep)
            self.assertEqual(expected,cache.restrict(keep,True))
            self.assertEqual(len(expected),cache.restrict(keep))

    def test_newly_equal_terms_cancel(self):
        cache=ProjectionCache((2,1,1),[(1,1,1),(3,1,1)])
        self.assertEqual([],cache.restrict(((0,),(0,),(0,)),True))

    def test_bad_coordinates_and_masks_are_rejected(self):
        for keep in [((0,0),(0,),(0,)),((1,0),(0,),(0,)),((2,),(0,),(0,)),
                     ((),(0,),(0,)),((True,),(0,),(0,))]:
            with self.assertRaises(ValueError):validate_keep((2,2,2),keep)
        with self.assertRaises(ValueError):ProjectionCache((2,2,2),[(16,1,1)])

    def test_family_counts_and_explicit_large_family_skip(self):
        rows=list(families((6,6,9),[(6,6,6)],20000))
        self.assertEqual(489,rows[0][2])
        self.assertEqual(84,rows[1][2])
        skipped=list(families((9,9,9),[(6,6,6)],20000))[-1]
        self.assertIsNone(skipped[1]);self.assertEqual(592704,skipped[2])

    def test_axis_stages_partition_the_default_neighborhood_exactly(self):
        shape=(2,3,2);full=tuple(tuple(range(n)) for n in shape)
        _,axes,count=next(families(shape,[],1000))
        default=set(itertools.product(*axes))-{full}
        self.assertEqual(len(default),count)
        for limit in (1,2):
            rows=list(families(shape,[],1000,limit));seen=[]
            for _,choices,declared in rows:
                views=list(itertools.product(*choices))
                self.assertEqual(len(views),declared);seen.extend(views)
            expected={keep for keep in default if sum(a!=b for a,b in zip(keep,full))<=limit}
            self.assertEqual(len(seen),len(set(seen)))
            self.assertEqual(set(seen),expected)
        thin=list(families((1,3,1),[],1000,2))
        self.assertEqual([(name,count) for name,_,count in thin],[('delete-axes-1',3)])
        for bad in (0,4,True,1.0):
            with self.assertRaises(ValueError):list(families(shape,[],1000,bad))

    def test_axis_stage_does_not_restrict_explicit_target_family(self):
        rows=list(families((3,3,3),[(1,1,1)],1000,1))
        name,axes,count=rows[-1]
        self.assertEqual((name,count),('target-1x1x1',27))
        self.assertEqual(len(list(itertools.product(*axes))),27)

    def test_staged_parent_scan_counts_and_exact_witnesses(self):
        shape=(2,3,2);terms=naive(shape);body=text(terms)
        with tempfile.TemporaryDirectory() as temporary:
            path=Path(temporary)/'parent.txt';path.write_bytes(body)
            entry=dict(id=0,path=str(path),shape=shape,rank=len(terms),
                sha256=hashlib.sha256(body).hexdigest(),identity=identity(shape,terms))
            for limit,views,targets in ((1,7,3),(2,23,6),(3,35,7)):
                row=scan_parent((entry,[],1000),max_deleted_axes=limit)
                self.assertEqual((row['views'],len(row['rows'])),(views,targets))
                self.assertEqual(sum(row['families'].values()),views)
                for output in row['rows']:
                    expected=direct(shape,terms,output['keep'])
                    self.assertEqual(output['terms'],expected)
                    self.assertEqual(output['rank'],len(expected))

    def test_targets_only_counts_guards_and_budget(self):
        rows=list(families((20,23,29),[(20,23,27)],20000,targets_only=True))
        self.assertEqual([(r[0],r[2]) for r in rows],[('target-20x23x27',406)])
        self.assertEqual(len(list(itertools.product(*rows[0][1]))),406)
        duplicates=list(families((3,3,3),[(2,3,3),(3,2,3)],1000,targets_only=True))
        self.assertEqual(len(duplicates),3)
        self.assertEqual(sum(r[2] for r in duplicates),9)
        skipped=list(families((9,9,9),[(6,6,6)],20000,targets_only=True))
        self.assertEqual(len(skipped),1)
        self.assertIsNone(skipped[0][1]);self.assertEqual(skipped[0][2],592704)
        for targets,flag in (([],True),([(2,3,3)],1),([(2,3,3)],None)):
            with self.assertRaises(ValueError):list(families((3,3,3),targets,1000,targets_only=flag))

    def test_targets_only_matches_named_family_minima_without_prefix_selection(self):
        shape=(3,3,4);terms=naive(shape);body=text(terms)
        with tempfile.TemporaryDirectory() as temporary:
            path=Path(temporary)/'parent.txt';path.write_bytes(body)
            entry=dict(id=0,path=str(path),shape=shape,rank=len(terms),
                sha256=hashlib.sha256(body).hexdigest(),identity=identity(shape,terms))
            job=(entry,[(3,3,2)],1000)
            normal=scan_parent(job,pair_order=(2,0,1))
            focused=scan_parent(job,pair_order=(2,0,1),targets_only=True)
            expected={tuple(row['shape']):row for row in normal['rows'] if sorted(row['shape'])==[2,3,3]}
            self.assertEqual({tuple(row['shape']):row for row in focused['rows']},expected)
            self.assertEqual(focused['views'],30)
            self.assertLess(focused['views'],normal['views'])
            self.assertTrue(all(name.startswith('target-') for name in focused['families']))
            for row in focused['rows']:
                self.assertEqual(row['terms'],direct(shape,terms,row['keep']))

    def test_targets_only_cli_and_independent_replay(self):
        from verify_coordinate_projections import verify
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary);shape=(3,3,3);terms=naive(shape);body=text(terms)
            path=root/'parent.txt';path.write_bytes(body)
            entry=dict(path=str(path),shape=shape,rank=len(terms),sha256=hashlib.sha256(body).hexdigest(),
                       identity=identity(shape,terms))
            (root/'inputs.json').write_text(json.dumps(dict(complete=True,parents=[entry])))
            (root/'prices.json').write_text(json.dumps(dict(complete=True,field='GF(2)',record_claim=False,
                model_shapes=[[2,3,3]],baseline_recipes=[dict(rank=18)])))
            output=root/'out'
            command=[sys.executable,'-B',str(Path(__file__).with_name('projection_composition_scan.py')),
                '--inputs',str(root/'inputs.json'),'--prices',str(root/'prices.json'),
                '--output',str(output),'--targets-only','--workers','1']
            failed=subprocess.run(command,capture_output=True,text=True,timeout=30)
            self.assertNotEqual(failed.returncode,0);self.assertFalse(output.exists())
            self.assertIn('requires at least one --target',failed.stderr)
            result=subprocess.run(command+['--target','2x3x3'],capture_output=True,text=True,timeout=30)
            self.assertEqual(result.returncode,0,result.stderr)
            report=json.loads((output/'report.json').read_bytes())
            self.assertTrue(report['limits']['targets_only']);self.assertEqual(report['views'],9)
            self.assertEqual(len(report['outputs']),3)
            self.assertTrue(verify(output,1)['complete'])


if __name__=='__main__':unittest.main()
