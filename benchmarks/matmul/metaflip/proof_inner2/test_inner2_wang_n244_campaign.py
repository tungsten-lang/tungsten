#!/usr/bin/env python3

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from inner2_wang_n244_campaign import (
    EXPECTED_ORBITS,
    EXPECTED_ORBITS_BY_CONSTRAINT_DIM,
    UPSTREAM_COMMIT,
    audit_certificate,
    btp_path,
    build_command,
    problem_copt,
    search_command,
    snapshot_pair,
)


def synthetic_certificate(backtracking: bool = False) -> str:
    lines = [
        'problem_name: "matrix_q02_n244"',
        "characteristic: 2",
        "extension_degree: 1",
        "na: 8",
        "nb: 16",
        "nc: 8",
    ]
    dimensions = [
        dimension
        for dimension, count in EXPECTED_ORBITS_BY_CONSTRAINT_DIM.items()
        for _ in range(count)
    ]
    for index, dimension in enumerate(dimensions):
        lines.extend(("constrained_tensors {", f"  index: {index}"))
        if dimension:
            lines.append(f'  constraints: "{"x" * dimension}"')
        if index == EXPECTED_ORBITS - 1:
            lines.append("  rank_lower_bound: 23")
            if backtracking:
                lines.extend(
                    (
                        "  rank_lower_bound_proof {",
                        "    backtracking_proof {",
                        "      proof_size: 7",
                        "    }",
                        "  }",
                    )
                )
        lines.append("}")
    return "\n".join(lines) + "\n"


class WangN244CampaignTest(unittest.TestCase):
    def test_build_selection_and_default_are_pinned(self) -> None:
        self.assertIn("-DCP_N0=2,-DCP_N1=4,-DCP_N2=4", problem_copt())
        command = build_command(mac_no_lto=True)
        self.assertIn("--copt=-fno-lto", command)
        self.assertIn("//verifier:verifier_main", command)

    def test_forced_product_cap_does_not_disable_other_methods(self) -> None:
        command = search_command(
            Path("/upstream"),
            Path("/campaign.pb.txt"),
            step_limit=100_000,
            max_map_size=3_000_000,
            forced_product_log2=0,
            reset=False,
        )
        self.assertIn("--forced_product_max_iterations_log2=0", command)
        self.assertIn("--backtracking_step_limit=100000", command)
        self.assertNotIn("--basic_method=false", command)
        self.assertNotIn("--degenerate_method=false", command)

        uncapped = search_command(
            Path("/upstream"),
            Path("/campaign.pb.txt"),
            step_limit=0,
            max_map_size=1,
            forced_product_log2=None,
            reset=False,
        )
        self.assertFalse(any("forced_product" in item for item in uncapped))

    def test_complete_cover_and_backtracking_pair_are_required(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            certificate = Path(directory) / "campaign.pb.txt"
            # Match proto3's real text encoding, which omits ``index: 0``.
            certificate.write_text(
                synthetic_certificate(backtracking=True).replace("  index: 0\n", "", 1)
            )
            with self.assertRaisesRegex(ValueError, "archive is missing"):
                audit_certificate(certificate)
            btp_path(certificate).write_bytes(b"test archive")
            result = audit_certificate(certificate)
            self.assertEqual(result["orbit_count"], EXPECTED_ORBITS)
            self.assertEqual(result["root_lower_bound_in_certificate"], 23)
            self.assertEqual(result["rigorous_known_interval"], "23..26")

            incomplete = Path(directory) / "incomplete.pb.txt"
            incomplete.write_text(
                synthetic_certificate().replace(
                    f"constrained_tensors {{\n  index: {EXPECTED_ORBITS - 1}\n"
                    "  rank_lower_bound: 23\n}\n",
                    "",
                )
            )
            with self.assertRaisesRegex(ValueError, "incomplete orbit cover"):
                audit_certificate(incomplete)

    def test_snapshot_copies_certificate_and_archive_as_a_pair(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "live.pb.txt"
            source.write_text(synthetic_certificate(backtracking=True))
            btp_path(source).write_bytes(b"paired backtracking archive")
            destination = root / "snapshots/round-001.pb.txt"
            manifest = snapshot_pair(source, destination)
            self.assertEqual(destination.read_bytes(), source.read_bytes())
            self.assertEqual(
                btp_path(destination).read_bytes(), btp_path(source).read_bytes()
            )
            self.assertEqual(manifest["upstream_commit"], UPSTREAM_COMMIT)
            manifest_path = Path(manifest["manifest"])
            persisted = json.loads(manifest_path.read_text())
            self.assertEqual(
                persisted["certificate_sha256"], manifest["certificate_sha256"]
            )
            with self.assertRaisesRegex(FileExistsError, "refusing to overwrite"):
                snapshot_pair(source, destination)


if __name__ == "__main__":
    unittest.main()
