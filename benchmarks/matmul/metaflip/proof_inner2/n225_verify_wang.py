#!/usr/bin/env python3
"""Audit and replay the checked GF(2) rank-17 lower bound for ``<2,2,5>``."""

from __future__ import annotations

import argparse
import ast
import base64
import hashlib
import json
import platform
import re
import subprocess
import tempfile
from collections import Counter
from pathlib import Path


UPSTREAM_COMMIT = "efd22070269157e65aaf8d61a21da253a4000c61"
CERT_SHA256 = "b3e389f0006cac583e309a77c2c5600065d540a3d4e4c3022973a6ca89c6d9bb"
BTP_SHA256 = "eb7662a537d4e347a7a91218b36d2dc51b707a20c341a91fd1519f3dd1a6d52a"
EXPECTED_DIMS = (4, 10, 10)
EXPECTED_ORBITS_BY_DIM = {4: 1, 3: 2, 2: 5, 1: 2, 0: 1}
EXPECTED_ROOT_BOUND = 17


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _blocks(text: str) -> list[str]:
    result: list[str] = []
    active: list[str] | None = None
    for line in text.splitlines():
        if line == "constrained_tensors {":
            assert active is None
            active = [line]
        elif active is not None:
            active.append(line)
            if line == "}":
                result.append("\n".join(active))
                active = None
    assert active is None
    return result


def audit_artifacts(directory: Path) -> tuple[dict[str, object], bytes, bytes]:
    cert_path = directory / "cert_matrix_q02_n225_lb17.pb.txt"
    b64_path = directory / "cert_matrix_q02_n225_lb17.btp.b64"
    cert = cert_path.read_bytes()
    compact_b64 = b"".join(b64_path.read_bytes().split())
    archive = base64.b64decode(compact_b64, validate=True)
    assert sha256_bytes(cert) == CERT_SHA256
    assert sha256_bytes(archive) == BTP_SHA256
    assert archive.startswith(b"BTPARCH\x00")

    text = cert.decode("ascii")
    assert re.search(r'(?m)^problem_name: "matrix_q02_n225"$', text)
    assert re.search(r"(?m)^characteristic: 2$", text)
    assert re.search(r"(?m)^extension_degree: 1$", text)
    dims = tuple(
        int(re.search(rf"(?m)^{field}: (\d+)$", text).group(1))
        for field in ("na", "nb", "nc")
    )
    assert dims == EXPECTED_DIMS

    blocks = _blocks(text)
    assert len(blocks) == sum(EXPECTED_ORBITS_BY_DIM.values())
    indices: list[int] = []
    constraint_dims: list[int] = []
    for position, block in enumerate(blocks):
        match = re.search(r"(?m)^  index: (\d+)$", block)
        indices.append(0 if position == 0 and match is None else int(match.group(1)))
        constraints = re.search(r'(?m)^  constraints: (".*")$', block)
        if constraints is None:
            constraint_dims.append(0)
        else:
            decoded = ast.literal_eval(constraints.group(1)).encode("latin1")
            constraint_dims.append(len(decoded))
    assert indices == list(range(len(blocks)))
    assert dict(Counter(constraint_dims)) == EXPECTED_ORBITS_BY_DIM
    root = re.search(r"(?m)^  rank_lower_bound: (\d+)$", blocks[-1])
    assert root is not None and int(root.group(1)) == EXPECTED_ROOT_BOUND
    assert text.count("flatten_matrix_proof {") == 6
    assert text.count("forced_product_proof {") == 1
    assert text.count("degenerate_proof {") == 2
    assert text.count("backtracking_proof {") == 2
    return (
        {
            "schema": "wang-n225-lb17-audit-v1",
            "field": "GF(2)",
            "tensor": "<2,2,5>",
            "tensor_space_dimensions": list(dims),
            "orbit_count": len(blocks),
            "orbits_by_constraint_dimension": EXPECTED_ORBITS_BY_DIM,
            "verified_lower_bound_encoded": EXPECTED_ROOT_BOUND,
            "certificate_sha256": CERT_SHA256,
            "archive_sha256": BTP_SHA256,
        },
        cert,
        archive,
    )


def replay(upstream: Path, cert: bytes, archive: bytes) -> str:
    required = (
        upstream / "MODULE.bazel",
        upstream / "search/rank_lower_bound_main.cc",
        upstream / "verifier/verifier_main.cc",
    )
    assert all(path.is_file() for path in required)
    revision = subprocess.run(
        ["git", "rev-parse", "HEAD"], cwd=upstream, check=True,
        capture_output=True, text=True,
    ).stdout.strip()
    assert revision == UPSTREAM_COMMIT

    copt = (
        "--per_file_copt=.*_main\\.cc@-DCP_MATRIX,-DCP_P=2,-DCP_M=1,"
        "-DCP_N0=2,-DCP_N1=2,-DCP_N2=5"
    )
    command = ["bazel", "build", "--config=opt"]
    if platform.system() == "Darwin":
        command.extend(("--copt=-fno-lto", "--linkopt=-fno-lto"))
    command.extend((copt, "//verifier:verifier_main"))
    subprocess.run(command, cwd=upstream, check=True)

    with tempfile.TemporaryDirectory(prefix="n225-proof-") as temporary:
        base = Path(temporary) / "cert_matrix_q02_n225_lb17"
        cert_path = Path(str(base) + ".pb.txt")
        archive_path = Path(str(base) + ".btp")
        cert_path.write_bytes(cert)
        archive_path.write_bytes(archive)
        completed = subprocess.run(
            [str(upstream / "bazel-bin/verifier/verifier_main"), str(cert_path)],
            cwd=upstream, check=True, capture_output=True, text=True,
        )
    output = completed.stdout + completed.stderr
    assert "Verified. Rank lower bound for matrix_q02_n225 is 17." in output
    assert "UNCONSTRAINED TENSOR RANK LOWER BOUND: 17" in output
    assert "OK. Verified" in output
    return output


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--upstream", type=Path)
    parser.add_argument("--audit-only", action="store_true")
    args = parser.parse_args()
    directory = Path(__file__).resolve().parent
    audit, cert, archive = audit_artifacts(directory)
    if not args.audit_only:
        if args.upstream is None:
            parser.error("--upstream is required unless --audit-only is used")
        replay(args.upstream.resolve(), cert, archive)
        audit["upstream_commit"] = UPSTREAM_COMMIT
        audit["upstream_verifier"] = "PASS"
    print(json.dumps(audit, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
