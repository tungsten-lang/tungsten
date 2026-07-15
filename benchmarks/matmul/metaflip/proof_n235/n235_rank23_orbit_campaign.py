#!/usr/bin/env python3
"""Build an audited symmetry-cover CNF for the n235 rank-23 probe.

The full fixed-rank-two necessary system is small as an integer model but
awkward for clause-learning solvers.  This generator exposes the finite
24-element stabilizer action as an explicit disjunction of canonical leaves.
All leaves share one copy of the ambient capacity constraints; selector
variables guard only their canonicalization conditions and subgroup lex
leaders.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from dataclasses import dataclass
from pathlib import Path

from n235_capacity import Cnf, build_fixed_rank_two_global_multiset_cnf
from n235_common import expand_certificate, group_permutations


@dataclass(frozen=True)
class SymmetryBranch:
    name: str
    fixed_multiplicities: tuple[tuple[int, int], ...]
    minimum_multiplicities: tuple[tuple[int, int], ...]
    stabilizer_fixed_points: tuple[int, ...]
    root_orbit_index: int
    child_orbit_index: int | None


def point_orbits(
    group: list[list[int]], points: set[int]
) -> list[tuple[int, ...]]:
    """Return a deterministic, independently checked orbit partition."""
    remaining = set(points)
    orbits: list[tuple[int, ...]] = []
    while remaining:
        representative = min(remaining)
        orbit = tuple(sorted({permutation[representative] for permutation in group}))
        assert orbit and set(orbit) <= remaining
        assert all(
            {permutation[point] for permutation in group} == set(orbit)
            for point in orbit
        )
        remaining.difference_update(orbit)
        orbits.append(orbit)
    assert set().union(*(set(orbit) for orbit in orbits)) == points
    assert sum(map(len, orbits)) == len(points)
    return orbits


def build_symmetry_branches(
    certificate: Path,
) -> tuple[list[SymmetryBranch], dict[str, object]]:
    """Construct the complete two-level stabilizer-orbit cover.

    At the root, choose the first occupied orbit of Stab(6), map one occupied
    point to that orbit's representative, and split its exact multiplicity.
    The multiplicity-one cases in the first five roots are the only difficult
    leaves.  Since 21 further occurrences remain, choose the first occupied
    orbit of the representative stabilizer and map one of its points to the
    child representative.  The other root leaves are kept directly.
    """
    _, lower_bounds, _ = expand_certificate(certificate)
    base = 6
    points = set(range(1, 64)) - {base}
    full_group = [
        permutation
        for permutation in group_permutations()
        if permutation[base] == base
    ]
    assert len(full_group) == 24
    root_orbits = point_orbits(full_group, points)
    assert [len(orbit) for orbit in root_orbits] == [3, 6, 3, 2, 12, 12, 24]

    branches: list[SymmetryBranch] = []
    child_counts: list[int] = []
    direct_count = 0
    for root_index, root_orbit in enumerate(root_orbits):
        root = root_orbit[0]
        root_capacity = 23 - lower_bounds[(root,)]
        assert root_capacity in (2, 3)
        earlier_root_points = tuple(
            point
            for orbit in root_orbits[:root_index]
            for point in orbit
        )
        root_zeros = tuple((point, 0) for point in earlier_root_points)
        root_stabilizer = [
            permutation
            for permutation in full_group
            if permutation[root] == root
        ]
        assert len(root_stabilizer) * len(root_orbit) == len(full_group)

        for count in range(1, root_capacity + 1):
            if count != 1 or root_index >= 5:
                branches.append(
                    SymmetryBranch(
                        name=f"root{root_index}-p{root}-m{count}",
                        fixed_multiplicities=root_zeros + ((root, count),),
                        minimum_multiplicities=(),
                        stabilizer_fixed_points=(root,),
                        root_orbit_index=root_index,
                        child_orbit_index=None,
                    )
                )
                direct_count += 1
                continue

            # With root multiplicity exactly one and total multiplicity 22,
            # some other point must occur.  The root stabilizer preserves the
            # earlier-root zero set, so its orbits on the remaining free
            # points give another sound first-occupied-orbit split.
            fixed_points = set(earlier_root_points) | {root}
            child_orbits = point_orbits(
                root_stabilizer, points - fixed_points
            )
            child_counts.append(len(child_orbits))
            for child_index, child_orbit in enumerate(child_orbits):
                child = child_orbit[0]
                earlier_child_points = tuple(
                    point
                    for orbit in child_orbits[:child_index]
                    for point in orbit
                )
                child_zeros = tuple(
                    (point, 0) for point in earlier_child_points
                )
                branches.append(
                    SymmetryBranch(
                        name=(
                            f"root{root_index}-p{root}-m1-"
                            f"child{child_index}-p{child}"
                        ),
                        fixed_multiplicities=(
                            root_zeros + ((root, 1),) + child_zeros
                        ),
                        minimum_multiplicities=((child, 1),),
                        stabilizer_fixed_points=(root, child),
                        root_orbit_index=root_index,
                        child_orbit_index=child_index,
                    )
                )

    assert child_counts == [14, 22, 9, 5, 25]
    assert direct_count == 12
    assert len(branches) == direct_count + sum(child_counts) == 87
    assert len({branch.name for branch in branches}) == len(branches)
    return branches, {
        "cover_schema": "n235-rank23-two-level-stabilizer-cover-v1",
        "fixed_base": base,
        "fixed_base_stabilizer_size": len(full_group),
        "root_orbit_sizes": [len(orbit) for orbit in root_orbits],
        "root_orbits": [list(orbit) for orbit in root_orbits],
        "refined_root_indices": list(range(5)),
        "refined_child_orbit_counts": child_counts,
        "direct_branches": direct_count,
        "refined_branches": sum(child_counts),
        "branches": len(branches),
        "coverage_argument": (
            "first occupied stabilizer orbit, then exact representative "
            "multiplicity; multiplicity-one hard roots repeat the same "
            "construction in the representative stabilizer"
        ),
    }


def parse_generated_cnf(data: bytes) -> tuple[Cnf, list[str]]:
    """Parse the trusted-in-process base generator's DIMACS output."""
    comments: list[str] = []
    header_variables = -1
    header_clauses = -1
    clauses: list[list[int]] = []
    for raw_line in data.decode().splitlines():
        if raw_line.startswith("c "):
            comments.append(raw_line[2:])
        elif raw_line.startswith("p cnf "):
            _, _, variables, count = raw_line.split()
            header_variables = int(variables)
            header_clauses = int(count)
        elif raw_line:
            literals = [int(value) for value in raw_line.split()]
            assert literals[-1] == 0
            clauses.append(literals[:-1])
    assert header_variables >= 0 and header_clauses == len(clauses)
    cnf = Cnf(header_variables)
    cnf.clauses = clauses
    return cnf, comments


def build_rank23_orbit_campaign_cnf(
    certificate: Path,
) -> tuple[bytes, dict[str, object]]:
    """Build one selector-guarded CNF containing all canonical leaves."""
    base_data, base_metadata = build_fixed_rank_two_global_multiset_cnf(
        certificate,
        global_rank=23,
        stabilizer_lex=False,
        prune_dominated_rows=True,
    )
    cnf, _ = parse_generated_cnf(base_data)
    base_variables = cnf.nvars
    base_clauses = len(cnf.clauses)

    _, lower_bounds, _ = expand_certificate(certificate)
    base = 6
    points = [point for point in range(1, 64) if point != base]
    capacities = {
        point: 23 - lower_bounds[(point,)] for point in points
    }
    slots: dict[tuple[int, int], int] = {}
    variable = 0
    for point in points:
        for occurrence in range(capacities[point]):
            variable += 1
            slots[point, occurrence] = variable
    assert variable == 145

    branches, cover_metadata = build_symmetry_branches(certificate)
    selectors = [cnf.var() for _ in branches]
    # Exactly one selector is sufficient and loses no model: every canonical
    # multiset belongs to at least one branch, and selecting just that branch
    # satisfies the selector constraints.  Pairwise AMO clauses make the
    # intended case split immediately visible to clause learning.
    cnf.add(*selectors)
    for left_index, left in enumerate(selectors):
        for right in selectors[left_index + 1 :]:
            cnf.add(-left, -right)

    all_permutations = group_permutations()
    branch_metadata: list[dict[str, object]] = []
    for selector, branch in zip(selectors, branches):
        stabilizer = [
            permutation
            for permutation in all_permutations
            if permutation[base] == base
            and all(
                permutation[point] == point
                for point in branch.stabilizer_fixed_points
            )
        ]
        assert stabilizer and 24 % len(stabilizer) == 0
        nonidentity = [
            permutation
            for permutation in stabilizer
            if any(permutation[point] != point for point in points)
        ]

        left = [
            slots[point, occurrence]
            for point in points
            for occurrence in range(capacities[point])
        ]
        guarded_lex = Cnf(cnf.nvars)
        for permutation in nonidentity:
            right = [
                slots[permutation[point], occurrence]
                for point in points
                for occurrence in range(capacities[point])
            ]
            guarded_lex.lex_less_equal(left, right)
        cnf.nvars = guarded_lex.nvars
        for clause in guarded_lex.clauses:
            cnf.add(-selector, *clause)

        for point, count in branch.fixed_multiplicities:
            assert 0 <= count <= capacities[point]
            for occurrence in range(capacities[point]):
                literal = slots[point, occurrence]
                cnf.add(
                    -selector,
                    literal if occurrence < count else -literal,
                )
        for point, count in branch.minimum_multiplicities:
            assert 0 <= count <= capacities[point]
            for occurrence in range(count):
                cnf.add(-selector, slots[point, occurrence])

        branch_metadata.append(
            {
                "name": branch.name,
                "selector": selector,
                "fixed_multiplicities": [
                    [point, count]
                    for point, count in branch.fixed_multiplicities
                ],
                "minimum_multiplicities": [
                    [point, count]
                    for point, count in branch.minimum_multiplicities
                ],
                "stabilizer_fixed_points": list(
                    branch.stabilizer_fixed_points
                ),
                "active_stabilizer_size": len(stabilizer),
                "lex_leaders": len(nonidentity),
            }
        )

    # DIMACS variable numbers do not affect semantics.  Put the 87 case
    # selectors first and their guarded clauses before the shared base.  This
    # makes a conventional CDCL solver branch on the finite symmetry cover
    # instead of spending minutes deciding sequential-counter auxiliaries
    # before it has selected any canonical leaf.
    old_variables = cnf.nvars
    selector_set = set(selectors)
    variable_order = selectors + [
        variable
        for variable in range(1, old_variables + 1)
        if variable not in selector_set
    ]
    assert len(variable_order) == old_variables
    remap = {
        old_variable: new_variable
        for new_variable, old_variable in enumerate(variable_order, start=1)
    }
    assert set(remap) == set(range(1, old_variables + 1))

    guarded_clauses = cnf.clauses[base_clauses:]
    shared_base_clauses = cnf.clauses[:base_clauses]
    cnf.clauses = [
        [
            remap[abs(literal)] if literal > 0 else -remap[abs(literal)]
            for literal in clause
        ]
        for clause in guarded_clauses + shared_base_clauses
    ]
    for record in branch_metadata:
        record["selector"] = remap[int(record["selector"])]
    assert [record["selector"] for record in branch_metadata] == list(
        range(1, len(branches) + 1)
    )

    branch_digest = hashlib.sha256(
        json.dumps(
            branch_metadata, sort_keys=True, separators=(",", ":")
        ).encode()
    ).hexdigest()
    comments = [
        "GF(2) <2,3,5> rank23 fixed-rank-two ambient capacity",
        "audited two-level stabilizer-orbit selector cover",
        f"base_cnf_sha256 {base_metadata['cnf_sha256']}",
        f"branch_digest {branch_digest}",
        f"branches {len(branches)} exactly_one_selector",
    ]
    data = cnf.dimacs(comments)
    metadata = dict(cover_metadata)
    metadata.update(
        {
            "certificate_sha256": base_metadata["certificate_sha256"],
            "base_cnf_sha256": base_metadata["cnf_sha256"],
            "base_variables": base_variables,
            "base_clauses": base_clauses,
            "variables": cnf.nvars,
            "clauses": len(cnf.clauses),
            "cnf_sha256": hashlib.sha256(data).hexdigest(),
            "selector_variables": len(selectors),
            "variable_order": "selectors-first",
            "clause_order": "guarded-cover-before-shared-base",
            "selector_pairwise_clauses": len(selectors)
            * (len(selectors) - 1)
            // 2,
            "branch_digest": branch_digest,
            "branch_metadata": branch_metadata,
            "dominance_audit": {
                "active_ambient_rows": base_metadata[
                    "active_ambient_rows"
                ],
                "redundant_ambient_rows": base_metadata[
                    "redundant_ambient_rows"
                ],
            },
        }
    )
    return data, metadata


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("certificate", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--metadata", type=Path)
    args = parser.parse_args()
    data, metadata = build_rank23_orbit_campaign_cnf(args.certificate)
    args.output.write_bytes(data)
    rendered = json.dumps(metadata, indent=2, sort_keys=True) + "\n"
    if args.metadata is not None:
        args.metadata.write_text(rendered)
    print(rendered, end="")


if __name__ == "__main__":
    main()
