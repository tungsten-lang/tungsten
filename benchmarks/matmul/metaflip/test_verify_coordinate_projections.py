import hashlib
from itertools import product
import json
from pathlib import Path
import tempfile
import unittest

from verify_coordinate_projections import project_grid,verify


def naive(shape):
    n,m,p=shape
    return [(1<<(i*m+j),1<<(j*p+k),1<<(i*p+k)) for i,j,k in product(range(n),range(m),range(p))]


class VerifyCoordinateProjectionsTest(unittest.TestCase):
    def fixture(self,root):
        def save(name,terms):
            raw=(str(len(terms))+'\n'+''.join(' '.join(map(str,t))+'\n' for t in terms)).encode()
            (root/name).write_bytes(raw);return hashlib.sha256(raw).hexdigest()
        row=dict(shape=[1,2,1],rank=2,baseline=3,improves_local=True,parent=0,
            parent_path='parent.txt',parent_shape=[2,3,2],parent_sha256=save('parent.txt',naive((2,3,2))),
            path='result.txt',sha256=save('result.txt',naive((1,2,1))),keep=[[1],[0,2],[1]])
        report=dict(complete=True,field='GF(2)',record_claim=False,parents_done=1,selected_parents=1,
            rows=[dict(views=1)],views=1,outputs=[row])
        (root/'report.json').write_text(json.dumps(report));return report

    def test_full_replay_and_coordinate_mutation(self):
        with tempfile.TemporaryDirectory() as name:
            root=Path(name).resolve();report=self.fixture(root)
            result=verify(root,1);self.assertEqual(result['tensors'],2)
            self.assertEqual(result['improved_shapes'],[dict(shape=(1,1,2),rank=2)])
            report['outputs'][0]['keep'][1]=[0,0]
            (root/'report.json').write_text(json.dumps(report))
            with self.assertRaises(AssertionError):verify(root,1)

    def test_hash_and_false_improvement_mutations(self):
        with tempfile.TemporaryDirectory() as name:
            root=Path(name).resolve();report=self.fixture(root)
            report['outputs'][0]['sha256']='0'*64
            (root/'report.json').write_text(json.dumps(report))
            with self.assertRaises(AssertionError):verify(root,1)
            report=self.fixture(root);report['outputs'][0]['improves_local']=False
            (root/'report.json').write_text(json.dumps(report))
            with self.assertRaises(AssertionError):verify(root,1)

    def test_grid_drops_zero_factors_and_cancels_duplicates(self):
        self.assertEqual([],project_grid([2,1,1],[(1,1,1),(3,1,1),(2,1,2)],[[0],[0],[0]]))

    def test_distinct_same_shape_representations_are_not_merged(self):
        with tempfile.TemporaryDirectory() as name:
            root=Path(name).resolve();report=self.fixture(root)
            parent=naive((2,3,2))
            a=parent.index((8,2,8));b=parent.index((32,32,8))
            parent[a]=(8,34,8);parent[b]=(40,32,8)
            terms=project_grid([2,3,2],parent,[[1],[0,2],[1]])
            row=dict(report['outputs'][0])
            for prefix,values in [('parent',parent),('result',terms)]:
                raw=(str(len(values))+'\n'+''.join(' '.join(map(str,t))+'\n' for t in values)).encode()
                filename=prefix+'-other.txt';(root/filename).write_bytes(raw)
                row['parent_path' if prefix=='parent' else 'path']=filename
                row['parent_sha256' if prefix=='parent' else 'sha256']=hashlib.sha256(raw).hexdigest()
            report['outputs'].append(row);(root/'report.json').write_text(json.dumps(report))
            self.assertEqual(verify(root,1)['outputs'],2)
            report['outputs'].append(dict(row));(root/'report.json').write_text(json.dumps(report))
            with self.assertRaises(AssertionError):verify(root,1)


if __name__=='__main__':unittest.main()
