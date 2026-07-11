import json
from pathlib import Path
import tempfile
import unittest

from bench_decomp import verify as independent_verify
from escape_portfolio import (
    DEFAULT_RECIPES,
    apply_move,
    build_portfolio,
    canonical,
    entries_from_schemes,
    enumerate_moves,
    read_bank,
    scheme_digest,
    verify_bank,
    write_bank,
)
from metaflip_proto2 import naive
from sym_escape import is_c3_closed


class EscapePortfolioTests(unittest.TestCase):
    def test_tracked_5x5_and_6x6_banks_are_exact(self):
        here = Path(__file__).resolve().parent
        expected = {
            "escape_bank_5x5_mixed.jsonl": (5, 48, 25),
            "escape_bank_6x6_mixed.jsonl": (6, 48, 25),
        }
        for name, (n, count, c3_count) in expected.items():
            with self.subTest(bank=name):
                header, entries = read_bank(str(here / name))
                reports = verify_bank(str(here / name))
                self.assertEqual(header["n"], n)
                self.assertEqual(len(entries), count)
                self.assertEqual(sum(report["c3"] for report in reports), c3_count)

    def test_mixed_bank_covers_every_single_and_depth_two_recipe(self):
        entries = build_portfolio(naive(3, 3, 3), 3, count=13, per_step=6)
        self.assertEqual(entries[0].recipe, ())
        self.assertEqual({entry.recipe for entry in entries[1:]}, set(DEFAULT_RECIPES))
        self.assertEqual(len({entry.scheme for entry in entries}), len(entries))
        for entry in entries:
            self.assertTrue(independent_verify(entry.scheme, 3, 3, 3))

        preserving = {"orbit-split", "polarize"}
        for entry in entries[1:]:
            if set(entry.recipe) <= preserving:
                self.assertTrue(is_c3_closed(entry.scheme, 3))
            if entry.recipe[-1] == "break":
                self.assertFalse(is_c3_closed(entry.scheme, 3))

    def test_depth_two_is_term_set_normalized(self):
        base = naive(3, 3, 3)
        first = enumerate_moves(base, 3, "split", limit=1)[0]
        escaped = apply_move(base, 3, first)
        # Every identity is an involution. Applying the identical split again
        # must canonicalize all the way back to the original term set.
        self.assertEqual(canonical(apply_move(escaped, 3, first)), canonical(base))
        entries = build_portfolio(base, 3, count=30, per_step=8)
        self.assertEqual(len({entry.scheme for entry in entries}), len(entries))

    def test_entries_from_schemes_is_a_public_miner_bridge(self):
        base = naive(3, 3, 3)
        move = enumerate_moves(base, 3, "split", limit=1)[0]
        candidate = apply_move(base, 3, move)
        entries = entries_from_schemes(
            base, [candidate, list(reversed(sorted(candidate))), base], 3, "circuit"
        )
        self.assertEqual(len(entries), 2)
        self.assertEqual(entries[0].recipe, ())
        self.assertEqual(entries[1].recipe, ("circuit",))
        self.assertEqual(entries[1].moves, ())
        self.assertEqual(entries[1].profile["distance"], 3)
        broken = set(candidate)
        broken.pop()
        with self.assertRaisesRegex(ValueError, "candidate scheme"):
            entries_from_schemes(base, [broken], 3)

    def test_jsonl_round_trip_and_independent_verifier(self):
        entries = build_portfolio(naive(3, 3, 3), 3, count=13, per_step=5)
        with tempfile.NamedTemporaryFile(mode="w+", suffix=".jsonl") as stream:
            write_bank(stream.name, entries, 3, "naive-3")
            header, loaded = read_bank(stream.name)
            self.assertEqual(header["count"], 13)
            self.assertTrue(all(entry.provenance for entry in loaded))
            self.assertEqual([entry.scheme for entry in loaded],
                             [entry.scheme for entry in entries])
            reports = verify_bank(stream.name)
            self.assertTrue(all(report["exact"] for report in reports))

            with open(stream.name) as source:
                rows = [json.loads(line) for line in source]
            rows[2]["terms"][0][0] ^= 1
            stream.seek(0)
            stream.truncate()
            for row in rows:
                stream.write(json.dumps(row) + "\n")
            stream.flush()
            with self.assertRaisesRegex(ValueError, "checksum mismatch"):
                read_bank(stream.name)

    def test_source_checksum_and_move_replay_are_verified(self):
        entries = build_portfolio(naive(3, 3, 3), 3, count=2, per_step=5)
        with tempfile.NamedTemporaryFile(mode="w+", suffix=".jsonl") as stream:
            write_bank(stream.name, entries, 3, "naive-3")
            with open(stream.name) as source:
                rows = [json.loads(line) for line in source]

            rows[0]["source_sha256"] = "0" * 64
            stream.seek(0)
            stream.truncate()
            for row in rows:
                stream.write(json.dumps(row) + "\n")
            stream.flush()
            with self.assertRaisesRegex(ValueError, "source checksum"):
                read_bank(stream.name)

            rows[0]["source_sha256"] = scheme_digest(entries[0].scheme)
            move = rows[2]["moves"][0]
            old_part = move["part"]
            old_factor = move["term"][move["axis"]]
            move["part"] = next(
                candidate for candidate in range(1, 1 << 9)
                if candidate not in (old_part, old_factor)
            )
            stream.seek(0)
            stream.truncate()
            for row in rows:
                stream.write(json.dumps(row) + "\n")
            stream.flush()
            with self.assertRaisesRegex(ValueError, "move provenance mismatch"):
                verify_bank(stream.name)

            # Relabeling a row as materialized must not provide an escape hatch
            # for nonempty, now-unchecked move documentation.
            rows[2]["provenance"]["mode"] = "materialized"
            rows[2]["provenance"]["replayable"] = False
            stream.seek(0)
            stream.truncate()
            for row in rows:
                stream.write(json.dumps(row) + "\n")
            stream.flush()
            with self.assertRaisesRegex(ValueError, "materialized provenance"):
                verify_bank(stream.name)

    def test_out_of_range_masks_cannot_pass_the_exactness_gate(self):
        base = naive(2, 2, 2)
        corrupted = list(base)
        u, v, w = corrupted[0]
        corrupted[0] = (u | 1 << 4, v, w)
        # bench_decomp's reconstruction ignores that high bit, which is why the
        # explicit mask-space gate is required ahead of it.
        self.assertTrue(independent_verify(corrupted, 2, 2, 2))
        with self.assertRaisesRegex(ValueError, "outside"):
            entries_from_schemes(corrupted, (), 2)


if __name__ == "__main__":
    unittest.main()
