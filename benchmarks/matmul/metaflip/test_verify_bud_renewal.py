from collections import Counter
from contextlib import redirect_stdout
import hashlib
import io
import json
from pathlib import Path
import tempfile
import unittest

from verify_bud_renewal import elementary, factor_maps, expand_group, verify_products
from verify_representation_portfolio import parse_terms


def naive(shape):
    n,m,p=shape
    return [(1 << (i*m+j),1 << (j*p+k),1 << (i*p+k))
            for i in range(n) for j in range(m) for k in range(p)]


class BudRenewalChecks(unittest.TestCase):
    def test_generic_product_audit_and_rejections(self):
        name = 'matmul_2x2_rank7_strassen_gf2.txt'
        source = Path(__file__).resolve().parent/'fixtures'/name
        if not source.exists():
            source = Path(__file__).resolve().parents[3]/'bits/tungsten-metaflip/lib/metaflip/seeds/gf2'/name
        terms = parse_terms(source.read_bytes(), 7)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            def snapshot(name, shape, ts):
                raw = (str(len(ts))+'\n'+''.join(' '.join(map(str,t))+'\n' for t in ts)).encode()
                (root/name).write_bytes(raw)
                return dict(path=name,shape=shape,sha256=hashlib.sha256(raw).hexdigest())
            parent = snapshot('parent.txt',[1,1,1],[(1,1,1)])
            result = snapshot('result.txt',[2,2,2],terms)
            recipe = dict(schema=1,field='GF(2)',record_claim=False,parent=parent,result=result,
                          scale=[2,2,2],formula_rank=7,exact_rank=7,
                          groups=[dict(axis=None,indices=[0],leaf=result)])
            (root/'recipe.json').write_text(json.dumps(recipe))
            row = dict(recipe='recipe.json',target=[2,2,2],formula=7,rank=7,baseline=8,gain=1,
                       density=sum(v.bit_count() for t in terms for v in t))
            baseline = dict(complete=True,field='GF(2)',record_claim=False,
                            rows=[dict(shape=[2,2,2],augmented_rank=8)])
            with redirect_stdout(io.StringIO()):
                checked = verify_products(root,[row],baseline,1)
                self.assertEqual((1,2,8),(checked['products'],checked['tensors'],checked['terms']))
                for key in ('formula','rank','density','gain','baseline'):
                    bad = dict(row); bad[key] += 1
                    self.assertRaises(AssertionError,verify_products,root,[bad],baseline,1)
                self.assertRaises(AssertionError,verify_products,root,[row,row],baseline,1)
                recipe['groups'][0]['indices'] = [1]
                (root/'recipe.json').write_text(json.dumps(recipe))
                self.assertRaises(AssertionError,verify_products,root,[row],baseline,1)

    def test_all_shared_axes_and_scale_maps(self):
        shape=[2,2,2]
        parent=naive(shape)
        scale=[2,1,2]
        for axis in range(3):
            groups={}
            for i,t in enumerate(parent):
                groups.setdefault(t[axis],[]).append(i)
            terms=[]
            for ids in groups.values():
                group=dict(axis=axis,indices=ids)
                e=elementary(group)
                leaf_shape=[d*s for d,s in zip(e,scale)]
                terms.extend(expand_group(shape,parent,scale,group,leaf_shape,naive(leaf_shape)))
            self.assertEqual(sorted(terms),sorted(naive([4,2,4])))

    def test_general_elementary_group(self):
        shape=[2,2,2]
        parent=naive(shape)
        group=dict(elementary_shape=shape,indices=list(range(8)))
        terms=list(expand_group(shape,parent,[1,2,1],group,[2,4,2],naive([2,4,2])))
        self.assertEqual(sorted(terms),sorted(naive([2,4,2])))

    def test_noninjective_maps_and_invalid_groups(self):
        group=dict(axis=1,indices=[0,1])
        terms=list(expand_group([1,1,1],[(1,1,1),(1,1,1)],[1,1,1],group,[2,1,1],naive([2,1,1])))
        self.assertEqual([t for t,n in Counter(terms).items() if n%2],[])
        self.assertRaises(AssertionError,factor_maps,[(1,1,1),(1,2,1)],group)
        self.assertRaises(AssertionError,elementary,dict(axis=3,indices=[0]))
        self.assertRaises(AssertionError,elementary,dict(indices=[]))
        self.assertRaises(AssertionError,elementary,dict(elementary_shape=[2,1,1],indices=[0]))
        self.assertRaises(AssertionError,elementary,dict(elementary_shape=[1,1,1],axis=0,indices=[0]))


if __name__=='__main__':
    unittest.main()
