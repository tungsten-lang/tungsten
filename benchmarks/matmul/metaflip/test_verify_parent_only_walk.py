import copy
import hashlib
import json
from itertools import combinations_with_replacement
from pathlib import Path
import tempfile
import unittest

from verify_parent_only_walk import cover_score, pure_score, verify
from rescore_parent_only_walk import bucket_signature, rescore


class ParentOnlyWalkTest(unittest.TestCase):
    def fixture(self, root):
        def put(name, value):
            path=root/name
            path.parent.mkdir(parents=True,exist_ok=True)
            path.write_text(json.dumps(value))
        terms=[(1<<(i*2+j),1<<(j*2+k),1<<(i*2+k)) for i in range(2) for j in range(2) for k in range(2)]
        body='8\n'+''.join(' '.join(map(str,t))+'\n' for t in terms)
        leaf='1\n1 1 1\n'
        digest=lambda text:hashlib.sha256(text.encode()).hexdigest()
        trial=dict(trial=0,score=8,parent=dict(rank=8,density=24,sha256=digest(body)),
                   end_parent=dict(rank=8,density=24,sha256=digest(body)))
        arms=[]
        for mode in ('walk','greedy','anneal'):
            directory=root/'study'/mode
            directory.mkdir(parents=True)
            (directory/'trial-0.txt').write_text(body)
            (directory/'end-0.txt').write_text(body)
            arms.append(dict(mode=mode,totals=dict(attempted='1',observations='1',held_terms='0'),
                products_materialized=False,trials=[copy.deepcopy(trial)],best_score=8,distinct_parents=1))
        (root/'study'/'parent.txt').write_text(body)
        (root/'study'/'leaf.txt').write_text(leaf)
        prices='10\n'+3*(' '.join(map(str,range(11)))+'\n')
        (root/'study'/'prices.txt').write_text(prices)
        put('study/price-leaves.json',[dict(axis=a,count=1,rank=1,snapshot=dict(
            path='leaf.txt',shape=[1,1,1],sha256=digest(leaf))) for a in range(3)])
        put('study/report.json',dict(field='GF(2)',record_claim=False,binary_sha256='pinned',
            options=dict(parents_only=True,scale='1x1x1',debt=2,trials=1,chunks=1,steps=1,observe_every=1),
            parent=dict(path='parent.txt',shape=[2,2,2],sha256=digest(body)),price_sha256=digest(prices),
            initial_score=8,arms=arms))
        put('report.json',dict(complete=True,field='GF(2)',record_claim=False,binary_sha256='pinned',
            rows=[dict(report='study/report.json')],attempts_per_policy=1,total_attempts=3))

    def test_exact_full_tensor_and_price_replay(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);self.fixture(root)
            result=verify(root,1)
            self.assertEqual((result['attempts'],result['winners'],result['unique_tensors']),(3,3,2))
            self.assertFalse(result['products_materialized'])

    def test_score_mutation_and_tensor_mutation_fail_closed(self):
        for kind in ('score','tensor','price','accounting'):
            with self.subTest(kind=kind),tempfile.TemporaryDirectory() as d:
                root=Path(d);self.fixture(root)
                path=root/'study/report.json';report=json.loads(path.read_text())
                if kind=='score':
                    report['arms'][0]['trials'][0]['score']=7
                elif kind=='tensor':
                    (root/'study/walk/trial-0.txt').write_text('8\n1 1 2\n')
                elif kind=='price':
                    (root/'study/prices.txt').write_text('10\n0 0\n')
                else:
                    report['arms'][0]['totals']['attempted']='2'
                path.write_text(json.dumps(report))
                with self.assertRaises(AssertionError):
                    verify(root,1)

    def test_pure_axis_minimum(self):
        terms=[(1,1,1),(1,2,2),(2,4,4)]
        self.assertEqual(pure_score(terms,[[0,5,7,9],[0,4,8,12],[0,6,12,18]]),12)

    def test_fixed_cover_falls_back_when_a_held_term_is_absent(self):
        terms=[(1,1,1),(1,2,2),(2,4,4)]
        prices=[[0,5,7,9],[0,4,8,12],[0,6,12,18]]
        self.assertEqual(cover_score(terms,prices,terms[:2],3),7)
        self.assertEqual(cover_score(terms,prices,terms[:2],20),12)
        self.assertEqual(cover_score(terms,prices,[(8,8,8)],1),12)
        self.assertEqual(cover_score(terms,prices,terms,3),3)

    def test_fixed_elementary_leaf_and_factor_map_are_independently_checked(self):
        for mutation in (None,'cost','shape','leaf'):
            with self.subTest(mutation=mutation),tempfile.TemporaryDirectory() as d:
                root=Path(d);self.fixture(root)
                base=root/'study'
                report=json.loads((base/'report.json').read_text())
                terms=[(1<<(i*2+j),1<<(j*2+k),1<<(i*2+k)) for i in range(2) for j in range(2) for k in range(2)]
                held=terms[:4]
                text=lambda rows:str(len(rows))+'\n'+''.join(' '.join(map(str,t))+'\n' for t in rows)
                h=text(held);(base/'holdout.txt').write_text(h)
                leaf=[(1<<j,1<<(j*2+k),1<<k) for j in range(2) for k in range(2)]
                if mutation=='leaf':leaf[0]=(leaf[0][0],leaf[0][1],2)
                l=text(leaf);(base/'held-leaf.txt').write_text(l)
                report['holdout']=dict(terms=held,path='holdout.txt',sha256=hashlib.sha256(h.encode()).hexdigest(),
                    elementary_shape=[1,2,2],cost=4,leaf=dict(path='held-leaf.txt',shape=[1,2,2],
                        sha256=hashlib.sha256(l.encode()).hexdigest()))
                report['options']['holdout_shape']=[1,2,2]
                report['score_kind']='fixed-elementary-group-or-pure-axis-upper-bound'
                for arm in report['arms']:
                    arm['totals']['held_terms']='4';arm['totals']['held_cost']='4'
                if mutation=='cost':report['holdout']['cost']=3
                if mutation=='shape':report['holdout']['elementary_shape']=[2,2,1]
                (base/'report.json').write_text(json.dumps(report))
                if mutation is None:
                    self.assertEqual(verify(root,1)['unique_tensors'],3)
                else:
                    error = ValueError if mutation=='leaf' else AssertionError
                    with self.assertRaises(error):verify(root,1)

    def test_weighted_portfolio_replays_each_leaf_before_combining_costs(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);self.fixture(root)
            base=root/'study';report=json.loads((base/'report.json').read_text())
            cases=[dict(scale=[1,1,1],weight=2),dict(scale=[1,1,2],weight=3)]
            raw=json.dumps(cases).encode();(base/'portfolio.json').write_bytes(raw)
            report['portfolio']=cases
            report['portfolio_source_path']='portfolio.json'
            report['portfolio_source_sha256']=hashlib.sha256(raw).hexdigest()
            report['score_kind']='weighted-common-axis-portfolio-cost-not-a-tensor-rank'
            report['options'].pop('scale')
            second='2\n1 1 1\n1 2 2\n';(base/'leaf2.txt').write_text(second)
            leaves=json.loads((base/'price-leaves.json').read_text())
            leaves += [dict(case=1,axis=a,count=1,rank=2,snapshot=dict(path='leaf2.txt',shape=[1,1,2],
                sha256=hashlib.sha256(second.encode()).hexdigest())) for a in range(3)]
            (base/'price-leaves.json').write_text(json.dumps(leaves))
            prices='10\n'+3*(' '.join(str(8*i) for i in range(11))+'\n')
            (base/'prices.txt').write_text(prices)
            report['price_sha256']=hashlib.sha256(prices.encode()).hexdigest()
            report['initial_score']=64
            for arm in report['arms']:
                arm['best_score']=64;arm['trials'][0]['score']=64
            (base/'report.json').write_text(json.dumps(report))
            result=verify(root,1)
            self.assertEqual(result['unique_tensors'],3)
            self.assertFalse(result['products_materialized'])
            report['portfolio'][0]['weight']=1
            (base/'report.json').write_text(json.dumps(report))
            with self.assertRaises(AssertionError):verify(root,1)

    def test_read_only_signature_cache_and_scale_census(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);self.fixture(root)
            audit=verify(root,1)
            (root/'independent-audit.json').write_text(json.dumps(audit))
            price_path=root/'price-grid.json'
            price_path.write_text(json.dumps(dict(complete=True,field='GF(2)',record_claim=False,
                rows=[dict(shape=list(s),rank=s[0]*s[1]*s[2])
                      for s in combinations_with_replacement(range(2,5),3)])))
            output=root/'rescore.json'
            result=rescore(root,price_path,output,maximum=4)
            self.assertEqual((result['parent_states'],result['price_signatures'],result['parent_scale_checks']),(1,1,7))
            self.assertEqual((result['targets'],result['improved_targets']),(3,0))
            with self.assertRaises(AssertionError):
                rescore(root,price_path,output,maximum=4)
        # Equal signatures may reuse prices but do not assert equal tensors.
        left=[(1,1,1),(1,2,2)];right=[(4,8,8),(4,16,16)]
        self.assertEqual(bucket_signature(left),bucket_signature(right))
        self.assertNotEqual(left,right)


if __name__=='__main__':
    unittest.main()
