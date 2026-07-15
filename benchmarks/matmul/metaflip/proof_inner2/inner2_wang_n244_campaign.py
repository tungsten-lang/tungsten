#!/usr/bin/env python3
"""Drive and audit Wang's pinned GF(2) ``<2,4,4>`` CPU campaign.

This wrapper deliberately does not modify Wang's prover or verifier.  It pins
the audited upstream revision, selects the matrix dimensions at compile time,
keeps the live protobuf and backtracking archive together, and checks the
86-orbit cover before accepting a campaign artifact.

The recommended campaign passes ``--forced_product_max_iterations_log2=0``.
In the pinned upstream this skips every forced-product enumeration with more
than one candidate before entering the enumeration loop.  It does *not*
disable flattening, degenerate reduction, backtracking, or their independent
verification.  The upstream binary's default remains 24 when it is invoked
without that flag.
"""

from __future__ import annotations

import argparse
import ast
import hashlib
import json
import os
import platform
import re
import shlex
import shutil
import subprocess
from collections import Counter
from pathlib import Path
from typing import Sequence


UPSTREAM_COMMIT = "efd22070269157e65aaf8d61a21da253a4000c61"
PROBLEM_NAME = "matrix_q02_n244"
EXPECTED_ORBITS = 86
EXPECTED_DIMS = (8, 16, 8)
EXPECTED_ORBITS_BY_CONSTRAINT_DIM = {
    8: 1,
    7: 2,
    6: 8,
    5: 17,
    4: 30,
    3: 17,
    2: 8,
    1: 2,
    0: 1,
}
BUILD_TARGETS = (
    "//search:orbit_enumerator_main",
    "//search:rank_lower_bound_main",
    "//verifier:verifier_main",
)
ORBIT_FILENAME = f"orbits_{PROBLEM_NAME}.pb.txt"
CAMPAIGN_FILENAME = f"campaign_{PROBLEM_NAME}.pb.txt"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        while block := source.read(1 << 20):
            digest.update(block)
    return digest.hexdigest()


def btp_path(certificate: Path) -> Path:
    value = str(certificate)
    if value.endswith(".pb.txt"):
        return Path(value[:-7] + ".btp")
    if value.endswith(".pb"):
        return Path(value[:-3] + ".btp")
    raise ValueError(f"certificate must end in .pb.txt or .pb: {certificate}")


def problem_copt() -> str:
    definitions = (
        "CP_MATRIX",
        "CP_P=2",
        "CP_M=1",
        "CP_N0=2",
        "CP_N1=4",
        "CP_N2=4",
    )
    return "--per_file_copt=.*_main\\.cc@" + ",".join(
        f"-D{definition}" for definition in definitions
    )


def build_command(mac_no_lto: bool) -> list[str]:
    command = ["bazel", "build", "--config=opt"]
    if mac_no_lto:
        command.extend(("--copt=-fno-lto", "--linkopt=-fno-lto"))
    command.append(problem_copt())
    command.extend(BUILD_TARGETS)
    return command


def enumerate_command(upstream: Path, output: Path) -> list[str]:
    return [
        str(upstream / "bazel-bin/search/orbit_enumerator_main"),
        f"--output_path={output}",
    ]


def search_command(
    upstream: Path,
    certificate: Path,
    step_limit: int,
    max_map_size: int,
    forced_product_log2: int | None,
    reset: bool,
    dim_min: int | None = None,
    dim_max: int | None = None,
) -> list[str]:
    command = [
        str(upstream / "bazel-bin/search/rank_lower_bound_main"),
        str(certificate),
        f"--output_path={certificate}",
        f"--backtracking_step_limit={step_limit}",
        f"--backtracking_max_map_size={max_map_size}",
    ]
    if forced_product_log2 is not None:
        command.append(
            f"--forced_product_max_iterations_log2={forced_product_log2}"
        )
    if reset:
        command.append("--ignore_rank_lower_bound=true")
    if dim_min is not None:
        command.append(f"--dim_min={dim_min}")
    if dim_max is not None:
        command.append(f"--dim_max={dim_max}")
    return command


def verify_command(upstream: Path, certificate: Path) -> list[str]:
    return [
        str(upstream / "bazel-bin/verifier/verifier_main"),
        str(certificate),
    ]


def _metadata_integer(text: str, field: str) -> int:
    match = re.search(rf"(?m)^{re.escape(field)}: (-?\d+)$", text)
    if match is None:
        raise ValueError(f"missing protobuf field {field}")
    return int(match.group(1))


def _metadata_string(text: str, field: str) -> str:
    match = re.search(rf'(?m)^{re.escape(field)}: "([^"]+)"$', text)
    if match is None:
        raise ValueError(f"missing protobuf field {field}")
    return match.group(1)


def _top_level_tensor_blocks(text: str) -> list[str]:
    blocks: list[str] = []
    active: list[str] | None = None
    for line in text.splitlines():
        if line == "constrained_tensors {":
            if active is not None:
                raise ValueError("nested top-level constrained_tensors block")
            active = [line]
        elif active is not None:
            active.append(line)
            if line == "}":
                blocks.append("\n".join(active))
                active = None
    if active is not None:
        raise ValueError("unterminated constrained_tensors block")
    return blocks


def audit_certificate(
    certificate: Path, require_complete_cover: bool = True
) -> dict[str, object]:
    if not str(certificate).endswith(".pb.txt"):
        raise ValueError("the campaign audit currently requires a text .pb.txt certificate")
    text = certificate.read_text()
    if _metadata_string(text, "problem_name") != PROBLEM_NAME:
        raise ValueError(f"wrong problem in {certificate}; expected {PROBLEM_NAME}")
    if _metadata_integer(text, "characteristic") != 2:
        raise ValueError("campaign is GF(2), but characteristic is not two")
    if _metadata_integer(text, "extension_degree") != 1:
        raise ValueError("campaign requires the prime field GF(2)")
    dims = tuple(_metadata_integer(text, field) for field in ("na", "nb", "nc"))
    if dims != EXPECTED_DIMS:
        raise ValueError(f"wrong tensor-space dimensions: {dims} != {EXPECTED_DIMS}")

    blocks = _top_level_tensor_blocks(text)
    if require_complete_cover and len(blocks) != EXPECTED_ORBITS:
        raise ValueError(
            f"incomplete orbit cover: {len(blocks)} != {EXPECTED_ORBITS}"
        )
    indices = []
    constraint_dims = []
    for position, block in enumerate(blocks):
        match = re.search(r"(?m)^  index: (\d+)$", block)
        # Proto3 text omits scalar fields holding their zero default, so the
        # first dense orbit normally has no explicit ``index: 0`` line.
        if match is None and position == 0:
            indices.append(0)
        elif match is None:
            raise ValueError("constrained tensor has no dense index")
        else:
            indices.append(int(match.group(1)))
        constraints_match = re.search(r'(?m)^  constraints: (".*")$', block)
        if constraints_match is None:
            constraint_dims.append(0)
        else:
            decoded = ast.literal_eval(constraints_match.group(1))
            if not isinstance(decoded, str):
                raise ValueError("constraints field did not decode as a byte string")
            constraint_dims.append(len(decoded.encode("latin1")))
    if indices != list(range(len(blocks))):
        raise ValueError("constrained-tensor indices are not dense and ordered")
    dimension_counts = dict(sorted(Counter(constraint_dims).items(), reverse=True))
    if require_complete_cover and dimension_counts != EXPECTED_ORBITS_BY_CONSTRAINT_DIM:
        raise ValueError(
            "wrong orbit distribution by constraint dimension: "
            f"{dimension_counts} != {EXPECTED_ORBITS_BY_CONSTRAINT_DIM}"
        )

    root_lower_bound: int | None = None
    if blocks:
        root_match = re.search(r"(?m)^  rank_lower_bound: (-?\d+)$", blocks[-1])
        if root_match is not None:
            root_lower_bound = int(root_match.group(1))
    backtracking_proofs = text.count("    backtracking_proof {")
    archive = btp_path(certificate)
    if backtracking_proofs and not archive.is_file():
        raise ValueError(
            f"certificate references {backtracking_proofs} backtracking proofs "
            f"but its archive is missing: {archive}"
        )

    result: dict[str, object] = {
        "schema": "wang-n244-campaign-audit-v1",
        "upstream_commit": UPSTREAM_COMMIT,
        "problem": PROBLEM_NAME,
        "orbit_count": len(blocks),
        "orbit_cover_complete": len(blocks) == EXPECTED_ORBITS,
        "orbits_by_constraint_dimension": dimension_counts,
        "root_lower_bound_in_certificate": root_lower_bound,
        "certificate": str(certificate),
        "certificate_sha256": sha256(certificate),
        "backtracking_proof_count": backtracking_proofs,
        "archive_present": archive.is_file(),
        "rigorous_known_interval": "23..26",
    }
    if archive.is_file():
        result["archive"] = str(archive)
        result["archive_sha256"] = sha256(archive)
    return result


def validate_upstream(upstream: Path) -> None:
    required = (
        upstream / "MODULE.bazel",
        upstream / "search/rank_lower_bound_main.cc",
        upstream / "search/rank_lower_bound_computer.h",
        upstream / "verifier/verifier_main.cc",
    )
    missing = [str(path) for path in required if not path.is_file()]
    if missing:
        raise ValueError("not a Wang upstream checkout; missing: " + ", ".join(missing))
    revision = subprocess.run(
        ["git", "rev-parse", "HEAD"],
        cwd=upstream,
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()
    if revision != UPSTREAM_COMMIT:
        raise ValueError(f"upstream revision {revision} != pinned {UPSTREAM_COMMIT}")
    main_source = (upstream / "search/rank_lower_bound_main.cc").read_text()
    expected_flag = "DEFINE_int32(forced_product_max_iterations_log2, 24,"
    if expected_flag not in main_source:
        raise ValueError("pinned forced-product cap/default was not found")


def run(command: Sequence[str], cwd: Path, dry_run: bool) -> None:
    print("+ " + shlex.join(command), flush=True)
    if not dry_run:
        subprocess.run(command, cwd=cwd, check=True)


def _atomic_copy(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_name(destination.name + ".tmp")
    shutil.copy2(source, temporary)
    os.replace(temporary, destination)


def snapshot_pair(source: Path, destination: Path) -> dict[str, object]:
    audit = audit_certificate(source)
    source_archive = btp_path(source)
    destination_archive = btp_path(destination)
    manifest_path = Path(str(destination) + ".snapshot.json")
    occupied = [
        str(path)
        for path in (destination, destination_archive, manifest_path)
        if path.exists()
    ]
    if occupied:
        raise FileExistsError("refusing to overwrite snapshot files: " + ", ".join(occupied))
    _atomic_copy(source, destination)
    if source_archive.is_file():
        _atomic_copy(source_archive, destination_archive)
    elif destination_archive.exists():
        destination_archive.unlink()
    copied = audit_certificate(destination)
    manifest = {
        "schema": "wang-n244-checkpoint-v1",
        "upstream_commit": UPSTREAM_COMMIT,
        "source_certificate_sha256": audit["certificate_sha256"],
        "certificate": destination.name,
        "certificate_sha256": copied["certificate_sha256"],
        "archive": destination_archive.name if destination_archive.is_file() else None,
        "archive_sha256": copied.get("archive_sha256"),
        "orbit_count": copied["orbit_count"],
        "root_lower_bound_in_certificate": copied["root_lower_bound_in_certificate"],
        "rigorous_known_interval": "23..26",
    }
    temporary = manifest_path.with_name(manifest_path.name + ".tmp")
    temporary.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    os.replace(temporary, manifest_path)
    manifest["manifest"] = str(manifest_path)
    return manifest


def print_json(value: object) -> None:
    print(json.dumps(value, indent=2, sort_keys=True))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--upstream",
        type=Path,
        default=Path(os.environ["WANG_TENSOR_RANK"])
        if "WANG_TENSOR_RANK" in os.environ
        else None,
        help="pinned wcgbg/tensor-rank-lower-bound checkout",
    )
    parser.add_argument(
        "--work-dir",
        type=Path,
        default=Path("/tmp/wang-n244"),
        help="campaign output directory (default: /tmp/wang-n244)",
    )
    parser.add_argument(
        "--mac-no-lto",
        action=argparse.BooleanOptionalAction,
        default=platform.system() == "Darwin",
        help="use the Apple ld64.lld -fno-lto workaround (default on macOS)",
    )
    parser.add_argument("--dry-run", action="store_true")
    subparsers = parser.add_subparsers(dest="action", required=True)
    subparsers.add_parser("build", help="build the three pinned CPU binaries")
    subparsers.add_parser("enumerate", help="enumerate and audit the 86 orbits")

    search_parser = subparsers.add_parser(
        "search", help="start or resume the in-place checked campaign"
    )
    search_parser.add_argument("--step-limit", type=int, default=100_000)
    search_parser.add_argument("--max-map-size", type=int, default=3_000_000)
    search_parser.add_argument(
        "--forced-product-max-iterations-log2",
        type=int,
        default=0,
        help="campaign cap; 0 skips every enumeration larger than one",
    )
    search_parser.add_argument(
        "--use-upstream-forced-product-default",
        action="store_true",
        help="omit the cap flag and retain Wang's default of 24",
    )
    search_parser.add_argument("--dim-min", type=int)
    search_parser.add_argument("--dim-max", type=int)
    search_parser.add_argument(
        "--fresh",
        action="store_true",
        help="replace the live campaign with the enumerated baseline",
    )

    verify_parser = subparsers.add_parser("verify", help="replay Wang's verifier")
    verify_parser.add_argument("certificate", type=Path, nargs="?")
    audit_parser = subparsers.add_parser("audit", help="audit metadata and hashes")
    audit_parser.add_argument("certificate", type=Path, nargs="?")
    snapshot_parser = subparsers.add_parser(
        "snapshot", help="verify and atomically snapshot protobuf + BTP archive"
    )
    snapshot_parser.add_argument("destination", type=Path)
    snapshot_parser.add_argument("--certificate", type=Path)
    subparsers.add_parser("plan", help="print the default campaign commands")
    args = parser.parse_args()

    work_dir: Path = args.work_dir.resolve()
    orbit_certificate = work_dir / ORBIT_FILENAME
    live_certificate = work_dir / CAMPAIGN_FILENAME
    upstream = args.upstream.resolve() if args.upstream is not None else None

    if args.action == "audit":
        certificate = (args.certificate or live_certificate).resolve()
        print_json(audit_certificate(certificate))
        return

    if upstream is None:
        parser.error("--upstream or WANG_TENSOR_RANK is required for this action")
    validate_upstream(upstream)

    if args.action == "build":
        run(build_command(args.mac_no_lto), upstream, args.dry_run)
        return
    if args.action == "enumerate":
        work_dir.mkdir(parents=True, exist_ok=True)
        if orbit_certificate.exists() and not args.dry_run:
            raise FileExistsError(
                f"refusing to overwrite {orbit_certificate}; remove it explicitly"
            )
        run(enumerate_command(upstream, orbit_certificate), upstream, args.dry_run)
        if not args.dry_run:
            print_json(audit_certificate(orbit_certificate))
        return
    if args.action == "search":
        if args.step_limit < 0 or args.max_map_size <= 0:
            parser.error("step limit must be nonnegative and map size must be positive")
        if not 0 <= args.forced_product_max_iterations_log2 <= 64:
            parser.error("forced-product log2 cap must be in [0,64]")
        work_dir.mkdir(parents=True, exist_ok=True)
        reset = args.fresh or not live_certificate.exists()
        if reset and not args.dry_run:
            audit_certificate(orbit_certificate)
            _atomic_copy(orbit_certificate, live_certificate)
            archive = btp_path(live_certificate)
            if archive.exists():
                archive.unlink()
        elif not live_certificate.exists() and args.dry_run:
            print(
                "+ cp "
                + shlex.quote(str(orbit_certificate))
                + " "
                + shlex.quote(str(live_certificate))
            )
        forced_cap = (
            None
            if args.use_upstream_forced_product_default
            else args.forced_product_max_iterations_log2
        )
        command = search_command(
            upstream,
            live_certificate,
            args.step_limit,
            args.max_map_size,
            forced_cap,
            reset,
            args.dim_min,
            args.dim_max,
        )
        run(command, upstream, args.dry_run)
        run(verify_command(upstream, live_certificate), upstream, args.dry_run)
        if not args.dry_run:
            print_json(audit_certificate(live_certificate))
        return
    if args.action == "verify":
        certificate = (args.certificate or live_certificate).resolve()
        audit_certificate(certificate)
        run(verify_command(upstream, certificate), upstream, args.dry_run)
        return
    if args.action == "snapshot":
        certificate = (args.certificate or live_certificate).resolve()
        audit_certificate(certificate)
        run(verify_command(upstream, certificate), upstream, args.dry_run)
        if not args.dry_run:
            print_json(snapshot_pair(certificate, args.destination.resolve()))
        return
    if args.action == "plan":
        commands = [
            build_command(args.mac_no_lto),
            enumerate_command(upstream, orbit_certificate),
            ["cp", str(orbit_certificate), str(live_certificate)],
            search_command(
                upstream,
                live_certificate,
                100_000,
                3_000_000,
                0,
                True,
            ),
            verify_command(upstream, live_certificate),
        ]
        for command in commands:
            print(shlex.join(command))
        return
    raise AssertionError(args.action)


if __name__ == "__main__":
    main()
