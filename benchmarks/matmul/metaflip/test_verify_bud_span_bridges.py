import copy
import unittest
from verify_bud_span_bridges import replay


class ReplayTest(unittest.TestCase):
    def test_exact_cross_group_replay_and_malformed_witnesses(self):
        source=[(1,1,1),(1,2,2),(2,3,4),(2,4,8)]
        row=dict(shared_axis=0,aligned_axis=1,target=3,groups=[[0,1],[2,3]],masks=[3,1],
                 intersection_dimension=1,word=[[0,1,1,0],[1,0,0,2]])
        self.assertEqual(replay(source,row),[(1,2,3),(1,3,5),(2,4,8),(3,3,4)])
        for key,value in [('target',2),('masks',[1,1]),('intersection_dimension',2),
                          ('word',[[0,1,1,0],[0,1,0,2]]),('groups',[[0],[2,3]])]:
            bad=copy.deepcopy(row);bad[key]=value
            with self.assertRaises(AssertionError):replay(source,bad)
        self.assertEqual(source,[(1,1,1),(1,2,2),(2,3,4),(2,4,8)])


if __name__=='__main__':unittest.main()
