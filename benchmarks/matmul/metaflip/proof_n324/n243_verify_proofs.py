#!/usr/bin/env python3
"""Strictly replay the 46 disjoint n243 capacity proofs with VeriPB 3."""

from __future__ import annotations

import argparse
import hashlib
import re
import subprocess
from pathlib import Path


DIAGNOSTIC = re.compile(r"\b(warning|unjustified|assumption|error|failed)\b", re.I)
ASSUMPTION_RULE = re.compile(rb"^(a|assumption)(?:\s|$)", re.M)


def proof_stems(shard_dir: Path) -> list[str]:
    root0 = sorted(shard_dir.glob("n243_capacity_orbit_00_*_child_*.opb"))
    root1 = sorted(shard_dir.glob("n243_capacity_orbit_01_*_child_*.opb"))
    assert len(root0) == 20, len(root0)
    assert len(root1) == 22, len(root1)
    roots = []
    for index in range(2, 6):
        matches = list(shard_dir.glob(f"n243_capacity_orbit_{index:02d}_rep_*.opb"))
        assert len(matches) == 1, (index, matches)
        roots.extend(matches)
    selected = root0 + root1 + roots
    stems = sorted(path.stem for path in selected)
    assert len(stems) == len(set(stems)) == 46
    return stems


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as source:
        while chunk := source.read(1 << 20):
            value.update(chunk)
    return value.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("shard_dir", type=Path)
    parser.add_argument("proof_dir", type=Path)
    parser.add_argument("--veripb", type=Path, required=True)
    parser.add_argument("--emit-manifest", type=Path)
    args = parser.parse_args()

    stems = proof_stems(args.shard_dir)
    actual_proofs = {path.stem for path in args.proof_dir.glob("*.pbp")}
    assert actual_proofs == set(stems), (
        sorted(set(stems) - actual_proofs),
        sorted(actual_proofs - set(stems)),
    )

    manifest = []
    for index, stem in enumerate(stems, 1):
        formula = args.shard_dir / f"{stem}.opb"
        proof = args.proof_dir / f"{stem}.pbp"
        proof_data = proof.read_bytes()
        assert not ASSUMPTION_RULE.search(proof_data), stem
        assert re.search(
            rb"\nconclusion UNSAT : \d+\nend pseudo-Boolean proof\s*$", proof_data
        ), stem
        checked = subprocess.run(
            [str(args.veripb), "--opb", str(formula), str(proof)],
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        output = checked.stdout
        assert checked.returncode == 0, (stem, checked.returncode, output)
        assert output.count("s VERIFIED UNSATISFIABLE") == 1, (stem, output)
        assert not DIAGNOSTIC.search(output), (stem, output)
        print(f"[{index:02d}/46] VERIFIED {stem}")
        manifest.append(f"{digest(formula)}  opb/{formula.name}")
        manifest.append(f"{digest(proof)}  proof/{proof.name}")

    if args.emit_manifest:
        args.emit_manifest.write_text("\n".join(manifest) + "\n")
    print("VERIFIED: all 46 disjoint shards, no assumptions or diagnostics")


if __name__ == "__main__":
    main()
