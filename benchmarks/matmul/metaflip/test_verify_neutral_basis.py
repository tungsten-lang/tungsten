import copy
import json
from pathlib import Path
import tempfile
import unittest

from verify_cofactor_mergers import compress_shared, refactor_shared
from verify_neutral_basis import digest, encode, replay_case, verify


class NeutralBasisReplayTest(unittest.TestCase):
    def test_replay_full_tensor_and_mutated_transition(self):
        with tempfile.TemporaryDirectory(prefix='metaflip-neutral-test-') as directory:
            root=Path(directory)
            initial=[(1<<j,1<<(j*2+k),1<<k) for j in range(2) for k in range(2)]
            initial += [initial[0],initial[0]]
            body=encode(initial);(root/'input.txt').write_bytes(body)
            entry=dict(path='input.txt',shape=[1,2,2],sha256=digest(body))
            initial=sorted(initial);terms=initial;steps=[];seen={digest(body)}
            for _ in range(2):
                for axis in range(3):
                    before=digest(encode(terms))
                    terms,changed=refactor_shared(terms,axis,max_bits=4,reverse_columns=True)
                    steps.append(dict(axis=axis,before_sha256=before,after_sha256=digest(encode(terms)),
                                      changed_groups=len(changed),rank=len(terms)))
                h=digest(encode(terms))
                if h in seen:break
                seen.add(h)
            terms,history=compress_shared(terms,max_bits=4)
            result=encode(terms);(root/'result.txt').write_bytes(result)
            row=dict(input=entry,order=[0,1,2],reverse_columns=True,max_bits=4,rank_before=6,
                     rank_after=4,steps=steps,compression=history,
                     result=dict(path='result.txt',shape=[1,2,2],sha256=digest(result)))
            self.assertEqual(replay_case((root,[row]))['steps'],len(steps))
            bad=copy.deepcopy(row);bad['steps'][0]['changed_groups']+=1
            self.assertRaises(AssertionError,replay_case,(root,[bad]))
            report=dict(complete=True,field='GF(2)',record_claim=False,canonical_archive_changed=False,
                        passes=2,planned_trials=12,completed_trials=1,all_planned_trials_completed=False,
                        rank_drop_trials=1,distinct_endpoints=1,rows=[row])
            (root/'report.json').write_text(json.dumps(report)+'\n')
            audit=verify(root,workers=1)
            self.assertEqual(audit['tensors'],2)
            self.assertEqual(audit['rank_drop_trials'],1)


if __name__=='__main__':
    unittest.main()
