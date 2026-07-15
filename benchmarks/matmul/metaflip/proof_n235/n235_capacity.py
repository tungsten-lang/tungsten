#!/usr/bin/env python3
"""Generate and audit the finite capacity step in the GF(2) n235 proof."""

from __future__ import annotations

import argparse
import hashlib
import json
from collections import Counter
from pathlib import Path

from n235_common import (
    RANK_ONE_A,
    expand_certificate,
    group_permutations,
    rank_rows,
    span_elements,
)


class Cnf:
    def __init__(self, initial_vars: int):
        self.nvars = initial_vars
        self.clauses: list[list[int]] = []

    def var(self) -> int:
        self.nvars += 1
        return self.nvars

    def add(self, *literals: int) -> None:
        self.clauses.append(list(literals))

    def at_most(self, literals: list[int], bound: int) -> None:
        """Sinz sequential-counter encoding."""
        count = len(literals)
        if bound < 0:
            self.add()
            return
        if bound >= count:
            return
        if bound == 0:
            for literal in literals:
                self.add(-literal)
            return
        counters = [
            [self.var() for _ in range(bound)] for _ in range(count - 1)
        ]
        for i in range(count - 1):
            self.add(-literals[i], counters[i][0])
        for i in range(1, count - 1):
            self.add(-counters[i - 1][0], counters[i][0])
            for j in range(1, bound):
                self.add(
                    -literals[i], -counters[i - 1][j - 1], counters[i][j]
                )
                self.add(-counters[i - 1][j], counters[i][j])
        for i in range(1, count):
            self.add(-literals[i], -counters[i - 1][bound - 1])

    def lex_less_equal(self, left: list[int], right: list[int]) -> None:
        """Encode a binary lexicographic ``left <= right`` constraint.

        Every input is a positive variable.  Auxiliary variables record that
        all preceding bit pairs were equal.  The encoding is deliberately
        plain CNF so a proof-producing solver and the CakeML checker can replay
        the symmetry-broken formula without trusting a CP/SAT frontend.
        """
        assert left and len(left) == len(right)
        prefix_equal: int | None = None
        for index, (left_bit, right_bit) in enumerate(zip(left, right)):
            assert left_bit > 0 and right_bit > 0
            # A stabilizer element often fixes a long prefix pointwise.  Such
            # a pair is syntactically equal, so it extends the current prefix
            # without clauses or an auxiliary variable.  Encoding ``x == x``
            # indirectly is sound but hides the resulting unit prefix from
            # propagation and made the proof-producing solver dramatically
            # colder than CP-SAT's presolved model.
            if left_bit == right_bit:
                continue
            if prefix_equal is None:
                # A first difference may be 0/1 but never 1/0.
                self.add(-left_bit, right_bit)
            else:
                self.add(-prefix_equal, -left_bit, right_bit)
            if index + 1 == len(left):
                continue

            next_equal = self.var()
            if prefix_equal is not None:
                self.add(-next_equal, prefix_equal)
            # next_equal implies equality of this bit pair.
            self.add(-next_equal, -left_bit, right_bit)
            self.add(-next_equal, left_bit, -right_bit)
            # Equal bits extend an already-equal prefix.
            if prefix_equal is None:
                self.add(-left_bit, -right_bit, next_equal)
                self.add(left_bit, right_bit, next_equal)
            else:
                self.add(
                    -prefix_equal, -left_bit, -right_bit, next_equal
                )
                self.add(-prefix_equal, left_bit, right_bit, next_equal)
            prefix_equal = next_equal

    def dimacs(self, comments: list[str]) -> bytes:
        lines = [f"c {comment}" for comment in comments]
        lines.append(f"p cnf {self.nvars} {len(self.clauses)}")
        lines.extend(
            " ".join(map(str, clause)) + (" " if clause else "") + "0"
            for clause in self.clauses
        )
        return ("\n".join(lines) + "\n").encode()


def build_rank_two_multiset_cnf(
    certificate: Path,
    remaining_occurrences: int = 21,
) -> tuple[bytes, dict[str, object]]:
    assert remaining_occurrences >= 21
    parsed, lower_bounds, orbit_map = expand_certificate(certificate)
    base = (6,)
    assert parsed[29] == (base, 21)
    assert parsed[-1] == ((), 22)

    points = sorted(
        {min(value, value ^ 6) for value in range(1, 64) if min(value, value ^ 6)}
    )
    assert len(points) == 31
    rows: list[tuple[tuple[int, ...], int, int, tuple[int, ...]]] = []
    for subspace in sorted(lower_bounds, key=lambda value: (len(value), value)):
        if rank_rows(subspace + base) != len(subspace):
            continue
        quotient_points = tuple(
            sorted(
                {
                    min(value, value ^ 6)
                    for value in span_elements(subspace)
                    if min(value, value ^ 6)
                }
            )
        )
        rows.append(
            (
                subspace,
                orbit_map[subspace],
                remaining_occurrences - lower_bounds[subspace],
                quotient_points,
            )
        )
    assert len(rows) == 374

    singleton_capacity = {
        quotient_points[0]: capacity
        for _, _, capacity, quotient_points in rows
        if len(quotient_points) == 1
    }
    assert set(singleton_capacity) == set(points)
    expected_histogram = {
        1 + remaining_occurrences - 21: 15,
        2 + remaining_occurrences - 21: 13,
        3 + remaining_occurrences - 21: 3,
    }
    assert Counter(singleton_capacity.values()) == expected_histogram

    slots: dict[tuple[int, int], int] = {}
    next_variable = 0
    for point in points:
        for occurrence in range(singleton_capacity[point]):
            next_variable += 1
            slots[point, occurrence] = next_variable
    expected_slots = 50 + 31 * (remaining_occurrences - 21)
    assert next_variable == expected_slots

    cnf = Cnf(next_variable)
    # Ordered slots encode multiplicities 0..capacity without permutation
    # symmetry between slots of one quotient point.
    for point in points:
        for occurrence in range(1, singleton_capacity[point]):
            cnf.add(-slots[point, occurrence], slots[point, occurrence - 1])
    for _, _, capacity, quotient_points in rows:
        literals = [
            slots[point, occurrence]
            for point in quotient_points
            for occurrence in range(singleton_capacity[point])
        ]
        cnf.at_most(literals, capacity)

    all_slots = list(slots.values())
    cnf.at_most(all_slots, remaining_occurrences)
    cnf.at_most(
        [-variable for variable in all_slots],
        len(all_slots) - remaining_occurrences,
    )

    certificate_hash = hashlib.sha256(certificate.read_bytes()).hexdigest()
    if remaining_occurrences == 21:
        comments = [
            "GF(2) <2,3,5> rank-two-A constrained-rank-21 multiset capacity",
            f"certificate_sha256 {certificate_hash}",
            "transpose 2x3 first factor to 3x2 coordinates",
            "base_constraint 6 base_lb 21 target 22",
            "one ordered slot per certified occurrence capacity of each quotient point",
            "374 subspaces containing base; occurrence count <= 21-certified_lb",
            "total occurrence count = 21",
        ]
    else:
        comments = [
            f"GF(2) <2,3,5> rank-two-A remaining-{remaining_occurrences} multiset capacity",
            f"certificate_sha256 {certificate_hash}",
            "transpose 2x3 first factor to 3x2 coordinates",
            f"base_constraint 6 base_lb 21 hypothetical_global_rank {remaining_occurrences + 1}",
            "one ordered slot per certified occurrence capacity of each quotient point",
            f"374 subspaces containing base; occurrence count <= {remaining_occurrences}-certified_lb",
            f"total occurrence count = {remaining_occurrences}",
        ]
    data = cnf.dimacs(comments)
    return data, {
        "certificate_sha256": certificate_hash,
        "cnf_sha256": hashlib.sha256(data).hexdigest(),
        "variables": cnf.nvars,
        "clauses": len(cnf.clauses),
        "containing_subspaces": len(rows),
        "quotient_points": len(points),
        "occurrence_slots": len(all_slots),
        "remaining_occurrences": remaining_occurrences,
        "singleton_capacity_histogram": dict(
            sorted(Counter(singleton_capacity.values()).items())
        ),
    }


def build_fixed_rank_two_global_multiset_cnf(
    certificate: Path,
    global_rank: int = 23,
    stabilizer_lex: bool = False,
    fixed_multiplicities: tuple[tuple[int, int], ...] = (),
    minimum_multiplicities: tuple[tuple[int, int], ...] = (),
    rank_one_incidence_cut: bool = False,
    prune_dominated_rows: bool = True,
    stabilizer_fixed_points: tuple[int, ...] = (),
) -> tuple[bytes, dict[str, object]]:
    """Use every ambient subspace after fixing one rank-two first factor.

    The quotient-only capacity model sees membership only in subspaces that
    contain the fixed line. This stronger necessary condition keeps the two
    possible lifts of every nonzero quotient point separate and enforces the
    certified occurrence inequality for all 2,825 ambient subspaces.
    """
    assert global_rank >= 23
    parsed, lower_bounds, orbit_map = expand_certificate(certificate)
    base = 6
    base_line = (base,)
    assert parsed[29] == (base_line, 21)
    assert lower_bounds[base_line] == 21

    points = [value for value in range(1, 64) if value != base]
    singleton_capacity: dict[int, int] = {}
    for point in points:
        line = (point,)
        assert line in lower_bounds
        singleton_capacity[point] = global_rank - lower_bounds[line]
    expected_offset = global_rank - 23
    assert Counter(singleton_capacity.values()) == {
        2 + expected_offset: 41,
        3 + expected_offset: 21,
    }

    slots: dict[tuple[int, int], int] = {}
    next_variable = 0
    for point in points:
        for occurrence in range(singleton_capacity[point]):
            next_variable += 1
            slots[point, occurrence] = next_variable
    assert next_variable == 145 + 62 * expected_offset

    cnf = Cnf(next_variable)
    for point in points:
        for occurrence in range(1, singleton_capacity[point]):
            cnf.add(-slots[point, occurrence], slots[point, occurrence - 1])

    row_specs: list[
        tuple[tuple[int, ...], int, int, frozenset[int], list[int]]
    ] = []
    for subspace in sorted(lower_bounds, key=lambda value: (len(value), value)):
        elements = set(span_elements(subspace))
        base_occurrence = int(base in elements)
        capacity = global_rank - lower_bounds[subspace] - base_occurrence
        assert capacity >= 0
        literals = [
            slots[point, occurrence]
            for point in points
            if point in elements
            for occurrence in range(singleton_capacity[point])
        ]
        row_specs.append(
            (
                subspace,
                orbit_map[subspace],
                capacity,
                frozenset(literals),
                literals,
            )
        )
    assert len(row_specs) == 2825

    all_slots = list(slots.values())
    remaining = global_rank - 1
    all_slot_set = frozenset(all_slots)

    # The certificate contains one row for every ambient subspace, but many
    # rows are immediate consequences of a tighter row on a containing
    # subspace.  For nonnegative Boolean occurrence variables,
    #
    #     S subset T and sum(T) <= l <= k  =>  sum(S) <= k.
    #
    # Singleton rows whose capacity equals their number of allocated unary
    # slots are tautologies, while the whole-space upper bound is already one
    # half of the exact-total constraint below.  Removing these rows is an
    # audited semantic simplification, not an assumption from an external
    # presolver.  Strict containment makes the dominance relation acyclic, so
    # a removed row always has a chain ending at an emitted row.
    redundant_rows: dict[tuple[int, ...], dict[str, object]] = {}
    if prune_dominated_rows:
        for subspace, _, capacity, literal_set, _ in row_specs:
            if capacity >= len(literal_set):
                redundant_rows[subspace] = {
                    "reason": "tautology",
                    "subspace": list(subspace),
                    "capacity": capacity,
                    "literals": len(literal_set),
                }
                continue
            if literal_set == all_slot_set and capacity >= remaining:
                redundant_rows[subspace] = {
                    "reason": "exact-total",
                    "subspace": list(subspace),
                    "capacity": capacity,
                    "literals": len(literal_set),
                }
                continue
            for other_subspace, _, other_capacity, other_set, _ in row_specs:
                if (
                    literal_set < other_set
                    and other_capacity <= capacity
                ):
                    redundant_rows[subspace] = {
                        "reason": "dominated",
                        "subspace": list(subspace),
                        "capacity": capacity,
                        "literals": len(literal_set),
                        "witness_subspace": list(other_subspace),
                        "witness_capacity": other_capacity,
                        "witness_literals": len(other_set),
                    }
                    break

    # Recheck every recorded witness independently of the selection loop and
    # ensure strict-containment chains terminate at an emitted row or at one
    # of the two explicitly justified endpoint rules.  The digest below pins
    # this complete machine-checkable audit without bloating the DIMACS file.
    row_by_subspace = {
        subspace: (capacity, literal_set)
        for subspace, _, capacity, literal_set, _ in row_specs
    }
    for subspace, record in redundant_rows.items():
        capacity, literal_set = row_by_subspace[subspace]
        assert record["capacity"] == capacity
        assert record["literals"] == len(literal_set)
        reason = record["reason"]
        if reason == "tautology":
            assert capacity >= len(literal_set)
        elif reason == "exact-total":
            assert literal_set == all_slot_set and capacity >= remaining
        else:
            assert reason == "dominated"
            witness_subspace = tuple(record["witness_subspace"])
            witness_capacity, witness_set = row_by_subspace[
                witness_subspace
            ]
            assert literal_set < witness_set
            assert witness_capacity <= capacity
            seen = {subspace}
            while witness_subspace in redundant_rows:
                assert witness_subspace not in seen
                seen.add(witness_subspace)
                witness_record = redundant_rows[witness_subspace]
                if witness_record["reason"] != "dominated":
                    break
                witness_subspace = tuple(
                    witness_record["witness_subspace"]
                )
            assert witness_subspace in row_by_subspace

    dominance_audit = sorted(
        redundant_rows.values(),
        key=lambda record: tuple(record["subspace"]),
    )
    dominance_audit_sha256 = hashlib.sha256(
        json.dumps(
            dominance_audit, sort_keys=True, separators=(",", ":")
        ).encode()
    ).hexdigest()

    active_row_metadata: list[tuple[int, int, int, int]] = []
    for subspace, orbit, capacity, _, literals in row_specs:
        if subspace in redundant_rows:
            continue
        cnf.at_most(literals, capacity)
        active_row_metadata.append(
            (len(subspace), orbit, capacity, len(literals))
        )

    cnf.at_most(all_slots, remaining)
    cnf.at_most([-variable for variable in all_slots], len(all_slots) - remaining)

    incidence_cut_metadata: dict[str, object] | None = None
    if rank_one_incidence_cut:
        # Sum the same 21 independently selected lower-bound-20 rows used by
        # the all-rank-one contradiction.  With the fixed base occurrence
        # removed, their combined right-hand side is 21*3-6 = 57.  Repeated
        # literals encode each ambient point's incidence degree.  This is a
        # redundant, explicitly audited integer sum of original rows; exposing
        # it saves a CNF solver from rediscovering the cut by resolution.
        triples: dict[tuple[int, ...], tuple[int, ...]] = {}
        for subspace, bound in lower_bounds.items():
            if bound != 20:
                continue
            elements = set(span_elements(subspace))
            intersection = tuple(
                value for value in RANK_ONE_A if value in elements
            )
            if len(intersection) == 3:
                triples.setdefault(intersection, subspace)
        assert len(triples) == 21
        degrees = Counter(
            value
            for subspace in triples.values()
            for value in span_elements(subspace)
            if value
        )
        assert {degrees[value] for value in RANK_ONE_A} == {3}
        cut_bound = sum(
            global_rank
            - lower_bounds[subspace]
            - int(base in span_elements(subspace))
            for subspace in triples.values()
        )
        assert cut_bound == 57 and degrees[base] == 6
        weighted_literals = [
            slots[point, occurrence]
            for point in points
            for occurrence in range(singleton_capacity[point])
            for _ in range(degrees[point])
        ]
        # The total multiplicity is exactly 22, so subtract one copy of every
        # slot from both sides.  This equivalent compressed row is much smaller
        # in a sequential-counter encoding.  Since every nonbase point has
        # degree at least one, it also directly yields at most 17 rank-one
        # occurrences; expose that elementary consequence as a second cut.
        compressed_literals = [
            slots[point, occurrence]
            for point in points
            for occurrence in range(singleton_capacity[point])
            for _ in range(degrees[point] - 1)
        ]
        compressed_bound = cut_bound - remaining
        assert compressed_bound == 35
        cnf.at_most(compressed_literals, compressed_bound)
        rank_one_slots = [
            slots[point, occurrence]
            for point in RANK_ONE_A
            for occurrence in range(singleton_capacity[point])
        ]
        assert len(rank_one_slots) == 63
        cnf.at_most(rank_one_slots, 17)
        incidence_cut_metadata = {
            "summed_rows": len(triples),
            "bound": cut_bound,
            "weighted_literals": len(weighted_literals),
            "compressed_bound": compressed_bound,
            "compressed_literals": len(compressed_literals),
            "rank_one_occurrence_bound": 17,
            "base_incidence_removed": degrees[base],
            "rank_one_degree": 3,
        }

    assert len(set(stabilizer_fixed_points)) == len(stabilizer_fixed_points)
    assert all(point in points for point in stabilizer_fixed_points)
    stabilizer = [
        permutation
        for permutation in group_permutations()
        if permutation[base] == base
        and all(
            permutation[point] == point
            for point in stabilizer_fixed_points
        )
    ]
    assert stabilizer and 24 % len(stabilizer) == 0
    nonidentity_stabilizer = [
        permutation
        for permutation in stabilizer
        if any(permutation[point] != point for point in points)
    ]
    assert len(nonidentity_stabilizer) == len(stabilizer) - 1
    if stabilizer_lex:
        # Counts use ordered unary slots.  The stabilizer preserves matrix
        # rank, hence it also preserves every point's slot capacity.  Comparing
        # these flattened unary vectors is exactly lexicographic comparison of
        # the integer multiplicity vectors.  Every stabilizer orbit has a least
        # vector, so these constraints remove symmetry without removing a
        # feasible orbit.
        left = [
            slots[point, occurrence]
            for point in points
            for occurrence in range(singleton_capacity[point])
        ]
        for permutation in nonidentity_stabilizer:
            right = [
                slots[permutation[point], occurrence]
                for point in points
                for occurrence in range(singleton_capacity[point])
            ]
            assert len(right) == len(left)
            cnf.lex_less_equal(left, right)
    assert len({point for point, _ in fixed_multiplicities}) == len(
        fixed_multiplicities
    )
    for fixed_point, fixed_count in fixed_multiplicities:
        assert fixed_point in points
        assert 0 <= fixed_count <= singleton_capacity[fixed_point]
        for occurrence in range(singleton_capacity[fixed_point]):
            variable = slots[fixed_point, occurrence]
            cnf.add(variable if occurrence < fixed_count else -variable)
    assert len({point for point, _ in minimum_multiplicities}) == len(
        minimum_multiplicities
    )
    fixed_counts = dict(fixed_multiplicities)
    for minimum_point, minimum_count in minimum_multiplicities:
        assert minimum_point in points
        assert 0 <= minimum_count <= singleton_capacity[minimum_point]
        if minimum_point in fixed_counts:
            assert fixed_counts[minimum_point] >= minimum_count
        for occurrence in range(minimum_count):
            cnf.add(slots[minimum_point, occurrence])

    certificate_hash = hashlib.sha256(certificate.read_bytes()).hexdigest()
    data = cnf.dimacs(
        [
            "GF(2) <2,3,5> fixed-rank-two-A global multiset capacity",
            f"certificate_sha256 {certificate_hash}",
            "transpose 2x3 first factor to 3x2 coordinates",
            f"fixed_base 6 fixed_multiplicity 1 hypothetical_global_rank {global_rank}",
            "all 2825 ambient certified subspaces enforced",
            f"active nondominated ambient rows = {len(active_row_metadata)}",
            f"remaining nonbase occurrence count = {remaining}",
            f"active stabilizer size = {len(stabilizer)}",
            f"stabilizer lex leaders = {len(nonidentity_stabilizer) if stabilizer_lex else 0}",
        ]
    )
    return data, {
        "certificate_sha256": certificate_hash,
        "cnf_sha256": hashlib.sha256(data).hexdigest(),
        "variables": cnf.nvars,
        "clauses": len(cnf.clauses),
        "ambient_subspaces": len(row_specs),
        "active_ambient_rows": len(active_row_metadata),
        "prune_dominated_rows": prune_dominated_rows,
        "redundant_ambient_rows": dict(
            sorted(
                Counter(
                    record["reason"] for record in redundant_rows.values()
                ).items()
            )
        ),
        "dominance_audit_sha256": dominance_audit_sha256,
        "nonbase_points": len(points),
        "occurrence_slots": len(all_slots),
        "remaining_occurrences": remaining,
        "fixed_base_stabilizer_size": 24,
        "active_stabilizer_size": len(stabilizer),
        "stabilizer_fixed_points": list(stabilizer_fixed_points),
        "stabilizer_lex_leaders": (
            len(nonidentity_stabilizer) if stabilizer_lex else 0
        ),
        "fixed_multiplicities": [
            {"point": point, "count": count}
            for point, count in fixed_multiplicities
        ],
        "minimum_multiplicities": [
            {"point": point, "count": count}
            for point, count in minimum_multiplicities
        ],
        "rank_one_incidence_cut": incidence_cut_metadata,
        "singleton_capacity_histogram": dict(
            sorted(Counter(singleton_capacity.values()).items())
        ),
        "row_literal_histogram": dict(
            sorted(Counter(len(row[4]) for row in row_specs).items())
        ),
        "active_row_literal_histogram": dict(
            sorted(Counter(row[3] for row in active_row_metadata).items())
        ),
    }


def build_fixed_rank_two_global_multiset_opb(
    certificate: Path,
    global_rank: int = 23,
) -> tuple[bytes, dict[str, object]]:
    """Emit the same stabilizer-broken ambient model as native PB rows.

    This is substantially smaller than expanding every cardinality row to a
    sequential-counter CNF and gives proof-logging PB solvers the inequalities
    in their natural form.  The unary multiplicity and lex-leader variables
    remain Boolean, so the output is standard OPB.
    """
    assert global_rank == 23
    parsed, lower_bounds, _ = expand_certificate(certificate)
    base = 6
    assert parsed[29] == ((base,), 21)
    points = [value for value in range(1, 64) if value != base]
    singleton_capacity = {
        point: global_rank - lower_bounds[(point,)] for point in points
    }
    assert Counter(singleton_capacity.values()) == {2: 41, 3: 21}

    slots: dict[tuple[int, int], int] = {}
    next_variable = 0
    for point in points:
        for occurrence in range(singleton_capacity[point]):
            next_variable += 1
            slots[point, occurrence] = next_variable
    assert next_variable == 145

    constraints: list[str] = []
    for point in points:
        for occurrence in range(1, singleton_capacity[point]):
            constraints.append(
                f"+1 x{slots[point, occurrence - 1]} "
                f"-1 x{slots[point, occurrence]} >= 0 ;"
            )

    active_rows = 0
    for subspace in sorted(lower_bounds, key=lambda value: (len(value), value)):
        elements = set(span_elements(subspace))
        capacity = (
            global_rank
            - lower_bounds[subspace]
            - int(base in elements)
        )
        literals = [
            slots[point, occurrence]
            for point in points
            if point in elements
            for occurrence in range(singleton_capacity[point])
        ]
        if capacity >= len(literals):
            continue
        constraints.append(
            " ".join(f"-1 x{literal}" for literal in literals)
            + f" >= {-capacity} ;"
        )
        active_rows += 1

    all_slots = list(slots.values())
    remaining = global_rank - 1
    constraints.append(
        " ".join(f"+1 x{variable}" for variable in all_slots)
        + f" >= {remaining} ;"
    )
    constraints.append(
        " ".join(f"-1 x{variable}" for variable in all_slots)
        + f" >= {-remaining} ;"
    )

    stabilizer = [
        permutation
        for permutation in group_permutations()
        if permutation[base] == base
    ]
    assert len(stabilizer) == 24
    nonidentity_stabilizer = [
        permutation
        for permutation in stabilizer
        if any(permutation[point] != point for point in points)
    ]
    assert len(nonidentity_stabilizer) == 23
    lex_cnf = Cnf(next_variable)
    left = [
        slots[point, occurrence]
        for point in points
        for occurrence in range(singleton_capacity[point])
    ]
    for permutation in nonidentity_stabilizer:
        right = [
            slots[permutation[point], occurrence]
            for point in points
            for occurrence in range(singleton_capacity[point])
        ]
        lex_cnf.lex_less_equal(left, right)
    for clause in lex_cnf.clauses:
        negative_count = sum(literal < 0 for literal in clause)
        terms = " ".join(
            f"{'+1' if literal > 0 else '-1'} x{abs(literal)}"
            for literal in clause
        )
        constraints.append(f"{terms} >= {1 - negative_count} ;")

    certificate_hash = hashlib.sha256(certificate.read_bytes()).hexdigest()
    header = (
        f"* #variable= {lex_cnf.nvars} #constraint= {len(constraints)} "
        "#equal= 0 intsize= 64\n"
    )
    comments = (
        "* GF(2) <2,3,5> fixed-rank-two-A global multiset capacity\n"
        f"* certificate_sha256 {certificate_hash}\n"
        "* all active ambient rows; complete fixed-base stabilizer lex leaders\n"
    )
    data = (header + comments + "\n".join(constraints) + "\n").encode()
    return data, {
        "certificate_sha256": certificate_hash,
        "opb_sha256": hashlib.sha256(data).hexdigest(),
        "variables": lex_cnf.nvars,
        "constraints": len(constraints),
        "active_ambient_rows": active_rows,
        "occurrence_slots": len(all_slots),
        "remaining_occurrences": remaining,
        "fixed_base_stabilizer_size": len(stabilizer),
        "stabilizer_lex_leaders": len(nonidentity_stabilizer),
        "lex_clauses": len(lex_cnf.clauses),
    }


def audit_rank_two_multiset_model(
    certificate: Path,
    model_path: Path,
) -> dict[str, object]:
    """Semantically audit the compact SAT witness for 22 quotient factors."""
    model = json.loads(model_path.read_text())
    assert model["schema"] == "n235-rank2-quotient-capacity-sat-model-v1"
    assert model["fixed_rank_two_first_factor"] == 6
    assert model["remaining_occurrences"] == 22
    generated, metadata = build_rank_two_multiset_cnf(certificate, 22)
    assert hashlib.sha256(generated).hexdigest() == model["cnf_sha256"]
    assert metadata["cnf_sha256"] == model["cnf_sha256"]

    parsed, lower_bounds, orbit_map = expand_certificate(certificate)
    base = (6,)
    assert parsed[29] == (base, 21)
    points = sorted(
        {min(value, value ^ 6) for value in range(1, 64) if min(value, value ^ 6)}
    )
    multiplicities = {point: 0 for point in points}
    for point_text, count in model["quotient_multiplicities"].items():
        point = int(point_text)
        assert point in multiplicities
        assert isinstance(count, int) and count > 0
        multiplicities[point] = count
    assert sum(multiplicities.values()) == 22

    slacks: list[int] = []
    saturated_by_dimension: Counter[int] = Counter()
    for subspace in sorted(lower_bounds, key=lambda value: (len(value), value)):
        if rank_rows(subspace + base) != len(subspace):
            continue
        quotient_points = {
            min(value, value ^ 6)
            for value in span_elements(subspace)
            if min(value, value ^ 6)
        }
        capacity = 22 - lower_bounds[subspace]
        used = sum(multiplicities[point] for point in quotient_points)
        assert used <= capacity
        slack = capacity - used
        slacks.append(slack)
        if slack == 0:
            saturated_by_dimension[len(subspace)] += 1
    assert len(slacks) == 374
    return {
        "status": "SATISFIABLE",
        "cnf_sha256": model["cnf_sha256"],
        "support_points": sum(count > 0 for count in multiplicities.values()),
        "total_occurrences": sum(multiplicities.values()),
        "maximum_multiplicity": max(multiplicities.values()),
        "slack_histogram": dict(sorted(Counter(slacks).items())),
        "saturated_rows": sum(slack == 0 for slack in slacks),
        "saturated_by_dimension": dict(sorted(saturated_by_dimension.items())),
        "limitation": (
            "quotient capacities forget which ambient lift x or x+6 each "
            "occurrence uses; non-containing subspace constraints and the "
            "remaining B/C tensor equations are absent"
        ),
    }


def audit_rank_one_counting(
    certificate: Path,
    hypothetical_rank: int = 22,
) -> dict[str, object]:
    assert hypothetical_rank >= 22
    parsed, lower_bounds, _ = expand_certificate(certificate)
    assert parsed[28] == ((1,), 20)
    rank_one_set = set(RANK_ONE_A)
    triples: dict[tuple[int, ...], tuple[int, ...]] = {}
    for subspace, bound in lower_bounds.items():
        if bound != 20:
            continue
        intersection = tuple(
            value for value in RANK_ONE_A if value in set(span_elements(subspace))
        )
        if len(intersection) == 3:
            # Several ambient subspaces can induce the same rank-one triple.
            # One certified witness is sufficient for its occurrence row.
            triples.setdefault(intersection, subspace)
    assert len(triples) == 21
    assert set().union(*(set(triple) for triple in triples)) == rank_one_set
    degrees = Counter(value for triple in triples for value in triple)
    assert set(degrees) == rank_one_set
    assert set(degrees.values()) == {3}

    # In a hypothetical rank-r scheme, each selected subspace can contain at
    # most r-20 occurrences. Summing the 21 inequalities counts every
    # rank-one first factor exactly three times. This contradicts both r=22
    # and r=23; the latter observation isolates rank-two factors as the only
    # surviving case in the next-bound probe.
    left_hand_side = 3 * hypothetical_rank
    right_hand_side = 21 * (hypothetical_rank - 20)
    assert left_hand_side > right_hand_side
    return {
        "rank_one_points": len(RANK_ONE_A),
        "selected_subspaces": len(triples),
        "points_per_subspace": 3,
        "incidence_degree": 3,
        "certified_subspace_lower_bound": 20,
        "hypothetical_rank": hypothetical_rank,
        "summed_left_hand_side": left_hand_side,
        "summed_right_hand_side": right_hand_side,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("certificate", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--remaining-occurrences", type=int, default=21)
    parser.add_argument("--full-ambient", action="store_true")
    parser.add_argument("--stabilizer-lex", action="store_true")
    parser.add_argument("--opb", action="store_true")
    parser.add_argument("--fix-point", type=int)
    parser.add_argument("--fix-count", type=int)
    parser.add_argument(
        "--fix",
        action="append",
        default=[],
        metavar="POINT=COUNT",
        help="fix an ambient point multiplicity; may be repeated",
    )
    parser.add_argument(
        "--minimum",
        action="append",
        default=[],
        metavar="POINT=COUNT",
        help="require at least this ambient-point multiplicity; may repeat",
    )
    parser.add_argument("--rank-one-incidence-cut", action="store_true")
    parser.add_argument("--no-dominance-pruning", action="store_true")
    parser.add_argument(
        "--stabilizer-fix-point",
        action="append",
        default=[],
        type=int,
        help="restrict lex leaders to the subgroup fixing this point",
    )
    args = parser.parse_args()
    if args.opb:
        assert args.full_ambient and args.stabilizer_lex
        data, metadata = build_fixed_rank_two_global_multiset_opb(
            args.certificate, args.remaining_occurrences + 1
        )
    elif args.full_ambient:
        fixed_multiplicities: list[tuple[int, int]] = []
        if args.fix_point is not None or args.fix_count is not None:
            assert args.fix_point is not None and args.fix_count is not None
            fixed_multiplicities.append((args.fix_point, args.fix_count))
        for item in args.fix:
            point_text, separator, count_text = item.partition("=")
            assert separator
            fixed_multiplicities.append((int(point_text), int(count_text)))
        minimum_multiplicities: list[tuple[int, int]] = []
        for item in args.minimum:
            point_text, separator, count_text = item.partition("=")
            assert separator
            minimum_multiplicities.append((int(point_text), int(count_text)))
        data, metadata = build_fixed_rank_two_global_multiset_cnf(
            args.certificate,
            args.remaining_occurrences + 1,
            stabilizer_lex=args.stabilizer_lex,
            fixed_multiplicities=tuple(fixed_multiplicities),
            minimum_multiplicities=tuple(minimum_multiplicities),
            rank_one_incidence_cut=args.rank_one_incidence_cut,
            prune_dominated_rows=not args.no_dominance_pruning,
            stabilizer_fixed_points=tuple(args.stabilizer_fix_point),
        )
    else:
        data, metadata = build_rank_two_multiset_cnf(
            args.certificate, args.remaining_occurrences
        )
    args.output.write_bytes(data)
    metadata["rank_one_counting"] = audit_rank_one_counting(args.certificate)
    print(json.dumps(metadata, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
