#!/usr/bin/env python3
"""Independent structural replay and machine-readable n324 proof summary."""

from __future__ import annotations

import argparse
import hashlib
import json
import random
from pathlib import Path

from fixed_a_shards import (EXPECTED_CASES, audit_residual_cases, left_b,
                            left_c, right_b, right_c)
from n324_common import (RANK_ONE_A, apply_a, expand_certificate, gl_packed,
                         group_perms, inverse_square, rank32, rank_rows,
                         span_elements)


EXPECTED_CERT_SHA256 = "b1926bac436850d6c43c1c909a4bdfd9c84a073ed14b6359635944dfd694316d"
EXPECTED_BTP_SHA256 = "875f7ce52ad6afc9ffbab70269cbaca25cdf205174da2c8e2edec2af5aff2e4d"
ORBIT29_OPEN17 = (11, 17, 19, 24, 25, 26, 27, 33, 35,
                  41, 43, 49, 50, 51, 56, 57, 59)
ROOT_OPEN19 = (2, 4, 5, 8, 10, 12, 15, 16, 17, 20,
               21, 32, 34, 40, 42, 48, 51, 60, 63)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify_capacity_witnesses(lb_by_subspace: dict[tuple[int, ...], int],
                              orbit_by_subspace: dict[tuple[int, ...], int]) -> None:
    base = (6,)
    for subspace, bound in lb_by_subspace.items():
        if rank_rows(subspace + base) != len(subspace):
            continue
        qpoints = {min(x, x ^ 6) for x in span_elements(subspace)
                   if min(x, x ^ 6)}
        assert len(set(ORBIT29_OPEN17) & qpoints) <= 18 - bound
    assert len(ORBIT29_OPEN17) == 17

    root = set(ROOT_OPEN19)
    for subspace, published_bound in lb_by_subspace.items():
        bound = published_bound + int(orbit_by_subspace[subspace] == 29)
        points = set(span_elements(subspace)) - {0}
        assert len(root & points) <= 19 - bound
    assert len(ROOT_OPEN19) == 19


def tensor(terms: list[tuple[int, int, int]]) -> list[int]:
    result = [0] * (6 * 8 * 12)
    for a, b, c in terms:
        for ai in range(6):
            if not ((a >> ai) & 1):
                continue
            for bj in range(8):
                if not ((b >> bj) & 1):
                    continue
                for ck in range(12):
                    if (c >> ck) & 1:
                        result[(ai * 8 + bj) * 12 + ck] ^= 1
    return result


def verify_isotropy(samples: int) -> None:
    gl3, gl2, gl4 = gl_packed(3), gl_packed(2), gl_packed(4)
    naive = [(1 << (i * 2 + j), 1 << (j * 4 + k), 1 << (k * 3 + i))
             for i in range(3) for j in range(2) for k in range(4)]
    target = tensor(naive)
    rng = random.Random(324)
    for _ in range(samples):
        left, right, middle = (rng.choice(gl3), rng.choice(gl2),
                               rng.choice(gl4))
        left_inverse = inverse_square(left, 3)
        right_inverse = inverse_square(right, 2)
        middle_inverse = inverse_square(middle, 4)
        transformed = []
        for a, b, c in naive:
            transformed.append((
                apply_a(a, left, right),
                right_b(left_b(right_inverse, b), middle),
                right_c(left_c(middle_inverse, c), left_inverse),
            ))
        assert tensor(transformed) == target


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("certificate", type=Path)
    parser.add_argument("--btp", type=Path)
    parser.add_argument("--summary", type=Path)
    parser.add_argument("--audit-residual", action="store_true")
    parser.add_argument("--isotropy-samples", type=int, default=100)
    args = parser.parse_args()

    cert_hash = sha256(args.certificate)
    assert cert_hash == EXPECTED_CERT_SHA256
    btp_hash = None
    if args.btp is not None:
        btp_hash = sha256(args.btp)
        assert btp_hash == EXPECTED_BTP_SHA256
    parsed, lb_by_subspace, orbit_by_subspace = expand_certificate(
        args.certificate)
    assert parsed[28] == ((1,), 18)
    assert parsed[29] == ((6,), 18)
    assert parsed[30] == ((), 19)
    orbit_sizes = [sum(index == orbit for index in orbit_by_subspace.values())
                   for orbit in range(31)]
    assert orbit_sizes[28:] == [21, 42, 1]

    perms = group_perms()
    pair_representatives = {
        min(tuple(sorted((p[a], p[b]))) for p in perms)
        for i, a in enumerate(RANK_ONE_A) for b in RANK_ONE_A[i + 1:]
    }
    assert pair_representatives == {(1, 2), (1, 4), (1, 8)}
    assert tuple(x for x in range(1, 64) if rank32(x) == 1) == RANK_ONE_A
    assert set(ROOT_OPEN19).issubset(RANK_ONE_A)
    verify_capacity_witnesses(lb_by_subspace, orbit_by_subspace)
    verify_isotropy(args.isotropy_samples)
    if args.audit_residual:
        audit_residual_cases()

    residual_counts = {
        f"{missing[0]}_{missing[1]}": sum(map(len, by_b.values()))
        for (missing, _), by_b in EXPECTED_CASES.items()
    }
    quotient_manifest_path = Path(__file__).with_name(
        "n324_quotient_rank_manifest.json"
    )
    quotient_manifest = json.loads(quotient_manifest_path.read_text())
    assert quotient_manifest["schema"] == "n324-quotient-rank-proof-manifest-v1"
    assert len(quotient_manifest["cases"]) == 6
    assert all(
        item["veripb"] == "VERIFIED UNSATISFIABLE; no warning or error"
        for item in quotient_manifest["cases"]
    )
    summary = {
        "status": {
            "orbit29_lb19": "proved_and_formally_checked",
            "global_n324_lb20": "proved_by_six_quotient_rank_unsat_proofs",
            "global_n324_rank": 20,
        },
        "published": {
            "prover_commit": "efd22070269157e65aaf8d61a21da253a4000c61",
            "certificate_sha256": cert_hash,
            "btp_sha256": btp_hash or EXPECTED_BTP_SHA256,
        },
        "finite_geometry": {
            "group_order": 1008,
            "certificate_orbits": len(parsed),
            "covered_subspaces": len(lb_by_subspace),
            "root_rank1_A_orbit_size": orbit_sizes[28],
            "root_rank2_A_orbit_size": orbit_sizes[29],
        },
        "orbit29_capacity": {
            "base": [6],
            "published_lb": 18,
            "proved_lb": 19,
            "quotient_points": 31,
            "containing_subspaces": 374,
            "maximum_open_size": 17,
            "open_size_17_witness": list(ORBIT29_OPEN17),
            "cnf_sha256": "96d7b3b591b7e15edd79fa4e5c5b9a98efdee49da0aeaecaa1802b19fd922de4",
            "xlrup_sha256": "a5ce61305607af51d84da7bc4336048e2c79148e2adb031c0a458aff05fe3932",
        },
        "global_reduction": {
            "root_open_size_19_witness": list(ROOT_OPEN19),
            "rank1_A_points": list(RANK_ONE_A),
            "missing_pair_orbit_representatives": [[1, 2], [1, 4], [1, 8]],
            "aggregate_cases": 9,
            "fixed_pair_shards": sum(residual_counts.values()),
            "residual_pair_orbits": residual_counts,
        },
        "quotient_rank_closure": {
            "symmetry_shards": 6,
            "verified_unsat_shards": 6,
            "manifest_sha256": sha256(quotient_manifest_path),
        },
    }
    rendered = json.dumps(summary, indent=2, sort_keys=True) + "\n"
    if args.summary is not None:
        args.summary.write_text(rendered)
    print(rendered, end="")


if __name__ == "__main__":
    main()
