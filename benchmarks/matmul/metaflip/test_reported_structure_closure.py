import copy
import unittest

from check_reported_structure_closure import templates
from verify_recursive_portfolio import solver


class ReportedStructureChecks(unittest.TestCase):
    def fixture(self):
        return {'8x8x24':{'s1':{'dimension':[2,2,12],'rank':42,
            'structure':'<1,1,4> + 2<1,1,1> + 3<1,1,2> + 6<1,1,5>'},
            's2':{'dimension':[4,4,2]}}}

    def test_known_template_can_eliminate_a_false_novelty_claim(self):
        edges,count=templates(self.fixture())
        self.assertEqual(count,1)
        prices={(2,4,4):26,(4,4,4):47,(4,4,8):94,(4,4,10):115,(8,8,24):985}
        self.assertGreater(solver(prices)((8,8,24)),977)
        self.assertLessEqual(solver(prices,edges)((8,8,24)),977)

    def test_rejects_bad_reported_geometry(self):
        bad=copy.deepcopy(self.fixture())
        bad['8x8x24']['s1']['rank']=41
        with self.assertRaises(AssertionError):
            templates(bad)
        bad=copy.deepcopy(self.fixture())
        bad['8x8x24']['s2']['dimension']=[4,4,3]
        with self.assertRaises(AssertionError):
            templates(bad)

    def test_rejects_cycles_and_nonpositive_costs(self):
        for count,leaf in [(1,(2,2,2)),(1,(2,2,3)),(0,(1,1,1)),(-1,(1,1,1))]:
            with self.assertRaises(AssertionError):
                solver({}, {(2,2,2):[((count,leaf),)]})


if __name__=='__main__':
    unittest.main()
