import contextlib
import io
import json
import os
import sys
import tempfile
import unittest
from unittest import mock

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import hybrid_escape  # noqa: E402
from escape_portfolio import (PortfolioEntry, canonical, profile_scheme,
                              scheme_digest, verify_bank, write_bank)  # noqa: E402
from metaflip_proto2 import naive  # noqa: E402
from sym_escape import c3_orbit, fixed_terms, is_c3_closed  # noqa: E402


class HybridEscapeTests(unittest.TestCase):
    def test_base_is_the_default_control_and_slots_are_exact(self):
        base = canonical(naive(2, 2, 2))
        profile = profile_scheme(base, base, 2)
        entries = [
            PortfolioEntry(base, (), (), profile),
            PortfolioEntry(base, ("orbit-split",), (), profile),
            PortfolioEntry(base, ("split",), (), profile),
        ]
        reports = [
            {"id": 0, "c3": True},
            {"id": 1, "c3": True},
            {"id": 2, "c3": False},
        ]
        selected = hybrid_escape.select_c3_slots(reports, entries, 1)
        self.assertEqual(0, selected[0][0]["id"])
        selected = hybrid_escape.select_c3_slots(
            reports, entries, 1, include_base=False
        )
        self.assertEqual(1, selected[0][0]["id"])
        with self.assertRaisesRegex(ValueError, "slots must be positive"):
            hybrid_escape.select_c3_slots(reports, entries, 0)
        with self.assertRaisesRegex(ValueError, "only 2 C3 slots"):
            hybrid_escape.select_c3_slots(reports, entries, 3)

    def test_no_fixed_cube_falls_back_to_an_ordinary_split(self):
        scheme = set(c3_orbit((1, 2, 4), 2))
        self.assertTrue(is_c3_closed(scheme, 2))
        self.assertFalse(fixed_terms(scheme, 2))
        move, output = hybrid_escape.choose_symmetry_break(scheme, 2, "test")
        self.assertEqual("split", move.kind)
        self.assertFalse(is_c3_closed(output, 2))

    def test_metal_removes_a_stale_result_before_launch(self):
        base = canonical(naive(2, 2, 2))
        profile = profile_scheme(base, base, 2)
        entry = PortfolioEntry(base, (), (), profile)
        report = {"id": 0, "recipe": (), "exact": True, **profile}
        with tempfile.TemporaryDirectory() as directory:
            stale = os.path.join(directory, "metal_best.txt")
            with open(stale, "w") as stream:
                stream.write("8 24\n")
            with (
                mock.patch.object(hybrid_escape, "verify_bank", return_value=[report]),
                mock.patch.object(
                    hybrid_escape, "read_bank",
                    return_value=({"n": 2}, [entry]),
                ),
                mock.patch.object(
                    hybrid_escape, "gpu_cal2zone_gen",
                    return_value=("fn main() -> i32 { 0 }\n", 1),
                ),
                mock.patch.object(hybrid_escape, "compile_tungsten", return_value=0.0),
                mock.patch.object(hybrid_escape, "run_binary", return_value=("", 0.0)),
                contextlib.redirect_stdout(io.StringIO()),
            ):
                hybrid_escape.run_metal(
                    "unused.jsonl", directory, 0, 1, 16, 1
                )
            self.assertFalse(os.path.exists(stale))

    def test_staged_provenance_is_partial_but_replays_its_move_stage(self):
        base = canonical(naive(2, 2, 2))
        move, thawed = hybrid_escape.choose_symmetry_break(base, 2, "stage")
        base_digest = scheme_digest(base)
        thawed_digest = scheme_digest(thawed)
        provenance = {
            "mode": "staged",
            "replayable": False,
            "base_sha256": base_digest,
            "result_sha256": thawed_digest,
            "stages": [
                {
                    "kind": "c3-walk",
                    "input_sha256": base_digest,
                    "output_sha256": base_digest,
                    "replayable": False,
                },
                {
                    "kind": move.kind,
                    "input_sha256": base_digest,
                    "output_sha256": thawed_digest,
                    "replayable": True,
                    "move": move.as_json(),
                    "input_terms": [list(term) for term in base],
                },
                {
                    "kind": "full-walk",
                    "input_sha256": thawed_digest,
                    "output_sha256": thawed_digest,
                    "replayable": False,
                },
            ],
        }
        entries = [
            PortfolioEntry(base, (), (), profile_scheme(base, base, 2)),
            PortfolioEntry(
                canonical(thawed), ("c3-walk", move.kind, "full-walk"), (),
                profile_scheme(thawed, base, 2), provenance,
            ),
        ]
        with tempfile.NamedTemporaryFile(mode="w+", suffix=".jsonl") as stream:
            write_bank(stream.name, entries, 2, "naive-2")
            self.assertEqual(2, len(verify_bank(stream.name)))
            with open(stream.name) as source:
                rows = [json.loads(line) for line in source]
            stored = rows[2]["provenance"]
            self.assertFalse(stored["replayable"])
            stage_move = stored["stages"][1]["move"]
            old_part = stage_move["part"]
            old_factor = stage_move["term"][stage_move["axis"]]
            stage_move["part"] = next(
                candidate for candidate in range(1, 1 << 4)
                if candidate not in (old_part, old_factor)
            )
            stream.seek(0)
            stream.truncate()
            for row in rows:
                stream.write(json.dumps(row) + "\n")
            stream.flush()
            with self.assertRaisesRegex(ValueError, "replay mismatch"):
                verify_bank(stream.name)

            stage_move["part"] = old_part
            stored["stages"][1]["kind"] = (
                "split" if move.kind != "split" else "break"
            )
            stream.seek(0)
            stream.truncate()
            for row in rows:
                stream.write(json.dumps(row) + "\n")
            stream.flush()
            with self.assertRaisesRegex(ValueError, "kind mismatch"):
                verify_bank(stream.name)


if __name__ == "__main__":
    unittest.main()
