#!/usr/bin/env python3
"""Independently decode and verify a SAT model from inner2_direct_rank_opb.py."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def rank_rows(rows: list[int], width: int) -> int:
    values = list(rows)
    rank = 0
    for bit in range(width - 1, -1, -1):
        pivot = next(
            (index for index in range(rank, len(values)) if (values[index] >> bit) & 1),
            None,
        )
        if pivot is None:
            continue
        values[rank], values[pivot] = values[pivot], values[rank]
        for index in range(len(values)):
            if index != rank and ((values[index] >> bit) & 1):
                values[index] ^= values[rank]
        rank += 1
    return rank


def matrix_rank(value: int, rows: int, columns: int) -> int:
    mask = (1 << columns) - 1
    return rank_rows(
        [(value >> (row * columns)) & mask for row in range(rows)], columns
    )


def parse_model(path: Path) -> set[int]:
    positive: set[int] = set()
    satisfiable = False
    for line in path.read_text().splitlines():
        satisfiable |= line == "s SATISFIABLE"
        if not line.startswith("v "):
            continue
        for token in line.split()[1:]:
            if token == "0":
                continue
            if token.startswith("x"):
                positive.add(int(token[1:]))
            elif token.startswith("-x"):
                continue
            else:
                literal = int(token)
                if literal > 0:
                    positive.add(literal)
    assert satisfiable, path
    return positive


def audit(path: Path, a: int, c: int, terms: int) -> dict[str, int | str]:
    positive = parse_model(path)
    adim, bdim, targets = 2 * a, 2 * c, a * c
    ambient = adim * bdim
    a_base = 1
    b_base = a_base + terms * adim
    product_base = b_base + terms * bdim
    coefficient_base = product_base + terms * ambient

    def avar(term: int, coordinate: int) -> int:
        return a_base + term * adim + coordinate

    def bvar(term: int, coordinate: int) -> int:
        return b_base + term * bdim + coordinate

    def coefficient(term: int, target: int) -> int:
        return coefficient_base + term * targets + target

    avalues = [
        sum((avar(term, coordinate) in positive) << coordinate for coordinate in range(adim))
        for term in range(terms)
    ]
    bvalues = [
        sum((bvar(term, coordinate) in positive) << coordinate for coordinate in range(bdim))
        for term in range(terms)
    ]
    assert all(avalues) and all(bvalues)

    columns = []
    projected = []
    for avalue, bvalue in zip(avalues, bvalues):
        column = 0
        quotient = 0
        for ai in range(adim):
            if not ((avalue >> ai) & 1):
                continue
            for bi in range(bdim):
                if (bvalue >> bi) & 1:
                    column |= 1 << (ai * bdim + bi)
        for i in range(a):
            for k in range(c):
                target = i * c + k
                r00 = ((avalue >> (2 * i)) & 1) & ((bvalue >> k) & 1)
                r01 = ((avalue >> (2 * i)) & 1) & ((bvalue >> (c + k)) & 1)
                r10 = ((avalue >> (2 * i + 1)) & 1) & ((bvalue >> k) & 1)
                r11 = ((avalue >> (2 * i + 1)) & 1) & ((bvalue >> (c + k)) & 1)
                quotient |= (r00 ^ r11) << (3 * target)
                quotient |= r01 << (3 * target + 1)
                quotient |= r10 << (3 * target + 2)
        columns.append(column)
        projected.append(quotient)

    for target in range(targets):
        actual = 0
        for term, column in enumerate(columns):
            if coefficient(term, target) in positive:
                actual ^= column
        target_i, target_k = divmod(target, c)
        expected = 0
        for shared in range(2):
            ai = 2 * target_i + shared
            bi = shared * c + target_k
            expected |= 1 << (ai * bdim + bi)
        assert actual == expected, (target, actual, expected)

    quotient_rank = rank_rows(projected, 3 * targets)
    assert quotient_rank <= terms - targets
    fixed_a_rank = matrix_rank(avalues[0], a, 2)
    fixed_b_rank = matrix_rank(bvalues[0], 2, c)
    pairing: int | str = "na"
    if fixed_a_rank == fixed_b_rank == 1:
        shared_row = next(
            (avalues[0] >> (2 * row)) & 3
            for row in range(a)
            if ((avalues[0] >> (2 * row)) & 3)
        )
        column = next(
            k
            for k in range(c)
            if ((bvalues[0] >> k) & 1) or ((bvalues[0] >> (c + k)) & 1)
        )
        shared_column = (
            ((bvalues[0] >> column) & 1)
            | (((bvalues[0] >> (c + column)) & 1) << 1)
        )
        overlap = shared_row & shared_column
        pairing = (overlap & 1) ^ ((overlap >> 1) & 1)
    return {
        "model": str(path),
        "a": a,
        "c": c,
        "terms": terms,
        "fixed_a_rank": fixed_a_rank,
        "fixed_b_rank": fixed_b_rank,
        "fixed_pairing": pairing,
        "quotient_rank": quotient_rank,
        "quotient_cap": terms - targets,
        "used_terms": sum(
            any(coefficient(term, target) in positive for target in range(targets))
            for term in range(terms)
        ),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("model", type=Path)
    parser.add_argument("--a", type=int, required=True)
    parser.add_argument("--c", type=int, required=True)
    parser.add_argument("--terms", type=int, required=True)
    args = parser.parse_args()
    print(json.dumps(audit(args.model, args.a, args.c, args.terms), sort_keys=True))


if __name__ == "__main__":
    main()
