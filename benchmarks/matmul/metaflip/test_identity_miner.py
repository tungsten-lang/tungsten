import os
import sys
import unittest
from unittest import mock

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from identity_miner import (c3_symmetrize, identity_kind,
                            independent_zero_signature, mine_circuits,
                            mine_five_circuits, mine_small_circuits,
                            select_diverse_rows)  # noqa: E402
from mitm_surgery import tensor_xor  # noqa: E402


class IdentityMinerTest(unittest.TestCase):
    def test_finds_split_and_every_result_is_tensor_zero(self):
        # t(3,1,1) = t(1,1,1) + t(2,1,1)
        candidates = [(1, 1, 1), (2, 1, 1), (3, 1, 1),
                      (1, 2, 2), (2, 2, 2)]
        circuits = mine_circuits(candidates, 2, 2, 2)
        self.assertTrue(circuits)
        self.assertIn("split", {identity_kind(item) for item in circuits})
        for identity in circuits:
            self.assertEqual(0, tensor_xor(identity, 2, 2, 2))

    def test_c3_symmetrization_preserves_zero_signature(self):
        identity = ((1, 1, 1), (2, 1, 1), (3, 1, 1))
        sym = c3_symmetrize(identity, 2)
        self.assertTrue(sym)
        self.assertEqual(0, tensor_xor(sym, 4, 4, 4))

    def test_finds_primitive_five_way_factor_circuit(self):
        candidates = [(mask, 1, 1) for mask in (1, 2, 4, 8, 15)]
        circuits = mine_five_circuits(candidates, 4, 4, 4)
        self.assertEqual([tuple(candidates)], circuits)
        self.assertEqual("multi-split", identity_kind(circuits[0]))
        self.assertEqual(0, tensor_xor(circuits[0], 4, 4, 4))

    def test_bank_selection_round_robins_identity_families(self):
        def row(kind, term):
            return {"kind": kind, "output": [(term, 1, 1)], "distance": term,
                    "rank": term, "flip_pairs": 0, "density": term,
                    "identity": ((term, 1, 1),)}

        rows = [row("split", 1), row("split", 2),
                row("five-circuit", 3), row("rectangle", 4)]
        selected = select_diverse_rows(rows, 3)
        self.assertEqual(
            {"five-circuit", "split", "rectangle"},
            {item["kind"] for item in selected},
        )

    def test_independent_zero_check_does_not_trust_signature_generator(self):
        split = ((1, 1, 1), (2, 1, 1), (3, 1, 1))
        self.assertTrue(independent_zero_signature(split, 2, 2, 2))
        self.assertFalse(independent_zero_signature(((1, 1, 1),), 2, 2, 2))

        candidates = [(1, 1, 1), (1, 2, 1), (1, 1, 2)]
        # A broken/colliding primary signature function makes this triple look
        # zero.  The sparse reconstruction is a separate implementation and
        # must still reject it.
        with mock.patch("identity_miner.tensor_xor", return_value=0):
            self.assertEqual(
                [], mine_small_circuits(candidates, 2, 2, 2)
            )

    def test_out_of_range_candidate_masks_are_rejected(self):
        with self.assertRaisesRegex(ValueError, "outside"):
            mine_circuits([(4, 1, 1), (1, 1, 1)], 2, 2, 2)


if __name__ == "__main__":
    unittest.main()
