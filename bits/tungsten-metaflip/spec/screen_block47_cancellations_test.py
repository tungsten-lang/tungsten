import sys
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest


sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from screen_block47_cancellations import prioritize_formulas, screened_shapes  # noqa: E402


class ScreenBlock47PriorityTest(unittest.TestCase):
    def setUp(self):
        self.formulas = [dict(target=shape, formula_rank=rank, audited_gain=gain)
                         for shape, rank, gain in (
                             ('2x2x2', 7, 1),
                             ('2x3x3', 15, 2),
                             ('3x3x3', 23, 3))]

    def test_default_order_favors_propagation_over_direct_headroom(self):
        rows = prioritize_formulas(self.formulas, set(), {}, 3, maximum=6)
        self.assertEqual([(row['target'], row['priority_downstream']) for row in rows],
                         [('2x2x2', 26), ('2x3x3', 25), ('3x3x3', 9)])

    def test_materialized_seed_changes_remaining_counterfactuals(self):
        rows = prioritize_formulas(self.formulas, {'2x2x2'}, {'2x2x2': 6},
                                   3, maximum=6)
        self.assertEqual([(row['target'], row['priority_downstream']) for row in rows],
                         [('2x3x3', 16), ('3x3x3', 7)])
        self.assertEqual(prioritize_formulas(self.formulas,
                                             {row['target'] for row in self.formulas},
                                             {}, 3, maximum=6), [])

    def test_completed_no_gain_screen_is_not_revisited(self):
        with TemporaryDirectory() as temp:
            history = Path(temp) / 'screen-results.jsonl'
            self.assertEqual(screened_shapes(history), set())
            history.write_text('{"shape":"2x2x2","cancellations":0}\n')
            seen = screened_shapes(history)
            rows = prioritize_formulas(self.formulas, seen, {}, 3, maximum=6)
            self.assertEqual([row['target'] for row in rows],
                             ['2x3x3', '3x3x3'])


if __name__ == '__main__':
    unittest.main()
