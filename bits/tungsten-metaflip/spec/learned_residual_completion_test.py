#!/usr/bin/env python3
"""Focused mathematical, leakage, budget, and model-contract checks."""
import importlib.util
import itertools
import json
from pathlib import Path
import random
import tempfile
import unittest

PATH = Path(__file__).resolve().parents[1] / "tools/learned_residual_completion.py"
spec = importlib.util.spec_from_file_location("learned_completion", PATH)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


class LearnedCompletionTest(unittest.TestCase):
    def test_elimination_coordinates(self):
        original, pivots = m.basis([6, 3, 5, 8])
        self.assertEqual(len(original), 3)
        for mask in range(8):
            value = m.xor(original[i] for i in m.bits(mask))
            self.assertEqual(m.coordinates(value, pivots), mask)
        with self.assertRaises(ValueError):
            m.coordinates(1, pivots)

    def test_compression_lift_roundtrip_from_tensor_only(self):
        rng = random.Random(91)
        for _ in range(100):
            dims = (6, 7, 5)
            terms = [tuple(rng.randrange(1, 1 << d) for d in dims) for _ in range(rng.randrange(1, 6))]
            target = m.tensor(terms, dims)
            core, cdims, bases = m.compress_residual(target, dims)
            unit_terms = [(1 << (i // (cdims[1]*cdims[2])),
                           1 << (i // cdims[2] % cdims[1]), 1 << (i % cdims[2])) for i in m.bits(core)]
            self.assertEqual(m.tensor(m.lift(unit_terms, bases), dims), target)
            self.assertEqual(cdims, m.flatten_ranks(target, dims))
        self.assertEqual(m.compress_residual(0, dims), (0, (0, 0, 0), [[], [], []]))

    def test_features_invariant_under_basis_and_mode_changes(self):
        rng = random.Random(13)
        for _ in range(40):
            dims = (3, 4, 2)
            terms = [tuple(rng.randrange(1, 1 << d) for d in dims) for _ in range(5)]
            before = m.features(m.tensor(terms, dims), dims)
            # Elementary GF(2) transvections on all three mode bases.
            changed = [tuple(v ^ ((v & 1) << 1) for v in t) for t in terms]
            self.assertEqual(m.features(m.tensor(changed, dims), dims), before)
            perm = (2, 0, 1)
            changed = [tuple(t[a] for a in perm) for t in terms]
            shape = tuple(dims[a] for a in perm)
            self.assertEqual(m.features(m.tensor(changed, shape), shape), before)

    def test_all_two_by_two_by_two_residuals_are_exact_or_bounded(self):
        dims = (2, 2, 2)
        for target in range(256):
            answer, stats = m.ResidualCompletionArm("popcount", beam=8, budget=10000).complete(target, dims, 3, 1)
            self.assertIsNotNone(answer, (target, stats))
            self.assertEqual(m.tensor(answer, dims), target)
            self.assertLessEqual(len(answer), 3)

    def test_budget_and_lower_bound_are_not_universal_failure_claims(self):
        dims = (3, 3, 3)
        target = m.tensor([(1, 1, 1), (2, 2, 2), (4, 4, 4)], dims)
        answer, stats = m.ResidualCompletionArm("popcount", budget=1).complete(target, dims, 3, 2)
        self.assertIsNone(answer)
        self.assertEqual(stats["status"], "work_budget")
        self.assertEqual(stats["xor_checks"], 1)
        answer, stats = m.ResidualCompletionArm("popcount").complete(target, dims, 2, 2)
        self.assertIsNone(answer)
        self.assertEqual(stats["status"], "flattening_lower_bound")
        self.assertEqual(stats["xor_checks"], 0)

    def test_full_gate_rejects_corruption(self):
        shape = (2, 2, 2)
        path = m.ROOT / "lib/metaflip/seeds/gf2/matmul_2x2_rank7_strassen_gf2.txt"
        parent = m.read_seed(path, shape)
        self.assertEqual(m.splice(parent, [0, 1], parent[:2], shape), m.canonical(parent))
        with self.assertRaises(ValueError):
            m.splice(parent, [0, 1], parent[:1], shape)
        with self.assertRaises(ValueError):
            m.splice(parent, [0, 0], parent[:2], shape)
        with self.assertRaises(ValueError):
            m.verify_full(parent[:-1], shape)

    def test_declared_real_seed_formats(self):
        cases = m.real_cases(1, 3)
        self.assertEqual(len(cases), 5)
        for case in cases:
            self.assertEqual(len(case["selected"]), 3)
            self.assertEqual(len(case["source_sha256"]), 64)

    def test_invalid_residual_contract(self):
        arm = m.ResidualCompletionArm("popcount")
        for target, dims, cap in [(-1, (2, 2, 2), 2), (1, (-1, 2, 2), 2),
                                  (1, (2, 2), 2), (1, (0, 2, 2), 2),
                                  (256, (2, 2, 2), 2), (1, (2, 2, 2), 7)]:
            with self.assertRaises(ValueError):
                arm.complete(target, dims, cap, 1)

    def test_training_roundtrip_and_schema(self):
        rows = m.synthetic_dataset(1200, 11)
        for row in rows:
            core, dims, _ = m.compress_residual(m.tensor(row["recipe"], row["original_dims"]), row["original_dims"])
            self.assertEqual((core, dims), (int(row["target"]), row["dims"]))
            self.assertGreaterEqual(row["label"], max(m.flatten_ranks(core, dims)))
        model, metadata, test = m.train_model(rows, 10, 11)
        self.assertGreater(len(test), 10)
        values = [rows[i]["features"] for i in test[:5]]
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "model.json"
            model.save(path, metadata)
            copy = m.ValueModel.load(path)
            self.assertEqual(model.predict(values).tolist(), copy.predict(values).tolist())
            data = json.loads(path.read_text())
            data["features"] = list(reversed(data["features"]))
            path.write_text(json.dumps(data))
            with self.assertRaises(ValueError):
                m.ValueModel.load(path)


if __name__ == "__main__":
    unittest.main()
