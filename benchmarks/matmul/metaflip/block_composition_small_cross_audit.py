#!/usr/bin/env python3
"""Reproduce the field-aware small-cross block-composition audit.

The generated TSV deliberately keeps the historical ``fmm-lille-pinned``
label for numerical-only bounds.  Their actual rank-claim provenance is the
pinned matmulcatalog ``cited-bounds.json`` input; the label is retained only
because it is part of the published, hashed audit format.

This file uses only the Python 3.9 standard library.  Output is UTF-8 with LF
line endings on every platform.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import re
import sys
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import DefaultDict, Dict, List, Mapping, Optional, Sequence, Set, Tuple


PINNED_SHA256 = {
    "scan": "1c9dce45aada5646a3de470ed05515175e4529c49769a41c82c5df5977bc86bd",
    "catalog": "c5e301452fcf4f51f61a8f16086b446d6509f73f80f3e0f729fd4fd9a717e546",
    "cited_bounds": "29bb4750eeed8cbc0d4aca109150f3b80c3d67119a14819a8601a8519a528199",
    "status": "fe51e550fea77b2ea97ea08a1e8e0a6470a20372de0dfb7554c3c33996fe2651",
    "audit": "a4e9145f987e0906bae5de6a16462dc0e29ff20e4bad29f4715ae0603819dba3",
}

SCAN_FIELDS = [
    "target",
    "formula_rank",
    "alloc_n",
    "alloc_m",
    "alloc_p",
    "source",
    "s3_code",
]

OUTPUT_FIELDS = [
    "target",
    "formula_rank",
    "formula_field",
    "f2_status",
    "f2_baseline_rank",
    "f2_gain",
    "f2_baseline_source",
    "f2_baseline_scope",
    "universal_numeric_status",
    "universal_baseline_rank",
    "universal_numeric_gain",
    "universal_baseline_source",
    "universal_baseline_scope",
    "char0_numeric_status",
    "char0_baseline_rank",
    "char0_numeric_gain",
    "char0_baseline_source",
    "char0_baseline_scope",
    "any_field_numeric_status",
    "any_field_baseline_rank",
    "any_field_numeric_gain",
    "any_field_baseline_source",
    "any_field_baseline_scope",
    "alloc_n",
    "alloc_m",
    "alloc_p",
    "source",
    "s3_code",
]

F2_FIELDS = {"F2"}
CHAR0_FIELDS = {"Z", "Q", "R", "C"}
UNIVERSAL_FIELDS = {"F2", "F3", "Z", "Q", "R", "C"}
REDUCIBLE_FMM_SCOPES = {"Z", "ZT"}
ORIGIN_PRIORITY = {"fmm": 0, "numerical": 1, "catalog": 2}

Shape = Tuple[int, int, int]


@dataclass(frozen=True)
class Candidate:
    rank: int
    origin: str
    source: str
    scope: str
    supports_f2: bool
    supports_universal: bool
    supports_char0: bool

    def eligible(self, comparison: str) -> bool:
        if comparison == "f2":
            return self.supports_f2
        if comparison == "universal":
            return self.supports_universal
        if comparison == "char0":
            return self.supports_char0
        if comparison == "any_field":
            return True
        raise ValueError("unknown comparison: %s" % comparison)

    def selection_key(self) -> Tuple[int, int, str, str]:
        # These priorities encode the published audit's deterministic policy:
        # prefer an explicit FMM certificate, then a numerical-only public
        # bound, then a catalog certificate when ranks tie.
        return (self.rank, ORIGIN_PRIORITY[self.origin], self.source, self.scope)


def sha256_path(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while True:
            block = stream.read(1024 * 1024)
            if not block:
                break
            digest.update(block)
    return digest.hexdigest()


def load_json(path: Path) -> object:
    with path.open("r", encoding="utf-8") as stream:
        return json.load(stream)


def canonical_shape(value: object) -> Shape:
    if isinstance(value, str):
        pieces = value.split("x")
    elif isinstance(value, (list, tuple)):
        pieces = list(value)
    else:
        raise ValueError("invalid tensor shape: %r" % (value,))
    if len(pieces) != 3:
        raise ValueError("tensor shape must have three dimensions: %r" % (value,))
    dims = tuple(sorted(int(piece) for piece in pieces))
    if dims[0] <= 0:
        raise ValueError("tensor dimensions must be positive: %r" % (value,))
    return dims  # type: ignore[return-value]


def shape_name(shape: Shape) -> str:
    return "x".join(str(dim) for dim in shape)


def field_tokens(field: object) -> Set[str]:
    if isinstance(field, str):
        return {token for token in re.split(r"[^A-Za-z0-9]+", field) if token}
    if isinstance(field, list):
        return {str(token) for token in field}
    raise ValueError("invalid field declaration: %r" % (field,))


def add_candidate(
    candidates: DefaultDict[Shape, List[Candidate]], shape: Shape, candidate: Candidate
) -> None:
    candidates[shape].append(candidate)


def load_catalog_candidates(
    catalog_path: Path,
) -> Tuple[DefaultDict[Shape, List[Candidate]], Dict[Shape, Tuple[int, str]]]:
    document = load_json(catalog_path)
    if not isinstance(document, dict) or not isinstance(document.get("schemes"), list):
        raise ValueError("catalog JSON must contain a schemes list")

    candidates: DefaultDict[Shape, List[Candidate]] = defaultdict(list)
    lille: Dict[Shape, Tuple[int, str]] = {}
    for scheme in document["schemes"]:
        if not isinstance(scheme, dict):
            raise ValueError("catalog scheme is not an object")
        shape = canonical_shape(scheme["format"])

        lille_entry = scheme.get("fmm_lille")
        if isinstance(lille_entry, dict):
            value = (int(lille_entry["best_rank"]), str(lille_entry["details_url"]))
            previous = lille.get(shape)
            if previous is not None and previous != value:
                raise ValueError("conflicting Lille metadata for %s" % shape_name(shape))
            lille[shape] = value

        if scheme.get("verified") is not True or scheme.get("commutative", False):
            continue
        fields = field_tokens(scheme["fields"])
        scope = "+".join(str(field) for field in scheme["fields"])
        source = "matmulcatalog:src/main/resources/schemes/" + str(scheme["file"])
        add_candidate(
            candidates,
            shape,
            Candidate(
                rank=int(scheme["rank"]),
                origin="catalog",
                source=source,
                scope=scope,
                # The conservative F2 column requires an explicit F2 mark.
                supports_f2=bool(fields & F2_FIELDS),
                # A noncommutative integral identity is universal.  Current
                # all-field catalog entries include Z as well.
                supports_universal="Z" in fields or UNIVERSAL_FIELDS <= fields,
                supports_char0=bool(fields & CHAR0_FIELDS),
            ),
        )
    return candidates, lille


def load_fmm_candidates(status_path: Path) -> DefaultDict[Shape, List[Candidate]]:
    document = load_json(status_path)
    if not isinstance(document, dict):
        raise ValueError("FMM status JSON must be an object")
    candidates: DefaultDict[Shape, List[Candidate]] = defaultdict(list)
    for raw_shape, entry in document.items():
        if not isinstance(entry, dict):
            continue
        shape = canonical_shape(raw_shape)
        ranks = entry.get("ranks", {})
        schemes = entry.get("schemes", {})
        if not isinstance(ranks, dict) or not isinstance(schemes, dict):
            continue
        for raw_scope, raw_rank in ranks.items():
            scope = str(raw_scope)
            rank = int(raw_rank)
            scope_schemes = schemes.get(raw_scope, [])
            if not isinstance(scope_schemes, list):
                continue
            for scheme in scope_schemes:
                if not isinstance(scheme, dict) or int(scheme.get("rank", -1)) != rank:
                    continue
                source_path = scheme.get("source")
                if not source_path:
                    continue
                add_candidate(
                    candidates,
                    shape,
                    Candidate(
                        rank=rank,
                        origin="fmm",
                        source="FastMatrixMultiplication:" + str(source_path),
                        scope=scope,
                        supports_f2=scope in REDUCIBLE_FMM_SCOPES or scope == "F2",
                        supports_universal=scope in REDUCIBLE_FMM_SCOPES,
                        supports_char0=scope in CHAR0_FIELDS or scope in REDUCIBLE_FMM_SCOPES,
                    ),
                )
    return candidates


def load_numerical_candidates(
    cited_bounds_path: Path, lille: Mapping[Shape, Tuple[int, str]]
) -> DefaultDict[Shape, List[Candidate]]:
    document = load_json(cited_bounds_path)
    if not isinstance(document, dict) or not isinstance(document.get("entries"), list):
        raise ValueError("cited-bounds JSON must contain an entries list")
    candidates: DefaultDict[Shape, List[Candidate]] = defaultdict(list)
    for claim in document["entries"]:
        if not isinstance(claim, dict) or "rank" not in claim:
            continue
        # Commutative-only algorithms are not tensor-rank comparators for the
        # noncommutative matrix-multiplication tensors audited here.
        if claim.get("commutative", False):
            continue
        shape = canonical_shape(claim["format"])
        if shape not in lille:
            # The cited table covers dimensions beyond this catalog slice.
            # They cannot participate without matching pinned public metadata.
            continue
        fields = field_tokens(claim["field"])
        supports_char0 = bool(fields & CHAR0_FIELDS) or "all" in fields
        add_candidate(
            candidates,
            shape,
            Candidate(
                rank=int(claim["rank"]),
                origin="numerical",
                source="fmm-lille-pinned:" + lille[shape][1],
                scope="Q+R+C-assumed",
                # Rank claims without checked factors remain numerical only.
                supports_f2=False,
                supports_universal=False,
                supports_char0=supports_char0,
            ),
        )
    return candidates


def merge_candidates(
    *sources: Mapping[Shape, Sequence[Candidate]]
) -> DefaultDict[Shape, List[Candidate]]:
    merged: DefaultDict[Shape, List[Candidate]] = defaultdict(list)
    for source in sources:
        for shape, candidates in source.items():
            merged[shape].extend(candidates)
    return merged


def add_lille_candidates(
    candidates: DefaultDict[Shape, List[Candidate]], lille: Mapping[Shape, Tuple[int, str]]
) -> None:
    for shape, (rank, url) in lille.items():
        add_candidate(
            candidates,
            shape,
            Candidate(
                rank=rank,
                origin="numerical",
                source="fmm-lille-pinned:" + url,
                scope="Q+R+C-assumed",
                supports_f2=False,
                supports_universal=False,
                supports_char0=True,
            ),
        )


def read_scan(path: Path) -> List[Dict[str, str]]:
    with path.open("r", encoding="utf-8", newline="") as stream:
        reader = csv.DictReader(stream, delimiter="\t")
        if reader.fieldnames != SCAN_FIELDS:
            raise ValueError("unexpected scan header: %r" % (reader.fieldnames,))
        rows = list(reader)
    seen: Set[Shape] = set()
    previous: Optional[Shape] = None
    for row in rows:
        shape = canonical_shape(row["target"])
        if row["target"] != shape_name(shape):
            raise ValueError("scan target is not canonical: %s" % row["target"])
        if shape in seen:
            raise ValueError("duplicate scan target: %s" % row["target"])
        if previous is not None and shape <= previous:
            raise ValueError("scan targets are not strictly sorted")
        int(row["formula_rank"])
        int(row["s3_code"])
        seen.add(shape)
        previous = shape
    return rows


def best_candidate(
    candidates: Sequence[Candidate], comparison: str
) -> Optional[Candidate]:
    eligible = [candidate for candidate in candidates if candidate.eligible(comparison)]
    return min(eligible, key=Candidate.selection_key) if eligible else None


def comparison_columns(
    formula_rank: int, candidate: Optional[Candidate], status_key: str, gain_key: str,
    rank_key: str, source_key: str, scope_key: str
) -> Dict[str, str]:
    if candidate is None:
        return {
            status_key: "uncovered",
            rank_key: "",
            gain_key: "",
            source_key: "",
            scope_key: "",
        }
    gain = candidate.rank - formula_rank
    status = "win" if gain > 0 else "tie" if gain == 0 else "loss"
    return {
        status_key: status,
        rank_key: str(candidate.rank),
        gain_key: str(gain),
        source_key: candidate.source,
        scope_key: candidate.scope,
    }


def generate_rows(
    scan_rows: Sequence[Mapping[str, str]], candidates: Mapping[Shape, Sequence[Candidate]]
) -> List[Dict[str, str]]:
    output: List[Dict[str, str]] = []
    specs = [
        ("f2", "f2_status", "f2_baseline_rank", "f2_gain", "f2_baseline_source", "f2_baseline_scope"),
        ("universal", "universal_numeric_status", "universal_baseline_rank", "universal_numeric_gain", "universal_baseline_source", "universal_baseline_scope"),
        ("char0", "char0_numeric_status", "char0_baseline_rank", "char0_numeric_gain", "char0_baseline_source", "char0_baseline_scope"),
        ("any_field", "any_field_numeric_status", "any_field_baseline_rank", "any_field_numeric_gain", "any_field_baseline_source", "any_field_baseline_scope"),
    ]
    for scan in scan_rows:
        shape = canonical_shape(scan["target"])
        formula_rank = int(scan["formula_rank"])
        row = {field: "" for field in OUTPUT_FIELDS}
        row.update({field: str(scan[field]) for field in SCAN_FIELDS})
        row["formula_field"] = "F2"
        for comparison, status, rank, gain, source, scope in specs:
            row.update(
                comparison_columns(
                    formula_rank,
                    best_candidate(candidates.get(shape, []), comparison),
                    status,
                    gain,
                    rank,
                    source,
                    scope,
                )
            )
        output.append(row)
    return output


def render_tsv(rows: Sequence[Mapping[str, str]]) -> bytes:
    stream = io.StringIO(newline="")
    writer = csv.DictWriter(
        stream,
        fieldnames=OUTPUT_FIELDS,
        delimiter="\t",
        lineterminator="\n",
        extrasaction="raise",
    )
    writer.writeheader()
    writer.writerows(rows)
    return stream.getvalue().encode("utf-8")


def validate_pinned(paths: Mapping[str, Path]) -> None:
    errors = []
    for role, path in paths.items():
        actual = sha256_path(path)
        expected = PINNED_SHA256[role]
        if actual != expected:
            errors.append("%s: expected %s, got %s (%s)" % (role, expected, actual, path))
    if errors:
        raise ValueError("pinned input mismatch:\n" + "\n".join(errors))


def summary(rows: Sequence[Mapping[str, str]]) -> str:
    columns = [
        ("f2", "f2_status"),
        ("universal", "universal_numeric_status"),
        ("char0", "char0_numeric_status"),
        ("any_field", "any_field_numeric_status"),
    ]
    parts = []
    for label, column in columns:
        counts = Counter(row[column] for row in rows)
        parts.append(
            "%s=%d/%d/%d/%d"
            % (
                label,
                counts["win"],
                counts["tie"],
                counts["loss"],
                counts["uncovered"],
            )
        )
    return " ".join(parts)


def run_self_test() -> None:
    fmm = Candidate(10, "fmm", "fmm:z", "Z", True, True, True)
    catalog_f2 = Candidate(10, "catalog", "catalog:f2", "F2", True, False, False)
    catalog_all = Candidate(11, "catalog", "catalog:all", "F2+F3+Z+Q+R+C", True, True, True)
    numerical = Candidate(10, "numerical", "numeric", "Q+R+C-assumed", False, False, True)

    candidates = [catalog_f2, catalog_all, numerical, fmm]
    assert best_candidate(candidates, "f2") == fmm
    assert best_candidate(candidates, "universal") == fmm
    assert best_candidate(candidates, "char0") == fmm
    assert best_candidate([catalog_f2, numerical], "char0") == numerical
    assert best_candidate([catalog_f2, numerical], "any_field") == numerical
    assert best_candidate([catalog_f2], "universal") is None

    rendered = render_tsv([])
    assert b"\r" not in rendered
    assert rendered.endswith(b"\n")
    assert rendered.decode("utf-8").rstrip("\n").split("\t") == OUTPUT_FIELDS
    print("block_composition_small_cross_audit self-test: pass")


def parse_args(argv: Optional[Sequence[str]] = None) -> argparse.Namespace:
    here = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scan", type=Path, default=here / "block_composition_small_cross_scan.tsv")
    parser.add_argument("--catalog", type=Path, help="matmulcatalog docs/catalog.json")
    parser.add_argument("--cited-bounds", type=Path, help="matmulcatalog docs/cited-bounds.json")
    parser.add_argument("--status", type=Path, help="FastMatrixMultiplication schemes/status.json")
    parser.add_argument("--output", type=Path, help="output TSV; omit to write stdout")
    parser.add_argument("--check", type=Path, help="fail unless generated bytes equal this file")
    parser.add_argument("--require-pinned", action="store_true", help="verify known input SHA-256 values")
    parser.add_argument("--self-test", action="store_true", help="run focused classifier/LF tests")
    return parser.parse_args(argv)


def main(argv: Optional[Sequence[str]] = None) -> int:
    args = parse_args(argv)
    if args.self_test:
        run_self_test()
        if args.catalog is None and args.cited_bounds is None and args.status is None:
            return 0
    missing = [
        option
        for option, value in [
            ("--catalog", args.catalog),
            ("--cited-bounds", args.cited_bounds),
            ("--status", args.status),
        ]
        if value is None
    ]
    if missing:
        raise ValueError("required generation inputs: %s" % ", ".join(missing))

    if args.require_pinned:
        validate_pinned(
            {
                "scan": args.scan,
                "catalog": args.catalog,
                "cited_bounds": args.cited_bounds,
                "status": args.status,
            }
        )

    catalog_candidates, lille = load_catalog_candidates(args.catalog)
    fmm_candidates = load_fmm_candidates(args.status)
    numerical_candidates = load_numerical_candidates(args.cited_bounds, lille)
    candidates = merge_candidates(catalog_candidates, fmm_candidates, numerical_candidates)
    add_lille_candidates(candidates, lille)
    scan_rows = read_scan(args.scan)
    rows = generate_rows(scan_rows, candidates)
    result = render_tsv(rows)

    if args.check is not None:
        expected = args.check.read_bytes()
        if result != expected:
            raise ValueError(
                "generated audit differs from %s: generated=%s expected=%s"
                % (
                    args.check,
                    hashlib.sha256(result).hexdigest(),
                    hashlib.sha256(expected).hexdigest(),
                )
            )

    if args.require_pinned:
        actual = hashlib.sha256(result).hexdigest()
        if actual != PINNED_SHA256["audit"]:
            raise ValueError("pinned output mismatch: expected %s, got %s" % (PINNED_SHA256["audit"], actual))

    if args.output is None:
        sys.stdout.buffer.write(result)
    else:
        args.output.write_bytes(result)
        print(
            "wrote %s rows=%d sha256=%s %s"
            % (args.output, len(rows), hashlib.sha256(result).hexdigest(), summary(rows))
        )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (KeyError, TypeError, ValueError) as error:
        print("error: %s" % error, file=sys.stderr)
        raise SystemExit(2)
