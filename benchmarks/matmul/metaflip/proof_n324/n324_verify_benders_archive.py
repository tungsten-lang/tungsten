#!/usr/bin/env python3
"""Independently replay and manifest an n324 Gaussian-Benders archive.

This verifier deliberately does not import the cut generator.  It reconstructs
the 576-by-228 C system, validates every recorded left-null witness directly,
rebuilds every PB cut byte-for-byte, and checks that each SAT model obeys all
necessary occurrence/span constraints and every earlier cut.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
from pathlib import Path

from n324_common import RANK_ONE_A, rank32, rank_rows


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        while chunk := source.read(1 << 20):
            digest.update(chunk)
    return digest.hexdigest()


def parse_model(path: Path) -> set[int]:
    text = path.read_text()
    assert re.search(r"^s SATISFIABLE$", text, re.M), path
    positive: set[int] = set()
    mentioned: set[int] = set()
    for line in text.splitlines():
        if not line.startswith("v "):
            continue
        for token in line.split()[1:]:
            match = re.fullmatch(r"(-?)x(\d+)", token)
            assert match, (path, token)
            variable = int(match.group(2))
            assert variable not in mentioned, (path, variable)
            mentioned.add(variable)
            if not match.group(1):
                positive.add(variable)
    assert set(range(1, 856)) <= mentioned, path
    return positive


def rank_one_b_values() -> tuple[int, ...]:
    values = tuple(
        value
        for value in range(1, 256)
        if rank_rows([value & 15, value >> 4], 4) == 1
    )
    assert len(values) == 45
    return values


def decode_b(positive: set[int], values: tuple[int, ...]) -> list[int]:
    result = []
    for term in range(19):
        selected = [
            value
            for offset, value in enumerate(values)
            if term * 45 + offset + 1 in positive
        ]
        assert len(selected) == 1, (term, selected)
        result.append(selected[0])
    return result


def system_rows(a: tuple[int, ...], b: list[int]) -> list[tuple[int, int]]:
    rows = []
    for ai in range(6):
        i, j = divmod(ai, 2)
        for bj in range(8):
            jb, k = divmod(bj, 4)
            for ck in range(12):
                kc, ic = divmod(ck, 3)
                variables = 0
                for term in range(19):
                    if ((a[term] >> ai) & 1) and ((b[term] >> bj) & 1):
                        variables ^= 1 << (term * 12 + ck)
                rows.append((variables, int(j == jb and k == kc and i == ic)))
    assert len(rows) == 576
    return rows


def system_is_inconsistent(rows: list[tuple[int, int]]) -> tuple[bool, int]:
    basis: dict[int, tuple[int, int]] = {}
    inconsistent = False
    for variables, rhs in rows:
        while variables:
            pivot = variables.bit_length() - 1
            if pivot not in basis:
                basis[pivot] = variables, rhs
                break
            old_variables, old_rhs = basis[pivot]
            variables ^= old_variables
            rhs ^= old_rhs
        else:
            inconsistent |= bool(rhs)
    return inconsistent, len(basis)


def column_masks(
    a: tuple[int, ...], bvalues: tuple[int, ...]
) -> list[list[list[int]]]:
    """Return [term][B index][C bit] 576-bit coefficient columns."""
    result: list[list[list[int]]] = []
    for avalue in a:
        by_b = []
        for bvalue in bvalues:
            by_c = []
            for cbit in range(12):
                mask = 0
                for ai in range(6):
                    if not ((avalue >> ai) & 1):
                        continue
                    for bj in range(8):
                        if (bvalue >> bj) & 1:
                            mask |= 1 << ((ai * 8 + bj) * 12 + cbit)
                by_c.append(mask)
            by_b.append(by_c)
        result.append(by_b)
    return result


def load_occurrence(path: Path, allowed: set[int]) -> list[tuple[int, set[int]]]:
    rows = []
    for line in path.read_text().splitlines():
        fields = tuple(map(int, line.split()))
        assert len(fields) >= 2
        capacity, points = fields[0], set(fields[1:])
        assert points <= allowed
        rows.append((capacity, points))
    assert len(rows) == 56724
    return rows


def audit_necessary_model(
    a: tuple[int, ...],
    b: list[int],
    occurrence: list[tuple[int, set[int]]],
    fixed_b: int,
    canonical_term: int,
) -> None:
    assert b[canonical_term] == fixed_b
    for capacity, points in occurrence:
        assert sum(value in points for value in b) <= capacity
    functionals = [value for value in range(1, 64) if rank32(value) == 2]
    assert len(functionals) == 42
    for functional in functionals:
        active = [
            b[term]
            for term, avalue in enumerate(a)
            if (functional & avalue).bit_count() & 1
        ]
        assert rank_rows(active, 8) == 8


def cut_variables(line: str) -> set[int]:
    match = re.fullmatch(r"((?:\+1 x\d+ ?)+)>= 1 ;", line)
    assert match, line
    variables = {int(value) for value in re.findall(r"\+1 x(\d+)", line)}
    assert len(variables) == line.count("+1 x")
    return variables


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("base", type=Path)
    parser.add_argument("occurrence_table", type=Path)
    parser.add_argument("work_dir", type=Path)
    parser.add_argument("manifest", type=Path)
    parser.add_argument(
        "--checked-instance", type=Path,
        help="emit base plus all cuts only after every external lemma passes",
    )
    parser.add_argument("--missing", nargs=2, type=int, required=True)
    parser.add_argument("--fixed-b", type=int, required=True)
    args = parser.parse_args()

    missing = tuple(args.missing)
    assert missing in ((1, 2), (1, 4), (1, 8))
    a = tuple(value for value in RANK_ONE_A if value not in missing)
    assert len(a) == len(set(a)) == 19
    canonical_a = {(1, 2): 3, (1, 4): 5, (1, 8): 15}[missing]
    canonical_term = a.index(canonical_a)
    bvalues = rank_one_b_values()
    bindex = {value: index for index, value in enumerate(bvalues)}
    occurrence = load_occurrence(args.occurrence_table, set(bvalues))
    columns = column_masks(a, bvalues)

    cut_paths = sorted(args.work_dir.glob("cuts[0-9][0-9][0-9].opb"))
    json_paths = sorted(args.work_dir.glob("cuts[0-9][0-9][0-9].json"))
    assert cut_paths and len(cut_paths) == len(json_paths)
    assert [path.stem for path in cut_paths] == [path.stem for path in json_paths]
    iterations = []
    previous_cut_variables: list[set[int]] = []
    all_cut_lines: list[str] = []
    total_cuts = 0

    for iteration, (cut_path, json_path) in enumerate(zip(cut_paths, json_paths)):
        assert cut_path.stem == f"cuts{iteration:03d}"
        model_path = args.work_dir / f"iter{iteration:03d}.out"
        assert model_path.is_file()
        positive = parse_model(model_path)
        b = decode_b(positive, bvalues)
        audit_necessary_model(
            a, b, occurrence, args.fixed_b, canonical_term
        )
        for variables in previous_cut_variables:
            assert positive & variables, (iteration, "violates an earlier cut")

        rows = system_rows(a, b)
        inconsistent, matrix_rank = system_is_inconsistent(rows)
        assert inconsistent, (iteration, "C system unexpectedly consistent")
        data = json.loads(json_path.read_text())
        assert data["missing_A"] == list(missing)
        assert data["fixed_B"] == args.fixed_b
        assert data["B_assignment"] == b
        metadata = data["selected_cuts"]
        lines = [line for line in cut_path.read_text().splitlines() if line]
        assert len(lines) == len(metadata) > 0

        current_variables = []
        cut_bindings = []
        for line, item in zip(lines, metadata):
            selected = item["selected_equations"]
            assert selected == sorted(set(selected))
            assert selected and selected[-1] < 576
            witness = sum(1 << index for index in selected)
            combined_row = 0
            combined_rhs = 0
            for index in selected:
                combined_row ^= rows[index][0]
                combined_rhs ^= rows[index][1]
            assert combined_row == item["combined_row"] == 0
            assert combined_rhs == item["combined_rhs"] == 1

            allowed = []
            for term in range(19):
                term_allowed = []
                for offset, bvalue in enumerate(bvalues):
                    if all(
                        not ((witness & columns[term][offset][cbit]).bit_count() & 1)
                        for cbit in range(12)
                    ):
                        term_allowed.append(bvalue)
                allowed.append(term_allowed)
            assert allowed == item["allowed_B_by_term"]
            assert list(map(len, allowed)) == item["allowed_sizes"]
            assert all(b[term] in allowed[term] for term in range(19))

            outside = [
                term * 45 + bindex[bvalue] + 1
                for term in range(19)
                for bvalue in bvalues
                if bvalue not in set(allowed[term])
            ]
            expected = " ".join(f"+1 x{variable}" for variable in outside) + " >= 1 ;"
            assert line == expected
            assert item["cut_literals"] == len(outside)
            assert item["selected_equation_count"] == len(selected)
            assert item["cut_sha256"] == hashlib.sha256((line + "\n").encode()).hexdigest()
            expected_score = sum(math.log2(len(values)) for values in allowed)
            assert math.isclose(
                item["excluded_log2_cartesian_size"], expected_score,
                rel_tol=0.0, abs_tol=1e-12,
            )
            assert item["direct_column_audit"] == "PASS"
            variables = cut_variables(line)
            assert variables == set(outside)
            assert not (positive & variables), "cut does not reject its source model"
            current_variables.append(variables)
            cut_bindings.append(
                {
                    "cut_sha256": item["cut_sha256"],
                    "y_selector_sha256": hashlib.sha256(
                        json.dumps(selected, separators=(",", ":")).encode()
                    ).hexdigest(),
                    "allowed_table_sha256": hashlib.sha256(
                        json.dumps(allowed, separators=(",", ":")).encode()
                    ).hexdigest(),
                }
            )

        previous_cut_variables.extend(current_variables)
        all_cut_lines.extend(lines)
        total_cuts += len(lines)
        meta_path = args.work_dir / f"iter{iteration:03d}.meta.json"
        entry = {
            "iteration": iteration,
            "model": model_path.name,
            "model_sha256": sha256(model_path),
            "B_assignment": b,
            "C_matrix_rank": matrix_rank,
            "C_inconsistent": True,
            "cut_file": cut_path.name,
            "cut_file_sha256": sha256(cut_path),
            "witness_file": json_path.name,
            "witness_file_sha256": sha256(json_path),
            "checked_cuts": len(lines),
            "cut_witness_bindings": cut_bindings,
        }
        if meta_path.is_file():
            entry["solver_metadata"] = json.loads(meta_path.read_text())
            entry["solver_metadata_sha256"] = sha256(meta_path)
        iterations.append(entry)
        print(
            f"iteration={iteration} model=PASS C=INCONSISTENT "
            f"rank={matrix_rank} cuts={len(lines)} PASS"
        )

    checked_instance = None
    if args.checked_instance is not None:
        base_lines = args.base.read_text().splitlines()
        header = re.fullmatch(
            r"\* #variable= (\d+) #constraint= (\d+) #equal= 0 intsize= 64",
            base_lines[0],
        )
        assert header, base_lines[0]
        variables, constraints = map(int, header.groups())
        base_lines[0] = (
            f"* #variable= {variables} #constraint= {constraints + total_cuts} "
            "#equal= 0 intsize= 64"
        )
        args.checked_instance.write_text(
            "\n".join([*base_lines, *all_cut_lines]) + "\n"
        )
        checked_instance = {
            "path": str(args.checked_instance.resolve()),
            "size": args.checked_instance.stat().st_size,
            "sha256": sha256(args.checked_instance),
            "base_constraints": constraints,
            "audited_external_cuts": total_cuts,
            "constraints": constraints + total_cuts,
        }

    manifest = {
        "schema": "n324-gaussian-benders-archive-v1",
        "claim_scope": "sound learned cuts only; this archive is not an UNSAT proof",
        "work_dir": str(args.work_dir.resolve()),
        "independent_checker": {
            "path": str(Path(__file__).resolve()),
            "sha256": sha256(Path(__file__).resolve()),
        },
        "missing_A": list(missing),
        "fixed_B": args.fixed_b,
        "base": {
            "path": str(args.base.resolve()),
            "size": args.base.stat().st_size,
            "sha256": sha256(args.base),
        },
        "occurrence_table": {
            "path": str(args.occurrence_table.resolve()),
            "size": args.occurrence_table.stat().st_size,
            "sha256": sha256(args.occurrence_table),
            "rows": len(occurrence),
        },
        "iterations": iterations,
        "checked_models": len(iterations),
        "checked_cuts": total_cuts,
        "checked_instance": checked_instance,
        "audit": {
            "one_hot_B": "PASS",
            "occurrence_constraints": "PASS",
            "rank_two_A_span_constraints": "PASS",
            "prior_cut_satisfaction": "PASS",
            "C_inconsistency": "PASS",
            "left_null_witnesses": "PASS",
            "allowed_B_sets": "PASS",
            "PB_cut_reconstruction": "PASS",
            "source_model_rejection": "PASS",
        },
        "replay_command": [
            "python3",
            str(Path(__file__).resolve()),
            str(args.base.resolve()),
            str(args.occurrence_table.resolve()),
            str(args.work_dir.resolve()),
            str(args.manifest.resolve()),
            "--missing",
            *map(str, missing),
            "--fixed-b",
            str(args.fixed_b),
            *(
                ["--checked-instance", str(args.checked_instance.resolve())]
                if args.checked_instance is not None
                else []
            ),
        ],
    }
    args.manifest.write_text(json.dumps(manifest, indent=2) + "\n")
    print(
        f"ARCHIVE PASS models={len(iterations)} cuts={total_cuts} "
        f"manifest={args.manifest} sha256={sha256(args.manifest)}"
    )


if __name__ == "__main__":
    main()
