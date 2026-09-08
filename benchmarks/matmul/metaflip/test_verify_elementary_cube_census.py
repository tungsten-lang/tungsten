import copy
import gzip
import hashlib
from itertools import product
import json
from pathlib import Path
import tempfile
import unittest

from verify_elementary_cube_census import verify


class ElementaryCubeCensusTest(unittest.TestCase):
    def fixture(self,root):
        terms = [(1<<(i*2+j),1<<(j*2+k),1<<(i*2+k)) for i,j,k in product(range(2),repeat=3)]
        body = '8\n'+''.join(' '.join(map(str,t))+'\n' for t in terms)
        identity = '2x2x2\n'+''.join(' '.join(map(str,t))+'\n' for t in sorted(terms))
        parent = dict(shape=[2,2,2],rank=8,path='old/seed.txt',identity=hashlib.sha256(identity.encode()).hexdigest(),
                      sha256=hashlib.sha256(body.encode()).hexdigest())
        common = dict(complete=True,field='GF(2)',record_claim=False)
        inputs = dict(common,parents=[parent])
        plan = dict(common,model_shapes=[[2,2,2]],baseline_recipes=[dict(rank=8)])
        saved = dict(parent,index=0,source_text=body)
        row = dict(parent,index=0,local_rank=8,formula_bound_if_cube=7,improves_local_rank=True,complete=True,
                   groups=[dict(elementary_shape=[2,2,2],indices=list(range(8)))])
        report = dict(common,requested_parents=1,all_parents_attempted=True,all_detections_complete=True,rows=[row])
        self.write(root,inputs,plan,saved,report)
        return inputs,plan,saved,report

    def write(self,root,inputs,plan,saved,report):
        for name,value in [('inputs.json',inputs),('plan.json',plan)]:
            (root/name).write_text(json.dumps(value))
        with gzip.open(root/'corpus.ndjson.gz','wt') as stream:
            stream.write(json.dumps(saved)+'\n')
        report['corpus'] = dict(path='corpus.ndjson.gz',sha256=hashlib.sha256((root/'corpus.ndjson.gz').read_bytes()).hexdigest())
        report['source_sha256'] = {'/old/inputs.json':hashlib.sha256((root/'inputs.json').read_bytes()).hexdigest(),
                                  '/old/report.json':hashlib.sha256((root/'plan.json').read_bytes()).hexdigest()}
        (root/'report.json').write_text(json.dumps(report))

    def check(self,root):
        leaf = Path(__file__).resolve().parents[3]/'bits/tungsten-metaflip/lib/metaflip/seeds/gf2/matmul_2x2_rank7_strassen_gf2.txt'
        return verify(root,root/'inputs.json',root/'plan.json',leaf)

    def test_source_and_actual_replacement_rank_replay(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); self.fixture(root)
            r=self.check(root)
            self.assertEqual((r['parents'],r['groups']), (1,1))
            self.assertEqual(r['candidates'][0]['actual_rank'],7)
            self.assertEqual(r['improved_shapes'],[(2,2,2)])
            self.assertFalse(r['search_absence_certified'])

    def test_mutated_maps_and_accounting_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); inputs,plan,saved,original=self.fixture(root)
            for mutation in ('overlap','order','rank','false_flag','count','source','identity','duplicate'):
                with self.subTest(mutation=mutation):
                    r=copy.deepcopy(original); row=r['rows'][0]
                    if mutation=='overlap': row['groups'][0]['indices'][-1]=0
                    elif mutation=='order': row['groups'][0]['indices'][1:3]=[2,1]
                    elif mutation=='rank': row['formula_bound_if_cube']=6
                    elif mutation=='false_flag': row['improves_local_rank']=False
                    elif mutation=='count': r['requested_parents']=2
                    elif mutation=='source': row['rank']=7
                    elif mutation=='identity': row['identity']='0'*64
                    elif mutation=='duplicate': row['groups'].append(copy.deepcopy(row['groups'][0]))
                    self.write(root,inputs,plan,saved,r)
                    with self.assertRaises((AssertionError,ValueError)):
                        self.check(root)

    def test_incomplete_detection_is_not_upgraded(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); inputs,plan,saved,r=self.fixture(root)
            r['rows'][0]['complete']=False; r['all_detections_complete']=False
            self.write(root,inputs,plan,saved,r)
            result=self.check(root)
            self.assertTrue(result['complete'])
            self.assertFalse(result['search_absence_certified'])

    def test_invalid_tensor_rejected_after_all_hashes_are_rebound(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); inputs,plan,saved,r=self.fixture(root)
            lines=saved['source_text'].splitlines()
            term=list(map(int,lines[1].split())); term[0]^=2
            lines[1]=' '.join(map(str,term))
            body='\n'.join(lines)+'\n'
            terms=sorted(tuple(map(int,line.split())) for line in lines[1:])
            identity='2x2x2\n'+''.join(' '.join(map(str,t))+'\n' for t in terms)
            for entry in (inputs['parents'][0],saved,r['rows'][0]):
                entry['sha256']=hashlib.sha256(body.encode()).hexdigest()
                entry['identity']=hashlib.sha256(identity.encode()).hexdigest()
            saved['source_text']=body
            self.write(root,inputs,plan,saved,r)
            with self.assertRaises(ValueError):
                self.check(root)


if __name__=='__main__':
    unittest.main()
