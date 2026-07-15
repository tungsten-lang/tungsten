#!/usr/bin/env python3
"""Audit the quotient-rank necessary condition for GF(2) <3,2,4> rank 19.

This first implementation is deliberately independent of the Gaussian C
checker.  It decodes rank-one A=x*y^T and B=p*z^T factors, forms

    (x tensor z) tensor pi(y tensor p),

where pi quotients the four-dimensional y*p space by the identity vector,
and computes the rank of the nineteen resulting 36-bit columns.
"""

from __future__ import annotations

import argparse
import itertools
import json
import random
import re
import subprocess
import time
import math
from pathlib import Path

from n324_common import RANK_ONE_A, rank_rows


def factor_a(value: int) -> tuple[int, int]:
    """Factor a nonzero rank-one row-major 3x2 mask as x*y^T."""
    for x in range(1, 8):
        for y in range(1, 4):
            candidate = sum(
                (((x >> i) & 1) & ((y >> j) & 1)) << (2 * i + j)
                for i in range(3)
                for j in range(2)
            )
            if candidate == value:
                return x, y
    raise AssertionError((value, "not rank one"))


def factor_b(value: int) -> tuple[int, int]:
    """Factor a nonzero rank-one row-major 2x4 mask as p*z^T."""
    for p in range(1, 4):
        for z in range(1, 16):
            candidate = sum(
                (((p >> j) & 1) & ((z >> k) & 1)) << (4 * j + k)
                for j in range(2)
                for k in range(4)
            )
            if candidate == value:
                return p, z
    raise AssertionError((value, "not rank one"))


def quotient_r(value: int) -> int:
    """Map F2^(2x2) onto a 3-space with kernel <I_2>."""
    return (
        (((value >> 0) ^ (value >> 3)) & 1)
        | (((value >> 1) & 1) << 1)
        | (((value >> 2) & 1) << 2)
    )


def quotient_column(avalue: int, bvalue: int) -> int:
    x, y = factor_a(avalue)
    p, z = factor_b(bvalue)
    q = sum(
        (((x >> i) & 1) & ((z >> k) & 1)) << (4 * i + k)
        for i in range(3)
        for k in range(4)
    )
    r = sum(
        (((y >> j) & 1) & ((p >> jb) & 1)) << (2 * j + jb)
        for j in range(2)
        for jb in range(2)
    )
    qr = quotient_r(r)
    assert qr
    return sum(
        (((q >> qi) & 1) & ((qr >> ri) & 1)) << (3 * qi + ri)
        for qi in range(12)
        for ri in range(3)
    )


def parse_model(path: Path) -> set[int]:
    positive: set[int] = set()
    saw_sat = False
    for line in path.read_text().splitlines():
        saw_sat |= line == "s SATISFIABLE"
        if not line.startswith("v "):
            continue
        for token in line.split()[1:]:
            if token.startswith("x"):
                positive.add(int(token[1:]))
            elif not token.startswith("-x"):
                raise AssertionError(token)
    assert saw_sat and positive, path
    return positive


def decode_b(path: Path) -> tuple[int, ...]:
    rank_one_b = tuple(
        value
        for value in range(1, 256)
        if rank_rows([value & 15, value >> 4], 4) == 1
    )
    assert len(rank_one_b) == 45
    positive = parse_model(path)
    out = []
    for term in range(19):
        selected = tuple(
            value
            for offset, value in enumerate(rank_one_b)
            if term * 45 + offset + 1 in positive
        )
        assert len(selected) == 1, (path, term, selected)
        out.append(selected[0])
    return tuple(out)


def quotient_rank(missing: tuple[int, int], bvalues: tuple[int, ...]) -> int:
    avalues = tuple(value for value in RANK_ONE_A if value not in missing)
    assert len(avalues) == len(bvalues) == 19
    return rank_rows(
        [quotient_column(a, b) for a, b in zip(avalues, bvalues)], 36
    )


def independent(values: list[int]) -> bool:
    return rank_rows(values, 36) == len(values)


def rank8_cuts(
    missing: tuple[int, int],
    bvalues: tuple[int, ...],
    limit: int,
    seed: int,
) -> list[tuple[tuple[int, int], ...]]:
    """Return deterministic forbidden selections of eight independent columns."""
    avalues = tuple(value for value in RANK_ONE_A if value not in missing)
    columns = tuple(
        quotient_column(a, b) for a, b in zip(avalues, bvalues)
    )
    assert rank_rows(list(columns), 36) > 7
    rng = random.Random(seed)
    seen: set[tuple[int, ...]] = set()
    subsets: list[tuple[int, ...]] = []

    # Diverse random bases are cheap and avoid lexicographically correlated
    # clauses.  Finish with lexicographic enumeration if random sampling
    # collides before reaching the requested bounded count.
    attempts = 0
    while len(subsets) < limit and attempts < 100 * limit:
        attempts += 1
        order = list(range(19))
        rng.shuffle(order)
        chosen: list[int] = []
        basis: list[int] = []
        old_rank = 0
        for term in order:
            candidate = basis + [columns[term]]
            new_rank = rank_rows(candidate, 36)
            if new_rank > old_rank:
                chosen.append(term)
                basis.append(columns[term])
                old_rank = new_rank
                if len(chosen) == 8:
                    break
        key = tuple(sorted(chosen))
        if len(key) == 8 and key not in seen:
            seen.add(key)
            subsets.append(key)
    if len(subsets) < limit:
        for key in itertools.combinations(range(19), 8):
            if key in seen or not independent([columns[t] for t in key]):
                continue
            seen.add(key)
            subsets.append(key)
            if len(subsets) == limit:
                break
    return [tuple((term, bvalues[term]) for term in key) for key in subsets]


def dual_basis(columns: tuple[int, ...]) -> tuple[int, ...]:
    """Return ell_i with dot(ell_i, columns[j]) = [i=j]."""
    assert len(columns) == 8 and independent(list(columns))
    # Carry all eight right-hand sides through one row reduction.
    rows = [column | (1 << (36 + row)) for row, column in enumerate(columns)]
    pivot_row = 0
    pivots: list[int] = []
    for bit in range(36):
        pivot = next(
            (row for row in range(pivot_row, 8) if (rows[row] >> bit) & 1),
            None,
        )
        if pivot is None:
            continue
        rows[pivot_row], rows[pivot] = rows[pivot], rows[pivot_row]
        for row in range(8):
            if row != pivot_row and ((rows[row] >> bit) & 1):
                rows[row] ^= rows[pivot_row]
        pivots.append(bit)
        pivot_row += 1
        if pivot_row == 8:
            break
    assert len(pivots) == 8
    duals = [0] * 8
    for row, pivot in enumerate(pivots):
        rhs = rows[row] >> 36
        for index in range(8):
            if (rhs >> index) & 1:
                duals[index] |= 1 << pivot
    assert all(
        ((duals[i] & columns[j]).bit_count() & 1) == int(i == j)
        for i in range(8)
        for j in range(8)
    )
    return tuple(duals)


def best_triangular_order(
    terms: tuple[int, ...],
    duals: tuple[int, ...],
    candidates: list[list[int]],
) -> tuple[int, ...]:
    """Maximize the Cartesian box size with an exact 2^8 subset DP."""
    # count[prior_mask][j] is the number of candidates at term j that pair to
    # one with ell_j and to zero with every already-ordered ell_i.
    count = [[0] * 8 for _ in range(1 << 8)]
    for prior in range(1 << 8):
        for j in range(8):
            if (prior >> j) & 1:
                continue
            count[prior][j] = sum(
                ((duals[j] & value).bit_count() & 1)
                and all(
                    not ((duals[i] & value).bit_count() & 1)
                    for i in range(8)
                    if (prior >> i) & 1
                )
                for value in candidates[j]
            )
            assert count[prior][j] >= 1
    score = [-math.inf] * (1 << 8)
    order: list[tuple[int, ...] | None] = [None] * (1 << 8)
    score[0] = 0.0
    order[0] = ()
    for mask in range(1 << 8):
        if order[mask] is None:
            continue
        for j in range(8):
            if (mask >> j) & 1:
                continue
            new = mask | (1 << j)
            candidate_score = score[mask] + math.log(count[mask][j])
            candidate_order = order[mask] + (j,)
            if (
                candidate_score > score[new] + 1e-12
                or (
                    abs(candidate_score - score[new]) <= 1e-12
                    and (order[new] is None or candidate_order < order[new])
                )
            ):
                score[new] = candidate_score
                order[new] = candidate_order
    assert order[-1] is not None
    return order[-1]


def triangular_cut(
    missing: tuple[int, int],
    bvalues: tuple[int, ...],
    terms: tuple[int, ...],
) -> dict[str, object]:
    """Build a lower-triangular Cartesian independent-column nogood."""
    avalues = tuple(value for value in RANK_ONE_A if value not in missing)
    all_b = rank_one_b_values()
    selected = tuple(
        quotient_column(avalues[term], bvalues[term]) for term in terms
    )
    duals = dual_basis(selected)
    candidates = [
        [quotient_column(avalues[term], bvalue) for bvalue in all_b]
        for term in terms
    ]
    order = best_triangular_order(terms, duals, candidates)
    prior: list[int] = []
    boxes = []
    for position in order:
        allowed = tuple(
            bvalue
            for bvalue, column in zip(all_b, candidates[position])
            if ((duals[position] & column).bit_count() & 1)
            and all(
                not ((duals[earlier] & column).bit_count() & 1)
                for earlier in prior
            )
        )
        assert bvalues[terms[position]] in allowed
        boxes.append((terms[position], allowed))
        prior.append(position)
    return {
        "terms": terms,
        "duals": duals,
        "order": order,
        "boxes": tuple(boxes),
        "box_product": math.prod(len(allowed) for _, allowed in boxes),
    }


def triangular_cuts(
    missing: tuple[int, int],
    bvalues: tuple[int, ...],
    limit: int,
    seed: int,
) -> list[dict[str, object]]:
    singleton = rank8_cuts(missing, bvalues, limit, seed)
    return [
        triangular_cut(missing, bvalues, tuple(term for term, _ in cut))
        for cut in singleton
    ]


def rank_one_b_values() -> tuple[int, ...]:
    values = tuple(
        value
        for value in range(1, 256)
        if rank_rows([value & 15, value >> 4], 4) == 1
    )
    assert len(values) == 45
    return values


def opb_line(cut: tuple[tuple[int, int], ...]) -> str:
    bindex = {value: index for index, value in enumerate(rank_one_b_values())}
    assert len(cut) == 8 and len({term for term, _ in cut}) == 8
    return " ".join(
        f"-1 x{term * 45 + bindex[bvalue] + 1}" for term, bvalue in cut
    ) + " >= -7 ;"


def triangular_opb_line(cut: dict[str, object]) -> str:
    bindex = {value: index for index, value in enumerate(rank_one_b_values())}
    boxes = cut["boxes"]
    assert isinstance(boxes, tuple) and len(boxes) == 8
    variables = [
        term * 45 + bindex[bvalue] + 1
        for term, allowed in boxes
        for bvalue in allowed
    ]
    assert len(variables) == len(set(variables))
    return " ".join(f"-1 x{variable}" for variable in variables) + " >= -7 ;"


def write_instance(base: Path, output: Path, cuts: list[str]) -> None:
    with base.open() as source, output.open("w") as target:
        header = source.readline()
        match = re.search(r"#constraint= (\d+)", header)
        assert match
        count = int(match.group(1)) + len(cuts)
        target.write(
            header[:match.start(1)] + str(count) + header[match.end(1):]
        )
        for line in source:
            target.write(line)
        for line in cuts:
            target.write(line + "\n")


def run_loop(args: argparse.Namespace) -> None:
    assert args.base_opb and args.solver and args.work_dir
    args.work_dir.mkdir(parents=True, exist_ok=True)
    missing = tuple(args.missing)
    cuts: list[str] = []
    cut_set: set[str] = set()
    history = []
    for iteration in range(args.iterations):
        instance = args.work_dir / f"iter{iteration:03d}.opb"
        model = args.work_dir / f"iter{iteration:03d}.out"
        write_instance(args.base_opb, instance, cuts)
        command = [
            str(args.solver), "--verbosity=0", "--print-sol=1",
            f"--time-limit={args.time_limit}", str(instance),
        ]
        started = time.monotonic()
        result = subprocess.run(command, text=True, capture_output=True)
        elapsed = time.monotonic() - started
        model.write_text(result.stdout + result.stderr)
        status = next(
            (line[2:] for line in result.stdout.splitlines() if line.startswith("s ")),
            "UNKNOWN",
        )
        record = {
            "iteration": iteration,
            "status": status,
            "elapsed_seconds": elapsed,
            "cumulative_cuts": len(cuts),
        }
        if status != "SATISFIABLE":
            history.append(record)
            print(json.dumps(record, sort_keys=True), flush=True)
            break
        bvalues = decode_b(model)
        rank = quotient_rank(missing, bvalues)
        record["quotient_rank"] = rank
        if rank <= 7:
            record["result"] = "rank-condition SAT"
            history.append(record)
            print(json.dumps(record, sort_keys=True), flush=True)
            break
        generated = triangular_cuts(
            missing, bvalues, args.cuts_per_model,
            args.seed + iteration * 0x9E3779B1,
        )
        before = len(cuts)
        for cut in generated:
            line = triangular_opb_line(cut)
            if line not in cut_set:
                cut_set.add(line)
                cuts.append(line)
        record["new_cuts"] = len(cuts) - before
        history.append(record)
        print(json.dumps(record, sort_keys=True), flush=True)
    (args.work_dir / "summary.json").write_text(
        json.dumps(
            {
                "schema": "n324-quotient-rank-lazy-v1",
                "missing": list(missing),
                "base_opb": str(args.base_opb),
                "solver": str(args.solver),
                "history": history,
                "cuts": len(cuts),
            },
            indent=2,
        ) + "\n"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("model", type=Path, nargs="*")
    parser.add_argument("--missing", nargs=2, type=int, required=True)
    parser.add_argument("--base-opb", type=Path)
    parser.add_argument("--solver", type=Path)
    parser.add_argument("--work-dir", type=Path)
    parser.add_argument("--iterations", type=int, default=10)
    parser.add_argument("--cuts-per-model", type=int, default=1024)
    parser.add_argument("--time-limit", type=int, default=60)
    parser.add_argument("--seed", type=int, default=324)
    args = parser.parse_args()
    missing = tuple(args.missing)
    assert missing in ((1, 2), (1, 4), (1, 8))
    if args.base_opb:
        run_loop(args)
        return
    assert args.model
    histogram: dict[int, int] = {}
    for path in args.model:
        rank = quotient_rank(missing, decode_b(path))
        histogram[rank] = histogram.get(rank, 0) + 1
        print(f"{path} quotient_rank={rank}")
    print("histogram=" + " ".join(f"r{k}:{v}" for k, v in sorted(histogram.items())))


if __name__ == "__main__":
    main()
