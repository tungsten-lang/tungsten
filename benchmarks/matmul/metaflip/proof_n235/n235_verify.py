#!/usr/bin/env python3
"""Audit and replay the checked GF(2) ``<2,3,5>`` rank-23 proof."""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import platform
import subprocess
import tempfile
from pathlib import Path

from n235_capacity import (
    audit_rank_one_counting,
    audit_rank_two_multiset_model,
    build_rank_two_multiset_cnf,
)
from n235_common import expand_certificate


UPSTREAM_COMMIT = "efd22070269157e65aaf8d61a21da253a4000c61"
CERT_SHA256 = "71ecdab1fed0ef331757806b707ad844cac04f057368250a4ea7a5e3920cd2eb"
BTP_SHA256 = "0688a309bcd26c6ab746870eb6f5cbfb84444d243b01360d5782ee37c5d8439f"
CNF_SHA256 = "453ba646318ff0d336afe7b338ef3dab0cf062bdf1e4ff1e0ce52436f1ec8e65"
XLRUP_SHA256 = "ccc860e7aa18a4754869375f0f6f4bc65e0bb1666b65b1ad6b94b7e50336340e"
UPPER_SCHEMES = (
    (
        "matmul_2x3x5_rank25_d160_fleet_gf2.txt",
        "48f567ce264b996cb6f1d9ce88296e1830b8a4261830ca3d03fc0a04b04e7be7",
        160,
        "FlipFleet density leader from the four-door rectangular campaign",
    ),
    (
        "matmul_2x3x5_rank25_d170_fleet_gf2.txt",
        "31abed1367f41e93a4d35f11cd295b05bc494394793714627d42fff2a26b31df",
        170,
        "FlipFleet density continuation from the public d173 scheme",
    ),
    (
        "matmul_2x3x5_rank25_d173_alphatensor_zt_mod2_gf2.txt",
        "45f7b780775158cbcac4adaef9ba91c0d3010648c780218981873b11c868f182",
        173,
        "FastMatrixMultiplication AlphaTensor ZT scheme reduced modulo 2",
    ),
    (
        "matmul_2x3x5_rank25_d210_fleet_gf2.txt",
        "7b6faf104b1bb0520ef3a266846b0ae087fb965628e1318e9c2a11a85a325613",
        210,
        "independent FlipFleet rediscovery seed 235107",
    ),
    (
        "matmul_2x3x5_rank25_d278_fleet_gf2.txt",
        "8d6ea17a0c13686ffd282df65165bd54ce9178f2a7f4fdb2a2d59933dafb4cac",
        278,
        "independent FlipFleet rediscovery seed 235110",
    ),
)


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def popcount(value: int) -> int:
    """Portable nonnegative-mask popcount (including Apple Python 3.9)."""
    assert value >= 0
    return bin(value).count("1")


def artifact_paths(directory: Path) -> dict[str, Path]:
    return {
        "certificate": directory / "cert_matrix_q02_n235_lb22.pb.txt",
        "archive_b64": directory / "cert_matrix_q02_n235_lb22.btp.b64",
        "cnf": directory / "n235_rank2_multiset_r21.cnf",
        "xlrup": directory / "n235_rank2_multiset_r21.xlrup",
    }


def audit_upper_schemes(directory: Path) -> list[dict[str, object]]:
    """Independently reconstruct every checked rank-25 restart door."""
    target = {
        (i, j, j, k, i, k)
        for i in range(2)
        for j in range(3)
        for k in range(5)
    }
    audited: list[dict[str, object]] = []
    term_sets: list[set[tuple[int, int, int]]] = []
    for filename, expected_hash, expected_density, provenance in UPPER_SCHEMES:
        path = directory.parent / filename
        data = path.read_bytes()
        assert sha256_bytes(data) == expected_hash
        lines = [
            line.strip()
            for line in data.decode("ascii").splitlines()
            if line.strip() and not line.lstrip().startswith("#")
        ]
        assert lines and lines[0] == "25"
        terms = [tuple(map(int, line.split())) for line in lines[1:]]
        assert len(terms) == 25
        assert all(len(term) == 3 for term in terms)
        assert len(set(terms)) == 25
        assert all(0 < u < (1 << 6) for u, _, _ in terms)
        assert all(0 < v < (1 << 15) for _, v, _ in terms)
        assert all(0 < w < (1 << 10) for _, _, w in terms)
        density = sum(popcount(value) for term in terms for value in term)
        assert density == expected_density

        actual: set[tuple[int, int, int, int, int, int]] = set()
        for u, v, w in terms:
            for ab in range(6):
                if not ((u >> ab) & 1):
                    continue
                i, j = divmod(ab, 3)
                for bc in range(15):
                    if not ((v >> bc) & 1):
                        continue
                    jj, k = divmod(bc, 5)
                    for ac in range(10):
                        if not ((w >> ac) & 1):
                            continue
                        ii, kk = divmod(ac, 5)
                        coefficient = (i, j, jj, k, ii, kk)
                        if coefficient in actual:
                            actual.remove(coefficient)
                        else:
                            actual.add(coefficient)
        assert actual == target
        term_sets.append(set(terms))
        audited.append(
            {
                "path": filename,
                "rank": len(terms),
                "density": density,
                "sha256": expected_hash,
                "provenance": provenance,
            }
        )
    common_terms = {
        (i, j): len(term_sets[i].intersection(term_sets[j]))
        for i in range(len(term_sets))
        for j in range(i + 1, len(term_sets))
    }
    assert common_terms[0, 1] == 3
    assert common_terms[0, 2] == 3
    assert common_terms[1, 2] == 23
    assert all(
        count == 0
        for pair, count in common_terms.items()
        if pair not in ((0, 1), (0, 2), (1, 2))
    )
    return audited


def audit_local(directory: Path) -> tuple[dict[str, object], bytes]:
    paths = artifact_paths(directory)
    certificate_bytes = paths["certificate"].read_bytes()
    assert sha256_bytes(certificate_bytes) == CERT_SHA256
    archive = base64.b64decode(
        b"".join(paths["archive_b64"].read_bytes().split()), validate=True
    )
    assert sha256_bytes(archive) == BTP_SHA256
    assert archive.startswith(b"BTPARCH\x00")

    parsed, lower_bounds, orbit_map = expand_certificate(paths["certificate"])
    assert len(parsed) == 31
    assert len(lower_bounds) == 2825
    assert len(orbit_map) == 2825
    assert parsed[28] == ((1,), 20)
    assert parsed[29] == ((6,), 21)
    assert parsed[30] == ((), 22)

    generated_cnf, capacity = build_rank_two_multiset_cnf(paths["certificate"])
    checked_cnf = paths["cnf"].read_bytes()
    assert generated_cnf == checked_cnf
    assert sha256_bytes(checked_cnf) == CNF_SHA256
    xlrup = paths["xlrup"].read_bytes()
    assert sha256_bytes(xlrup) == XLRUP_SHA256
    counting = audit_rank_one_counting(paths["certificate"])
    rank23_rank_one_probe = audit_rank_one_counting(
        paths["certificate"], hypothetical_rank=23
    )
    rank23_capacity_probe = audit_rank_two_multiset_model(
        paths["certificate"], directory / "n235_rank2_multiset_r22_model.json"
    )
    upper_schemes = audit_upper_schemes(directory)

    text = certificate_bytes.decode("ascii")
    assert text.count("flatten_matrix_proof {") == 11
    assert text.count("forced_product_proof {") == 2
    assert text.count("degenerate_proof {") == 7
    assert text.count("backtracking_proof {") == 11
    return (
        {
            "schema": "n235-rank23-proof-audit-v2",
            "field": "GF(2)",
            "tensor": "<2,3,5>",
            "checked_lower_bound": 23,
            "checked_upper_bound": 25,
            "wang_root_lower_bound": 22,
            "orbit_count": len(parsed),
            "expanded_subspace_count": len(lower_bounds),
            "certificate_sha256": CERT_SHA256,
            "archive_sha256": BTP_SHA256,
            "capacity_cnf_sha256": CNF_SHA256,
            "capacity_xlrup_sha256": XLRUP_SHA256,
            "capacity": capacity,
            "rank_one_counting": counting,
            "rank23_rank_one_probe": rank23_rank_one_probe,
            "rank23_capacity_probe": rank23_capacity_probe,
            "upper_schemes": upper_schemes,
            "upper_scheme_common_terms": {
                "d160:d170": 3,
                "d160:d173": 3,
                "d170:d173": 23,
                "pairs_with_d210_or_d278": 0,
            },
            "proof_logic": [
                "Wang certificate excludes rank <= 21",
                "checked multiset capacity raises every rank-two one-factor constraint from 21 to 22",
                "a rank-22 scheme therefore has only rank-one first factors",
                "21 certified incidence rows count those 22 factors three times but allow only 42 total incidences",
            ],
        },
        archive,
    )


def replay_capacity_checker(checker: Path, directory: Path) -> str:
    paths = artifact_paths(directory)
    completed = subprocess.run(
        [str(checker), str(paths["cnf"]), str(paths["xlrup"])],
        check=True,
        capture_output=True,
        text=True,
    )
    output = completed.stdout + completed.stderr
    lines = [line.strip() for line in output.splitlines() if line.strip()]
    assert lines == ["s VERIFIED UNSAT"]
    return output


def replay_wang(upstream: Path, certificate: bytes, archive: bytes) -> str:
    required = (
        upstream / "MODULE.bazel",
        upstream / "search/rank_lower_bound_main.cc",
        upstream / "verifier/verifier_main.cc",
    )
    assert all(path.is_file() for path in required)
    revision = subprocess.run(
        ["git", "rev-parse", "HEAD"],
        cwd=upstream,
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()
    assert revision == UPSTREAM_COMMIT

    copt = (
        "--per_file_copt=.*_main\\.cc@-DCP_MATRIX,-DCP_P=2,-DCP_M=1,"
        "-DCP_N0=2,-DCP_N1=3,-DCP_N2=5"
    )
    command = ["bazel", "build", "--config=opt"]
    if platform.system() == "Darwin":
        command.extend(("--copt=-fno-lto", "--linkopt=-fno-lto"))
    command.extend((copt, "//verifier:verifier_main"))
    subprocess.run(command, cwd=upstream, check=True)

    with tempfile.TemporaryDirectory(prefix="n235-proof-") as temporary:
        base = Path(temporary) / "cert_matrix_q02_n235_lb22"
        certificate_path = Path(str(base) + ".pb.txt")
        archive_path = Path(str(base) + ".btp")
        certificate_path.write_bytes(certificate)
        archive_path.write_bytes(archive)
        completed = subprocess.run(
            [str(upstream / "bazel-bin/verifier/verifier_main"), str(certificate_path)],
            cwd=upstream,
            check=True,
            capture_output=True,
            text=True,
        )
    output = completed.stdout + completed.stderr
    assert "Verified. Rank lower bound for matrix_q02_n235 is 22." in output
    assert "UNCONSTRAINED TENSOR RANK LOWER BOUND: 22" in output
    assert "OK. Verified" in output
    return output


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--checker", type=Path)
    parser.add_argument("--upstream", type=Path)
    parser.add_argument("--audit-only", action="store_true")
    args = parser.parse_args()
    directory = Path(__file__).resolve().parent
    audit, archive = audit_local(directory)
    if not args.audit_only:
        if args.checker is None:
            parser.error("--checker is required unless --audit-only is used")
        replay_capacity_checker(args.checker.resolve(), directory)
        audit["capacity_checked_replay"] = "PASS"
        if args.upstream is not None:
            certificate = artifact_paths(directory)["certificate"].read_bytes()
            replay_wang(args.upstream.resolve(), certificate, archive)
            audit["wang_upstream_commit"] = UPSTREAM_COMMIT
            audit["wang_verifier_replay"] = "PASS"
    print(json.dumps(audit, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
