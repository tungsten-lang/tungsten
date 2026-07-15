"""Audit signed matrix-multiplication schemes as exact GF(2) restart doors.

The external ``.exp`` format writes a trilinear trace decomposition

    (linear form in a_ij) * (linear form in b_jk) * (linear form in c_ki).

FlipFleet stores its third factor as the output coordinate ``C_ik``.  The
conversion therefore transposes every ``c`` coordinate.  Coefficient signs
vanish modulo two, duplicate rank-one terms cancel by parity, and every
projection is checked against all n^6 tensor coefficients before it can be
written.

This tool is deliberately independent of the FlipFleet worker/parser.  It is
an offline provenance and novelty audit; it is not part of a live hot path.
"""

from __future__ import annotations

import argparse
from collections import Counter
from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
import re
import statistics
import subprocess
from typing import Iterable, Iterator


Term = tuple[int, int, int]
Scheme = tuple[Term, ...]
Coordinate = tuple[int, int]
SignedFactor = dict[Coordinate, int]
SignedTerm = tuple[SignedFactor, SignedFactor, SignedFactor]

PINNED_COMMIT = "12c26b29a5458e173813911fb4f2c2865fba841e"
SOURCE_NAMES = (
    "structured/555.exp",
    "structured/k66ce4c614c48bda5-555-93-mod0.exp",
    "structured/666.exp",
    "structured/666r153.exp",
)
ZT_PINNED_COMMIT = "e0ec7db4cb7d7ca41abbb2c6e3bd8c7de75c7c64"
ZT_SOURCE_NAMES = (
    "schemes/results/ZT/4x4x4_m49_ZT.json",
    "schemes/results/ZT/7x7x7_m250_ZT.json",
)
EXTRA_INVENTORY = {
    7: (
        "matmul_7x7_rank248_d2952_sedoglavic_gf2.txt",
        "matmul_7x7_rank248_d2958_sedoglavic_gf2.txt",
        "matmul_7x7_rank248_d2967_leaf_canonical_gf2.txt",
        "matmul_7x7_rank248_d3015_connectivity_sedoglavic_gf2.txt",
        "matmul_7x7_rank250_d2966_gf2.txt",
    ),
}
_LINE_RE = re.compile(r"^\(([^()]*)\)\*\(([^()]*)\)\*\(([^()]*)\)$")
_ATOM_RE = re.compile(r"([+-]?)([abc])(\d)(\d)")


def popcount(value: int) -> int:
    # The Xcode Python selected by a non-login shell is still 3.9 on macOS,
    # even when a newer Homebrew Python is first on the interactive PATH.
    return bin(value).count("1")


@dataclass(frozen=True)
class Projection:
    source: Path
    n: int
    signed: tuple[SignedTerm, ...]
    terms: Scheme
    integer_exact: bool
    gf2_exact: bool

    @property
    def density(self) -> int:
        return sum(popcount(u) + popcount(v) + popcount(w)
                   for u, v, w in self.terms)

    @property
    def orbit_key(self) -> Scheme:
        return canonical_orbit(self.terms, self.n)

    @property
    def digest(self) -> str:
        payload = ";".join(f"{u},{v},{w}" for u, v, w in self.terms)
        return hashlib.sha256(payload.encode("ascii")).hexdigest()


def _parse_factor(text: str, expected_axis: str, n: int) -> SignedFactor:
    position = 0
    factor: SignedFactor = {}
    for match in _ATOM_RE.finditer(text):
        if match.start() != position:
            raise ValueError(f"malformed signed factor near {text[position:]!r}")
        position = match.end()
        sign_text, axis, row_text, column_text = match.groups()
        if axis != expected_axis:
            raise ValueError(f"expected {expected_axis} factor, found {axis}")
        row, column = int(row_text) - 1, int(column_text) - 1
        if not (0 <= row < n and 0 <= column < n):
            raise ValueError(f"{axis}{row + 1}{column + 1} is outside {n}x{n}")
        coefficient = -1 if sign_text == "-" else 1
        coordinate = (row, column)
        factor[coordinate] = factor.get(coordinate, 0) + coefficient
    if position != len(text) or not factor:
        raise ValueError(f"malformed or empty signed factor {text!r}")
    factor = {coordinate: coefficient for coordinate, coefficient in factor.items()
              if coefficient != 0}
    if not factor or any(abs(coefficient) != 1 for coefficient in factor.values()):
        raise ValueError(f"factor is not supported {{-1,0,1}} data: {text!r}")
    return factor


def parse_exp(path: Path, n: int) -> tuple[SignedTerm, ...]:
    terms: list[SignedTerm] = []
    for line_number, raw in enumerate(path.read_text().splitlines(), 1):
        line = "".join(raw.split())
        if not line:
            continue
        match = _LINE_RE.fullmatch(line)
        if match is None:
            raise ValueError(f"{path}:{line_number}: malformed .exp row")
        factors = tuple(_parse_factor(text, axis, n)
                        for text, axis in zip(match.groups(), "abc"))
        terms.append(factors)  # type: ignore[arg-type]
    if not terms:
        raise ValueError(f"{path}: no decomposition terms")
    return tuple(terms)


def square_size_from_name(path: Path) -> int:
    if len(path.name) >= 3 and path.name[:3].isdigit():
        digits = path.name[:3]
    else:
        match = re.search(r"-([2-9])([2-9])([2-9])-", path.name)
        if match is None:
            raise ValueError(f"cannot infer square dimensions from {path.name}")
        digits = "".join(match.groups())
    if len(set(digits)) != 1:
        raise ValueError(f"{path.name} is not a square tensor source")
    return int(digits[0])


def parse_zt_json(path: Path) -> tuple[int, tuple[SignedTerm, ...]]:
    data = json.loads(path.read_text())
    dimensions = data.get("n")
    if (not isinstance(dimensions, list) or len(dimensions) != 3
            or len(set(dimensions)) != 1):
        raise ValueError(f"{path}: this audit expects a square JSON scheme")
    n = dimensions[0]
    rank = data.get("m")
    matrices = (data.get("u"), data.get("v"), data.get("w"))
    if (not isinstance(n, int) or n <= 0 or not isinstance(rank, int)
            or any(not isinstance(matrix, list) or len(matrix) != rank
                   for matrix in matrices)):
        raise ValueError(f"{path}: malformed dimensions or rank")
    terms: list[SignedTerm] = []
    for term_index in range(rank):
        factors: list[SignedFactor] = []
        for axis, matrix in enumerate(matrices):
            row = matrix[term_index]
            if not isinstance(row, list) or len(row) != n * n:
                raise ValueError(f"{path}: malformed factor row {term_index}/{axis}")
            if any(type(value) is not int or value not in (-1, 0, 1) for value in row):
                raise ValueError(f"{path}: coefficient outside {{-1,0,1}}")
            factor = {(index // n, index % n): value
                      for index, value in enumerate(row) if value}
            if not factor:
                raise ValueError(f"{path}: empty factor row {term_index}/{axis}")
            factors.append(factor)
        terms.append(tuple(factors))  # type: ignore[arg-type]
    return n, tuple(terms)


def verify_integer(terms: Iterable[SignedTerm], n: int) -> tuple[bool, int, int]:
    coefficients: Counter[tuple[Coordinate, Coordinate, Coordinate]] = Counter()
    for left, right, output_dual in terms:
        for a_coordinate, a_coefficient in left.items():
            for b_coordinate, b_coefficient in right.items():
                for c_coordinate, c_coefficient in output_dual.items():
                    coefficients[(a_coordinate, b_coordinate, c_coordinate)] += (
                        a_coefficient * b_coefficient * c_coefficient)
    wanted = Counter({((i, j), (j, k), (k, i)): 1
                      for i in range(n) for j in range(n) for k in range(n)})
    keys = set(coefficients) | set(wanted)
    mismatches = sum(coefficients[key] != wanted[key] for key in keys)
    max_error = max((abs(coefficients[key] - wanted[key]) for key in keys), default=0)
    return mismatches == 0, mismatches, max_error


def project_mod2(terms: Iterable[SignedTerm], n: int) -> Scheme:
    parity: set[Term] = set()
    for left, right, output_dual in terms:
        masks = []
        for axis, factor in enumerate((left, right, output_dual)):
            mask = 0
            for (row, column), coefficient in factor.items():
                if coefficient & 1:
                    # c_ki is the trace-dual coordinate; FlipFleet's W mask
                    # addresses the output C_ik and must be transposed.
                    bit = column * n + row if axis == 2 else row * n + column
                    mask ^= 1 << bit
            if mask == 0:
                raise ValueError("signed factor projected to zero modulo two")
            masks.append(mask)
        term = (masks[0], masks[1], masks[2])
        if term in parity:
            parity.remove(term)
        else:
            parity.add(term)
    return tuple(sorted(parity))


def _set_bits(mask: int) -> Iterator[int]:
    while mask:
        low = mask & -mask
        yield low.bit_length() - 1
        mask ^= low


def tensor_support(terms: Iterable[Term]) -> set[tuple[int, int, int]]:
    support: set[tuple[int, int, int]] = set()
    for u, v, w in terms:
        for a in _set_bits(u):
            for b in _set_bits(v):
                for c in _set_bits(w):
                    coefficient = (a, b, c)
                    if coefficient in support:
                        support.remove(coefficient)
                    else:
                        support.add(coefficient)
    return support


def verify_gf2(terms: Iterable[Term], n: int) -> tuple[bool, int]:
    got = tensor_support(terms)
    wanted = {(i * n + j, j * n + k, i * n + k)
              for i in range(n) for j in range(n) for k in range(n)}
    return got == wanted, len(got ^ wanted)


def parse_gf2(path: Path) -> Scheme:
    rows: list[Term] = []
    lines = path.read_text().splitlines()
    bare = bool(lines and lines[0].strip().isdigit())
    declared_rank = int(lines[0]) if bare else None
    for index, raw in enumerate(lines):
        line = raw.strip()
        if not line:
            continue
        fields = line.split()
        if line.startswith("R ") and len(fields) == 4:
            rows.append((int(fields[1]), int(fields[2]), int(fields[3])))
        elif bare and index > 0 and len(fields) == 3:
            rows.append(tuple(map(int, fields)))  # type: ignore[arg-type]
    if declared_rank is not None and declared_rank != len(rows):
        raise ValueError(f"{path}: declared rank {declared_rank}, parsed {len(rows)}")
    if not rows:
        raise ValueError(f"{path}: no GF(2) terms")
    if len(set(rows)) != len(rows):
        raise ValueError(f"{path}: duplicate GF(2) terms")
    return tuple(sorted(rows))


def transpose(mask: int, n: int) -> int:
    result = 0
    for row in range(n):
        for column in range(n):
            if mask & (1 << (row * n + column)):
                result |= 1 << (column * n + row)
    return result


def reverse(mask: int, n: int) -> int:
    result = 0
    for row in range(n):
        for column in range(n):
            if mask & (1 << (row * n + column)):
                target = (n - 1 - row) * n + (n - 1 - column)
                result |= 1 << target
    return result


def transform_term(term: Term, n: int, code: int, reverse_indices: bool) -> Term:
    u, v, w = term
    if code == 0:
        image = (u, v, w)
    elif code == 1:
        image = (v, transpose(w, n), transpose(u, n))
    elif code == 2:
        image = (transpose(w, n), u, transpose(v, n))
    elif code == 3:
        image = (transpose(v, n), transpose(u, n), transpose(w, n))
    elif code == 4:
        image = (transpose(u, n), w, v)
    elif code == 5:
        image = (w, transpose(v, n), u)
    else:
        raise ValueError(f"invalid tensor-symmetry code {code}")
    if reverse_indices:
        image = tuple(reverse(mask, n) for mask in image)  # type: ignore[assignment]
    return image


def transform_scheme(terms: Iterable[Term], n: int, code: int,
                     reverse_indices: bool) -> Scheme:
    return tuple(sorted(transform_term(term, n, code, reverse_indices)
                        for term in terms))


def orbit_images(terms: Iterable[Term], n: int) -> Iterator[Scheme]:
    rows = tuple(terms)
    for reverse_indices in (False, True):
        for code in range(6):
            yield transform_scheme(rows, n, code, reverse_indices)


def canonical_orbit(terms: Iterable[Term], n: int) -> Scheme:
    return min(orbit_images(terms, n))


def raw_distance(left: Iterable[Term], right: Iterable[Term]) -> int:
    return len(set(left) ^ set(right))


def orbit_distance(left: Iterable[Term], right: Iterable[Term], n: int) -> tuple[int, int, bool]:
    right_set = set(right)
    best = 1 << 60
    best_code = -1
    best_reverse = False
    for reverse_indices in (False, True):
        for code in range(6):
            distance = raw_distance(transform_scheme(left, n, code, reverse_indices), right_set)
            if distance < best:
                best, best_code, best_reverse = distance, code, reverse_indices
    return best, best_code, best_reverse


def _profile_paths(profile_path: Path) -> dict[int, tuple[Path, ...]]:
    base = profile_path.parent
    result: dict[int, list[Path]] = {4: [], 5: [], 6: [], 7: []}
    inside = False
    active_n: int | None = None
    function_re = re.compile(r"^-> ffp_frontier_seed_paths\(n\)")
    n_re = re.compile(r"^  if n == ([0-9]+)$")
    path_re = re.compile(r'^    paths\.push\(base \+ "([^"]+)"\)$')
    for line in profile_path.read_text().splitlines():
        if function_re.match(line):
            inside = True
            continue
        if not inside:
            continue
        if line == "  paths":
            break
        n_match = n_re.match(line)
        if n_match:
            active_n = int(n_match.group(1))
            continue
        path_match = path_re.match(line)
        if path_match and active_n in result:
            result[active_n].append(base / path_match.group(1))
    return {n: tuple(paths) for n, paths in result.items()}


def _relation_stats(relation: Scheme, left_terms: Iterable[Term] = ()) -> dict[str, object]:
    axis_counts = [Counter(term[axis] for term in relation) for axis in range(3)]
    pairs_one = 0
    pairs_two = 0
    for left_index, left in enumerate(relation):
        for right in relation[left_index + 1:]:
            shared = sum(left[axis] == right[axis] for axis in range(3))
            pairs_one += shared >= 1
            pairs_two += shared >= 2

    # Exact-factor adjacency is the locality graph used by ordinary flips.
    parent = list(range(len(relation)))

    def find(index: int) -> int:
        while parent[index] != index:
            parent[index] = parent[parent[index]]
            index = parent[index]
        return index

    def union(left: int, right: int) -> None:
        left_root, right_root = find(left), find(right)
        if left_root != right_root:
            parent[right_root] = left_root

    buckets: dict[tuple[int, int], list[int]] = {}
    for index, term in enumerate(relation):
        for axis, factor in enumerate(term):
            bucket = buckets.setdefault((axis, factor), [])
            if bucket:
                union(index, bucket[0])
            bucket.append(index)
    components: dict[int, list[Term]] = {}
    for index, term in enumerate(relation):
        components.setdefault(find(index), []).append(term)
    component_rows = sorted((tuple(rows) for rows in components.values()),
                            key=len, reverse=True)
    zero_components = sum(not tensor_support(rows) for rows in component_rows)
    ordinary_flip_components = sum(
        len(rows) == 4
        and not tensor_support(rows)
        and any(len({term[axis] for term in rows}) == 1 for axis in range(3))
        for rows in component_rows
    )
    left_set = set(left_terms)
    component_histogram = tuple(sorted(Counter(map(len, component_rows)).items(), reverse=True))
    side_splits = tuple(sorted(Counter(
        (sum(term in left_set for term in rows),
         sum(term not in left_set for term in rows))
        for rows in component_rows
    ).items(), reverse=True)) if left_set else ()
    return {
        "terms": len(relation),
        "density": sum(popcount(mask) for term in relation for mask in term),
        "axis_unique": tuple(len(counts) for counts in axis_counts),
        "axis_max_reuse": tuple(max(counts.values(), default=0) for counts in axis_counts),
        "pairs_share_one": pairs_one,
        "pairs_share_two": pairs_two,
        "component_histogram": component_histogram,
        "zero_components": zero_components,
        "ordinary_flip_components": ordinary_flip_components,
        "side_splits": side_splits,
    }


def _format_stats(stats: dict[str, object]) -> str:
    return " ".join(f"{key}={value}" for key, value in stats.items())


def write_gf2(path: Path, terms: Scheme) -> None:
    payload = [str(len(terms))]
    payload.extend(f"{u} {v} {w}" for u, v, w in terms)
    path.write_text("\n".join(payload) + "\n")


def audit(source_repo: Path, zt_repo: Path, profile_path: Path,
          write_dir: Path | None) -> int:
    commit = subprocess.check_output(
        ("git", "-C", str(source_repo), "rev-parse", "HEAD"), text=True).strip()
    if commit != PINNED_COMMIT:
        raise ValueError(f"source checkout is {commit}, expected {PINNED_COMMIT}")

    archive_paths = _profile_paths(profile_path)
    archives: dict[int, list[tuple[Path, Scheme]]] = {
        n: [] for n in archive_paths
    }
    for n, paths in archive_paths.items():
        for path in paths:
            terms = parse_gf2(path)
            valid, mismatch = verify_gf2(terms, n)
            if not valid:
                raise ValueError(f"archive seed {path} failed GF(2) gate ({mismatch} mismatches)")
            archives[n].append((path, terms))
    inventory = {n: list(rows) for n, rows in archives.items()}
    certificate_dir = profile_path.parent
    for n, names in EXTRA_INVENTORY.items():
        for name in names:
            path = certificate_dir / name
            terms = parse_gf2(path)
            valid, mismatch = verify_gf2(terms, n)
            if not valid:
                raise ValueError(f"inventory seed {path} failed GF(2) gate ({mismatch} mismatches)")
            inventory[n].append((path, terms))

    zt_commit = subprocess.check_output(
        ("git", "-C", str(zt_repo), "rev-parse", "HEAD"), text=True).strip()
    if zt_commit != ZT_PINNED_COMMIT:
        raise ValueError(f"ZT source checkout is {zt_commit}, expected {ZT_PINNED_COMMIT}")

    projections: list[Projection] = []
    sources: list[tuple[str, Path, int, tuple[SignedTerm, ...], str]] = []
    for relative_name in SOURCE_NAMES:
        source = source_repo / relative_name
        n = square_size_from_name(source)
        sources.append((relative_name, source, n, parse_exp(source, n), commit))
    for relative_name in ZT_SOURCE_NAMES:
        source = zt_repo / relative_name
        n, signed = parse_zt_json(source)
        sources.append((relative_name, source, n, signed, zt_commit))

    for relative_name, source, n, signed, source_commit in sources:
        integer_exact, integer_mismatch, max_error = verify_integer(signed, n)
        terms = project_mod2(signed, n)
        gf2_exact, gf2_mismatch = verify_gf2(terms, n)
        projection = Projection(source, n, signed, terms, integer_exact, gf2_exact)
        projections.append(projection)
        print(
            f"SIGNED_PROJECTION source={relative_name} commit={source_commit} "
            f"source_sha256={hashlib.sha256(source.read_bytes()).hexdigest()} lines={len(signed)} "
            f"rank={len(terms)} density={projection.density} integer_exact={int(integer_exact)} "
            f"integer_mismatch={integer_mismatch} max_error={max_error} "
            f"gf2_exact={int(gf2_exact)} gf2_mismatch={gf2_mismatch} sha256={projection.digest}"
        )
        if not integer_exact or not gf2_exact:
            continue

        nearest: tuple[int, int, Path, int, bool, Scheme] | None = None
        for archive_path, archive_terms in archives[n]:
            raw = raw_distance(terms, archive_terms)
            orbit, code, reversed_indices = orbit_distance(terms, archive_terms, n)
            print(
                f"SIGNED_DISTANCE source={relative_name} archive={archive_path.name} "
                f"raw={raw} orbit={orbit} code={code} reverse={int(reversed_indices)} "
                f"archive_density={sum(popcount(mask) for term in archive_terms for mask in term)}"
            )
            candidate = (orbit, raw, archive_path, code, reversed_indices, archive_terms)
            if nearest is None or candidate[:2] < nearest[:2]:
                nearest = candidate

        matching_inventory = [
            path for path, known_terms in inventory[n]
            if projection.orbit_key == canonical_orbit(known_terms, n)
        ]
        canonical_match = bool(matching_inventory)
        for matching_path in matching_inventory:
            print(
                f"SIGNED_INVENTORY_MATCH source={relative_name} "
                f"inventory={matching_path.name} orbit=0"
            )
        assert nearest is not None
        orbit, raw, nearest_path, code, reversed_indices, nearest_terms = nearest
        aligned = transform_scheme(terms, n, code, reversed_indices)
        relation = tuple(sorted(set(aligned) ^ set(nearest_terms)))
        relation_zero = not tensor_support(relation)
        stats = _relation_stats(relation)

        archive_pair_distances = [
            orbit_distance(left_terms, right_terms, n)[0]
            for left_index, (_, left_terms) in enumerate(archives[n])
            for _, right_terms in archives[n][left_index + 1:]
        ]
        baseline = (
            min(archive_pair_distances, default=0),
            int(statistics.median(archive_pair_distances)) if archive_pair_distances else 0,
            max(archive_pair_distances, default=0),
        )

        positive_neighbors: list[tuple[int, int, Path, int, bool, Scheme]] = []
        for archive_path, archive_terms in archives[n]:
            neighbor_orbit, neighbor_code, neighbor_reverse = orbit_distance(
                terms, archive_terms, n)
            if neighbor_orbit > 0:
                positive_neighbors.append((
                    neighbor_orbit,
                    raw_distance(terms, archive_terms),
                    archive_path,
                    neighbor_code,
                    neighbor_reverse,
                    archive_terms,
                ))
        if positive_neighbors:
            (positive_orbit, positive_raw, positive_path, positive_code,
             positive_reverse, positive_terms) = min(positive_neighbors)
            positive_aligned = transform_scheme(terms, n, positive_code, positive_reverse)
            positive_relation = tuple(sorted(set(positive_aligned) ^ set(positive_terms)))
            print(
                f"SIGNED_NEAREST_NONZERO source={relative_name} archive={positive_path.name} "
                f"raw={positive_raw} orbit={positive_orbit} code={positive_code} "
                f"reverse={int(positive_reverse)} relation_zero="
                f"{int(not tensor_support(positive_relation))} "
                f"{_format_stats(_relation_stats(positive_relation, positive_aligned))}"
            )

        leader_path, leader_terms = archives[n][0]
        leader_orbit, leader_code, leader_reverse = orbit_distance(terms, leader_terms, n)
        leader_aligned = transform_scheme(terms, n, leader_code, leader_reverse)
        leader_relation = tuple(sorted(set(leader_aligned) ^ set(leader_terms)))
        print(
            f"SIGNED_LEADER_RELATION source={relative_name} leader={leader_path.name} "
            f"raw={raw_distance(terms, leader_terms)} orbit={leader_orbit} code={leader_code} "
            f"reverse={int(leader_reverse)} relation_zero="
            f"{int(not tensor_support(leader_relation))} "
            f"{_format_stats(_relation_stats(leader_relation, leader_aligned))}"
        )
        print(
            f"SIGNED_NEAREST source={relative_name} archive={nearest_path.name} raw={raw} "
            f"orbit={orbit} code={code} reverse={int(reversed_indices)} "
            f"canonical_match={int(canonical_match)} relation_zero={int(relation_zero)} "
            f"archive_orbit_baseline={baseline[0]}/{baseline[1]}/{baseline[2]} "
            f"{_format_stats(stats)}"
        )

        if write_dir is not None and not canonical_match:
            write_dir.mkdir(parents=True, exist_ok=True)
            source_tag = source.stem.replace("r", "_r").replace("_ZT", "_zt")
            output = write_dir / (
                f"matmul_{n}x{n}_rank{len(terms)}_d{projection.density}_"
                f"signed_{source_tag}_gf2.txt")
            write_gf2(output, terms)
            reloaded = parse_gf2(output)
            reload_exact, reload_mismatch = verify_gf2(reloaded, n)
            if reloaded != terms or not reload_exact:
                output.unlink(missing_ok=True)
                raise ValueError(f"serialized projection failed reload gate ({reload_mismatch})")
            print(f"SIGNED_PUBLISH source={relative_name} output={output} reload_exact=1")

    for left_index, left in enumerate(projections):
        for right in projections[left_index + 1:]:
            if left.n != right.n or not left.gf2_exact or not right.gf2_exact:
                continue
            distance, code, reversed_indices = orbit_distance(left.terms, right.terms, left.n)
            aligned = transform_scheme(left.terms, left.n, code, reversed_indices)
            relation = tuple(sorted(set(aligned) ^ set(right.terms)))
            print(
                f"SIGNED_CROSS_DISTANCE left={left.source.name} right={right.source.name} "
                f"orbit={distance} code={code} reverse={int(reversed_indices)} "
                f"relation_zero={int(not tensor_support(relation))} {_format_stats(_relation_stats(relation))}"
            )
    return 0 if all(projection.integer_exact and projection.gf2_exact
                    for projection in projections) else 1


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-repo", type=Path, default=Path("/tmp/matrix-multiplication"))
    parser.add_argument(
        "--zt-repo", type=Path, default=Path("/tmp/FastMatrixMultiplication-current"),
    )
    parser.add_argument(
        "--profiles", type=Path,
        default=Path(__file__).with_name("flipfleet_profiles.w"),
    )
    parser.add_argument(
        "--write-dir", type=Path,
        help="write independently gated projections that are new tensor-symmetry orbits",
    )
    args = parser.parse_args()
    return audit(args.source_repo, args.zt_repo, args.profiles, args.write_dir)


if __name__ == "__main__":
    raise SystemExit(main())
