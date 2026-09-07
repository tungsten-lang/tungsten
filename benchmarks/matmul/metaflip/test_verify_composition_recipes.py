import hashlib
from itertools import permutations,product
import json
from pathlib import Path
import tempfile
import unittest

from verify_composition_recipes import embed,kronecker,orient,verify


def naive(shape):
    n,m,p=shape
    return sorted((1<<(i*m+j),1<<(j*p+k),1<<(i*p+k)) for i,j,k in product(range(n),range(m),range(p)))


class VerifyCompositionRecipesTest(unittest.TestCase):
    def test_orientation_block_and_kronecker(self):
        for shape in permutations((2,3,4)):
            self.assertEqual(orient(naive((2,3,4)),(2,3,4),shape),naive(shape))
        self.assertEqual(sorted(kronecker(naive((2,2,2)),(2,2,2),naive((2,1,3)),(2,1,3))),naive((4,2,6)))
        terms=list(embed(naive((2,2,3)),(2,2,3),(2,5,3),(0,0,0)))
        terms+=list(embed(naive((2,3,3)),(2,3,3),(2,5,3),(0,2,0)))
        self.assertEqual(sorted(terms),naive((2,5,3)))

    def fixture(self,root,mixed=False):
        def save(name,shape,terms):
            raw=(str(len(terms))+'\n'+''.join(' '.join(map(str,t))+'\n' for t in terms)).encode()
            (root/name).write_bytes(raw)
            return dict(path=name,shape=shape,sha256=hashlib.sha256(raw).hexdigest())
        # Ordered by i,j,k so consecutive pairs share U.
        parent_terms=[(1<<(i*2+j),1<<(j*2+k),1<<(i*2+k)) for i,j,k in product(range(2),repeat=3)]
        parent=save('parent.txt',[2,2,2],parent_terms)
        leaf=save('leaf.txt',[2,1,2],naive((2,1,2)))
        result=save('result.txt',[4,2,2],naive((4,2,2)))
        recipe=dict(schema=1,field='GF(2)',record_claim=False,parent=parent,scale=[2,1,1],
                    groups=[dict(axis=0,indices=[2*i,2*i+1],leaf=leaf) for i in range(4)],
                    formula_rank=16,exact_rank=16,result=result)
        tensors=[parent,leaf,result]
        if mixed:
            other=save('other.txt',[4,1,1],naive((4,1,1)))
            single=save('single.txt',[2,1,1],naive((2,1,1)))
            tensors += [other,single]
            recipe['groups']=[dict(axis=0,indices=[0,1],leaf=leaf),
                              dict(axis=1,indices=[2,6],leaf=other)]
            recipe['groups'] += [dict(axis=None,indices=[i],leaf=single) for i in (3,4,5,7)]
        (root/'bud.json').write_text(json.dumps(recipe))
        report=dict(complete=True,field='GF(2)',record_claim=False,tensors=tensors,
                    recipes=[dict(kind='mixed_bud' if mixed else 'bud',shape=[4,2,2],rank=16,
                                  planned_rank=16,result=result,recipe='bud.json')],
                    materialized_targets=1,outputs=[dict(shape=[4,2,2],rank=16,baseline=17,result=result)])
        (root/'report.json').write_text(json.dumps(report))
        return recipe,report

    def test_replay_and_group_mutation(self):
        with tempfile.TemporaryDirectory() as name:
            root=Path(name).resolve();recipe,report=self.fixture(root)
            checked=verify(root,1)
            self.assertEqual(checked['tensors'],3)
            recipe['groups'][0]['indices']=[0,2]
            recipe['groups'][1]['indices']=[1,3]
            (root/'bud.json').write_text(json.dumps(recipe))
            with self.assertRaises(AssertionError):verify(root,1)

    def test_mixed_replay_and_axis_mutation(self):
        with tempfile.TemporaryDirectory() as name:
            root=Path(name).resolve();recipe,report=self.fixture(root,mixed=True)
            checked=verify(root,1)
            self.assertEqual(checked['tensors'],5)
            self.assertEqual(checked['bud_recipes'],1)
            recipe['groups'][1]['axis']=0
            (root/'bud.json').write_text(json.dumps(recipe))
            with self.assertRaises(AssertionError):verify(root,1)

    def test_grid_replay_and_schema_guard(self):
        with tempfile.TemporaryDirectory() as name:
            root=Path(name).resolve();recipe,report=self.fixture(root)
            recipe['schema']=2
            # Two 1x2x2 grids, each preserving the parent coordinate order.
            terms=naive((2,2,2))
            raw=(str(len(terms))+'\n'+''.join(' '.join(map(str,t))+'\n' for t in terms)).encode()
            (root/'grid-leaf.txt').write_bytes(raw)
            leaf=dict(path='grid-leaf.txt',shape=[2,2,2],sha256=hashlib.sha256(raw).hexdigest())
            recipe['groups']=[dict(elementary_shape=[1,2,2],indices=list(range(4*i,4*i+4)),leaf=leaf)
                              for i in range(2)]
            (root/'bud.json').write_text(json.dumps(recipe))
            checked=verify(root,1);self.assertEqual(checked['bud_recipes'],1)
            recipe['schema']=1;(root/'bud.json').write_text(json.dumps(recipe))
            with self.assertRaises(AssertionError):verify(root,1)
            recipe['schema']=2;recipe['groups'][0]['indices']=[0,2,1,3]
            (root/'bud.json').write_text(json.dumps(recipe))
            with self.assertRaises(AssertionError):verify(root,1)


if __name__=='__main__':unittest.main()
