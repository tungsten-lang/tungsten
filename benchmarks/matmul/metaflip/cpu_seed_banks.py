"""Exact, bounded seed banks for diverse FlipFleet CPU restarts.

``NearFrontierBank`` deliberately lives outside the fleet coordinator.  It
retains exact schemes one or two ranks above a moving frontier without making
them frontier candidates.  Each rank tier is bounded, enforces a quota per
factor-reuse signature, and uses raw term-set symmetric difference as its
novelty metric.  Selection is least-used with deterministic, caller-supplied
tie breaking, so a walker id can keep a stable restart lineage without relying
on Python's randomized hash seed.

``build_symmetry_move_bank`` constructs the other useful CPU detour: exact
C3-closed schemes reached by exactly one orbit split or polarization.  These
moves normally cost more than two ranks, so they are intentionally kept out of
the numeric near-frontier tiers.  Every returned entry is independently tensor
verified, C3 checked, and replayed from its declared move provenance.
"""

from __future__ import annotations

from collections import Counter
from dataclasses import dataclass, field
import hashlib
from typing import Iterable, Mapping, Optional

from bench_decomp import cost, verify as independent_verify
from escape_portfolio import (
    PortfolioEntry,
    build_portfolio,
    canonical,
    profile_scheme,
    replay_moves,
    scheme_digest,
    validate_scheme_masks,
)
from sym_escape import is_c3_closed


Term = tuple[int, int, int]
SchemeKey = tuple[Term, ...]
StructuralSignature = tuple[tuple[int, ...], tuple[int, ...], tuple[int, ...]]

NEAR_DELTAS = (1, 2)
SYMMETRY_RECIPES = (("orbit-split",), ("polarize",))
_SINGLETON_QUALITY_DISTANCE = 1 << 60


def raw_novelty(left: Iterable[Term], right: Iterable[Term]) -> int:
    """Return raw term-set symmetric-difference distance."""
    return len(frozenset(left).symmetric_difference(frozenset(right)))


def structural_signature(terms: Iterable[Term]) -> StructuralSignature:
    """Describe factor reuse without depending on the actual factor labels.

    For each stored axis the signature records the descending multiset of
    factor-bucket sizes.  It distinguishes which axis supplies ordinary flip
    pairs while treating coordinate relabelings with the same connectivity as
    one structural family.
    """
    scheme = tuple(terms)
    return tuple(  # type: ignore[return-value]
        tuple(sorted(Counter(term[axis] for term in scheme).values(), reverse=True))
        for axis in range(3)
    )


@dataclass
class NearSeed:
    """One independently exact restart seed retained by a near-frontier bank."""

    terms: SchemeKey
    rank: int
    delta: int
    bits: int
    digest: str
    signature: StructuralSignature
    c3: Optional[bool]
    source: str
    metadata: dict = field(default_factory=dict)
    uses: int = 0
    successes: int = 0
    best_result_rank: Optional[int] = None
    _termset: frozenset[Term] = field(init=False, repr=False)

    def __post_init__(self) -> None:
        self._termset = frozenset(self.terms)

    @property
    def termset(self) -> frozenset[Term]:
        return self._termset

    def as_status(self) -> dict:
        return {
            "rank": self.rank,
            "delta": self.delta,
            "bits": self.bits,
            "digest": self.digest,
            "c3": self.c3,
            "source": self.source,
            "uses": self.uses,
            "successes": self.successes,
            "best_result_rank": self.best_result_rank,
            "signature": [list(axis) for axis in self.signature],
            "metadata": dict(self.metadata),
        }


class NearFrontierBank:
    """Maintain bounded exact seeds at ``best_rank + 1`` and ``+2``.

    ``capacity`` is the total bound.  The +1 tier receives the extra slot when
    it is odd.  ``signature_quota`` applies independently within each tier.
    Invalid or out-of-band candidates are rejected and counted; they are never
    partially installed.
    """

    def __init__(
        self,
        n: int,
        best_rank: int,
        capacity: int = 64,
        signature_quota: int = 4,
        m: Optional[int] = None,
        p: Optional[int] = None,
    ) -> None:
        m = n if m is None else m
        p = n if p is None else p
        if any(isinstance(value, bool) or not isinstance(value, int) or value <= 0
               for value in (n, m, p)):
            raise ValueError("tensor dimensions must be positive integers")
        if any(width >= 63 for width in (n * m, m * p, n * p)):
            raise ValueError("factor masks must use fewer than 63 signed-i64 bits")
        if isinstance(best_rank, bool) or not isinstance(best_rank, int) or best_rank <= 0:
            raise ValueError("best_rank must be a positive integer")
        if isinstance(capacity, bool) or not isinstance(capacity, int) or capacity < 2:
            raise ValueError("capacity must be an integer of at least two")
        if (isinstance(signature_quota, bool) or
                not isinstance(signature_quota, int) or signature_quota <= 0):
            raise ValueError("signature_quota must be a positive integer")

        self.n, self.m, self.p = n, m, p
        self.best_rank = best_rank
        self.capacity = capacity
        self.capacities = {1: (capacity + 1) // 2, 2: capacity // 2}
        self.signature_quota = signature_quota
        self._tiers: dict[int, dict[SchemeKey, NearSeed]] = {1: {}, 2: {}}
        self.counters: Counter = Counter()
        self.last_rejection: Optional[str] = None

    def _canonical_exact(
        self, terms: Iterable[Term], expected_rank: Optional[int] = None
    ) -> SchemeKey:
        try:
            rows = tuple(tuple(term) for term in terms)
        except (TypeError, ValueError) as exc:
            raise ValueError("scheme must be an iterable of three-mask terms") from exc
        limits = (1 << (self.n * self.m),
                  1 << (self.m * self.p),
                  1 << (self.n * self.p))
        for index, term in enumerate(rows):
            if len(term) != 3:
                raise ValueError(f"term {index} must contain exactly three masks")
            for axis, (mask, limit) in enumerate(zip(term, limits)):
                if (isinstance(mask, bool) or not isinstance(mask, int) or
                        mask <= 0 or mask >= limit):
                    raise ValueError(
                        f"term {index} axis {axis} mask is outside [1,{limit})")
        key = tuple(sorted(rows))
        if len(set(key)) != len(key):
            raise ValueError("scheme contains duplicate rank-one terms")
        if expected_rank is not None and expected_rank != len(key):
            raise ValueError(
                f"scheme rank {len(key)} does not match expected rank {expected_rank}")
        if not independent_verify(key, self.n, self.m, self.p):
            raise ValueError("scheme is not the requested matrix-multiplication tensor")
        return key

    def _entry_from_terms(
        self,
        terms: Iterable[Term],
        source: str,
        metadata: Optional[Mapping] = None,
        expected_rank: Optional[int] = None,
        best_rank: Optional[int] = None,
    ) -> NearSeed:
        if not isinstance(source, str) or not source:
            raise ValueError("source must be a nonempty string")
        if metadata is not None and not isinstance(metadata, Mapping):
            raise ValueError("metadata must be a mapping")
        key = self._canonical_exact(terms, expected_rank)
        frontier = self.best_rank if best_rank is None else best_rank
        rank = len(key)
        return NearSeed(
            terms=key,
            rank=rank,
            delta=rank - frontier,
            bits=cost(key, self.n, self.m, self.p)["bits"],
            digest=scheme_digest(key),
            signature=structural_signature(key),
            c3=(is_c3_closed(key, self.n)
                if self.n == self.m == self.p else None),
            source=source,
            metadata=dict(metadata or {}),
        )

    @staticmethod
    def _set_quality(entries: Iterable[NearSeed]) -> tuple[int, int, int]:
        rows = tuple(entries)
        if len(rows) <= 1:
            return (_SINGLETON_QUALITY_DISTANCE, 0,
                    -sum(entry.bits for entry in rows))
        nearest = []
        for left_index, left in enumerate(rows):
            distances = [
                raw_novelty(left.termset, right.termset)
                for right_index, right in enumerate(rows)
                if left_index != right_index
            ]
            nearest.append(min(distances))
        return min(nearest), sum(nearest), -sum(entry.bits for entry in rows)

    @staticmethod
    def _signature_counts(entries: Iterable[NearSeed]) -> Counter:
        return Counter(entry.signature for entry in entries)

    @classmethod
    def _replacement_qualities(
        cls,
        current: Iterable[NearSeed],
        entry: NearSeed,
        victims: Iterable[NearSeed],
    ) -> tuple[tuple[int, int, int], dict[SchemeKey, tuple[int, int, int]]]:
        """Score every one-for-one replacement in quadratic, not cubic, work."""
        rows = tuple(current)
        victim_rows = tuple(victims)
        current_quality = cls._set_quality(rows)
        if len(rows) <= 1:
            return current_quality, {
                victim.terms: cls._set_quality((entry,))
                for victim in victim_rows
            }

        count = len(rows)
        infinity = _SINGLETON_QUALITY_DISTANCE
        distances = [[infinity] * count for _ in range(count)]
        for left_index, left in enumerate(rows):
            for right_index in range(left_index + 1, count):
                distance = raw_novelty(
                    left.termset, rows[right_index].termset)
                distances[left_index][right_index] = distance
                distances[right_index][left_index] = distance

        nearest = []
        nearest_counts = []
        second = []
        for index in range(count):
            values = [distances[index][other]
                      for other in range(count) if other != index]
            first = min(values)
            nearest.append(first)
            nearest_counts.append(values.count(first))
            second.append(min((value for value in values if value > first),
                              default=infinity))

        candidate_distances = [
            raw_novelty(entry.termset, row.termset) for row in rows
        ]
        index_by_terms = {row.terms: index for index, row in enumerate(rows)}
        current_bits = sum(row.bits for row in rows)
        qualities = {}
        for victim in victim_rows:
            victim_index = index_by_terms[victim.terms]
            resulting_nearest = []
            for index in range(count):
                if index == victim_index:
                    continue
                old_nearest = nearest[index]
                if (distances[index][victim_index] == old_nearest and
                        nearest_counts[index] == 1):
                    old_nearest = second[index]
                resulting_nearest.append(
                    min(old_nearest, candidate_distances[index]))
            resulting_nearest.append(min(
                candidate_distances[index] for index in range(count)
                if index != victim_index))
            qualities[victim.terms] = (
                min(resulting_nearest),
                sum(resulting_nearest),
                -(current_bits - victim.bits + entry.bits),
            )
        return current_quality, qualities

    def _reject(self, reason: str) -> bool:
        self.last_rejection = reason
        self.counters[reason] += 1
        return False

    def _admit_entry(self, entry: NearSeed) -> bool:
        if entry.delta not in NEAR_DELTAS:
            return self._reject("out_of_band")
        if any(entry.terms in tier for tier in self._tiers.values()):
            return self._reject("duplicate")

        tier = self._tiers[entry.delta]
        capacity = self.capacities[entry.delta]
        signatures = self._signature_counts(tier.values())
        if (len(tier) < capacity and
                signatures[entry.signature] < self.signature_quota):
            tier[entry.terms] = entry
            self.last_rejection = None
            self.counters["admitted"] += 1
            return True

        current = tuple(tier.values())
        best_victim = None
        best_quality = None
        # If the new signature is at quota, only one member of that family may
        # leave.  Otherwise a full tier may evict any member.
        victims = [
            victim for victim in current
            if (signatures[entry.signature] < self.signature_quota or
                victim.signature == entry.signature)
        ]
        current_quality, replacement_qualities = self._replacement_qualities(
            current, entry, victims)
        for victim in victims:
            replacement = tuple(row for row in current if row.terms != victim.terms) + (entry,)
            replacement_signatures = self._signature_counts(replacement)
            if max(replacement_signatures.values(), default=0) > self.signature_quota:
                continue
            quality = replacement_qualities[victim.terms]
            if (best_quality is None or quality > best_quality or
                    (quality == best_quality and
                     (victim.bits, victim.digest) >
                     (best_victim.bits, best_victim.digest))):
                best_quality = quality
                best_victim = victim

        if best_victim is None or best_quality is None or best_quality <= current_quality:
            reason = ("signature_quota" if
                      signatures[entry.signature] >= self.signature_quota and
                      len(tier) < capacity else "novelty")
            return self._reject(reason)

        del tier[best_victim.terms]
        tier[entry.terms] = entry
        self.last_rejection = None
        self.counters["admitted"] += 1
        self.counters["evicted"] += 1
        return True

    def admit(
        self,
        terms: Iterable[Term],
        source: str = "candidate",
        metadata: Optional[Mapping] = None,
        expected_rank: Optional[int] = None,
    ) -> bool:
        """Exact-gate and possibly retain one +1/+2 candidate.

        Malformed, rank-mismatched, or tensor-invalid candidates return
        ``False`` and increment ``invalid``.  A valid but out-of-band or
        insufficiently novel candidate is likewise rejected with a more
        specific counter in :meth:`status`.
        """
        try:
            entry = self._entry_from_terms(
                terms, source, metadata, expected_rank=expected_rank)
        except (TypeError, ValueError) as exc:
            self.counters["invalid"] += 1
            self.last_rejection = f"invalid: {exc}"
            return False
        return self._admit_entry(entry)

    def entries(self, delta: Optional[int] = None) -> tuple[NearSeed, ...]:
        """Return retained entries in deterministic order."""
        if delta is not None and delta not in NEAR_DELTAS:
            raise ValueError("delta must be 1 or 2")
        deltas = NEAR_DELTAS if delta is None else (delta,)
        return tuple(sorted(
            (entry for item in deltas for entry in self._tiers[item].values()),
            key=lambda entry: (entry.delta, entry.digest),
        ))

    @staticmethod
    def _stable_selection_key(stable_key, entry: NearSeed) -> bytes:
        material = f"{stable_key!r}:{entry.digest}".encode("utf-8")
        return hashlib.blake2b(material, digest_size=16).digest()

    def select(self, delta: int, stable_key=0) -> Optional[NearSeed]:
        """Select a least-used seed with deterministic tie breaking.

        Passing a stable walker id makes repeated campaigns with the same bank
        assign the same sequence while the least-used rule keeps all retained
        doors within one use of each other.
        """
        if delta not in NEAR_DELTAS:
            raise ValueError("delta must be 1 or 2")
        tier = tuple(self._tiers[delta].values())
        if not tier:
            return None
        least_used = min(entry.uses for entry in tier)
        pool = [entry for entry in tier if entry.uses == least_used]
        selected = min(
            pool, key=lambda entry: self._stable_selection_key(stable_key, entry))
        selected.uses += 1
        self.counters["selections"] += 1
        return selected

    def mark_success(
        self, seed: NearSeed, resulting_rank: Optional[int] = None
    ) -> bool:
        """Record a useful descent from a still-retained selected seed."""
        stored = self._tiers.get(seed.delta, {}).get(seed.terms)
        if stored is None:
            return False
        if (resulting_rank is not None and
                (isinstance(resulting_rank, bool) or
                 not isinstance(resulting_rank, int) or resulting_rank <= 0)):
            raise ValueError("resulting_rank must be a positive integer")
        stored.successes += 1
        if resulting_rank is not None:
            stored.best_result_rank = (
                resulting_rank if stored.best_result_rank is None else
                min(stored.best_result_rank, resulting_rank))
        self.counters["successes"] += 1
        return True

    def _farthest_subset(
        self, candidates: Iterable[NearSeed], capacity: int
    ) -> tuple[NearSeed, ...]:
        remaining = {entry.terms: entry for entry in candidates}
        selected = []
        signatures: Counter = Counter()
        while remaining and len(selected) < capacity:
            eligible = [
                entry for entry in remaining.values()
                if signatures[entry.signature] < self.signature_quota
            ]
            if not eligible:
                break
            if not selected:
                chosen = min(eligible, key=lambda entry: (entry.bits, entry.digest))
            else:
                chosen = min(
                    eligible,
                    key=lambda entry: (
                        -min(raw_novelty(entry.termset, old.termset)
                             for old in selected),
                        entry.bits,
                        entry.digest,
                    ),
                )
            selected.append(chosen)
            signatures[chosen.signature] += 1
            del remaining[chosen.terms]
        return tuple(selected)

    def rebase(
        self, new_best: int, old_frontier: Iterable[Iterable[Term]] = ()
    ) -> dict:
        """Atomically reclassify retained seeds around a lower frontier.

        Exact old-frontier schemes commonly become the new +1 tier after a
        one-rank improvement.  Existing +1 seeds then become +2.  Schemes
        outside the new two-rank window are dropped, and both tiers are rebuilt
        by deterministic farthest-first raw novelty under the signature quota.
        Selection-use counters reset because the rank roles have changed;
        historical success metadata is preserved.
        """
        if (isinstance(new_best, bool) or not isinstance(new_best, int) or
                new_best <= 0 or new_best > self.best_rank):
            raise ValueError("new_best must be positive and no greater than best_rank")

        candidate_by_key: dict[SchemeKey, NearSeed] = {}
        for old in self.entries():
            delta = old.rank - new_best
            if delta not in NEAR_DELTAS:
                continue
            metadata = dict(old.metadata)
            metadata.setdefault("rebased_from_delta", old.delta)
            candidate_by_key[old.terms] = NearSeed(
                terms=old.terms,
                rank=old.rank,
                delta=delta,
                bits=old.bits,
                digest=old.digest,
                signature=old.signature,
                c3=old.c3,
                source=old.source,
                metadata=metadata,
                successes=old.successes,
                best_result_rank=old.best_result_rank,
            )

        frontier_count = 0
        for index, terms in enumerate(old_frontier):
            try:
                entry = self._entry_from_terms(
                    terms,
                    "old-frontier",
                    {"frontier_rank": self.best_rank, "frontier_index": index},
                    best_rank=new_best,
                )
            except (TypeError, ValueError) as exc:
                raise ValueError(
                    f"old_frontier entry {index} failed exact verification: {exc}") from exc
            if entry.delta in NEAR_DELTAS:
                candidate_by_key[entry.terms] = entry
                frontier_count += 1

        new_tiers: dict[int, dict[SchemeKey, NearSeed]] = {1: {}, 2: {}}
        for delta in NEAR_DELTAS:
            candidates = [entry for entry in candidate_by_key.values()
                          if entry.delta == delta]
            selected = self._farthest_subset(candidates, self.capacities[delta])
            new_tiers[delta] = {entry.terms: entry for entry in selected}

        before = sum(len(tier) for tier in self._tiers.values())
        eligible = len(candidate_by_key)
        self.best_rank = new_best
        self._tiers = new_tiers
        self.counters["rebases"] += 1
        self.last_rejection = None
        after = sum(len(tier) for tier in self._tiers.values())
        return {
            "best_rank": new_best,
            "before": before,
            "eligible": eligible,
            "retained": after,
            "dropped": max(0, eligible - after),
            "old_frontier_admitted": frontier_count,
        }

    def minimum_distance(self, delta: int) -> Optional[int]:
        if delta not in NEAR_DELTAS:
            raise ValueError("delta must be 1 or 2")
        entries = tuple(self._tiers[delta].values())
        if len(entries) < 2:
            return None
        return min(
            raw_novelty(left.termset, right.termset)
            for index, left in enumerate(entries)
            for right in entries[index + 1:]
        )

    def status(self) -> dict:
        """Return JSON-serializable bank state and admission counters."""
        tiers = {}
        for delta in NEAR_DELTAS:
            entries = self.entries(delta)
            signatures = self._signature_counts(entries)
            tiers[f"+{delta}"] = {
                "rank": self.best_rank + delta,
                "size": len(entries),
                "capacity": self.capacities[delta],
                "minimum_distance": self.minimum_distance(delta),
                "least_uses": min((entry.uses for entry in entries), default=0),
                "most_uses": max((entry.uses for entry in entries), default=0),
                "signature_counts": [
                    {"signature": [list(axis) for axis in signature], "count": count}
                    for signature, count in sorted(signatures.items())
                ],
                "entries": [entry.as_status() for entry in entries],
            }
        return {
            "best_rank": self.best_rank,
            "size": sum(len(tier) for tier in self._tiers.values()),
            "capacity": self.capacity,
            "signature_quota": self.signature_quota,
            "tiers": tiers,
            "counters": dict(sorted(self.counters.items())),
            "last_rejection": self.last_rejection,
        }


def build_symmetry_move_bank(
    c3_terms: Iterable[Term], n: int, count: int
) -> tuple[PortfolioEntry, ...]:
    """Build up to ``count`` exact, one-move C3-preserving escape entries.

    The returned entries contain no base slot.  Each has exactly one declared
    ``orbit-split`` or ``polarize`` move that replays from ``c3_terms`` to its
    complete materialized scheme.
    """
    if isinstance(n, bool) or not isinstance(n, int) or n <= 0:
        raise ValueError("n must be a positive integer")
    if n * n >= 63:
        raise ValueError("factor masks must use fewer than 63 signed-i64 bits")
    if isinstance(count, bool) or not isinstance(count, int) or count <= 0:
        raise ValueError("count must be a positive integer")

    try:
        rows = tuple(tuple(term) for term in c3_terms)
    except (TypeError, ValueError) as exc:
        raise ValueError("c3_terms must be an iterable of three-mask terms") from exc
    validate_scheme_masks(rows, n, "C3 source")
    base = canonical(rows)
    if len(base) != len(rows):
        raise ValueError("C3 source must contain distinct nonzero terms")
    if not independent_verify(base, n, n, n):
        raise ValueError("C3 source is not an exact matrix-multiplication tensor")
    if not is_c3_closed(base, n):
        raise ValueError("C3 source is not closed under the cyclic symmetry")

    entries = build_portfolio(
        base,
        n,
        count=count,
        per_step=max(8, min(64, count * 2)),
        recipes=SYMMETRY_RECIPES,
        include_base=False,
    )
    checked = []
    seen = set()
    for index, entry in enumerate(entries):
        if entry.recipe not in SYMMETRY_RECIPES:
            raise RuntimeError(f"symmetry bank slot {index} has an illegal recipe")
        if len(entry.moves) != 1 or entry.moves[0].kind != entry.recipe[0]:
            raise RuntimeError(f"symmetry bank slot {index} lacks one-move provenance")
        replayed = replay_moves(base, entry.moves, n)
        if replayed != entry.scheme:
            raise RuntimeError(f"symmetry bank slot {index} provenance does not replay")
        validate_scheme_masks(entry.scheme, n, f"symmetry bank slot {index}")
        if entry.scheme in seen:
            raise RuntimeError(f"symmetry bank slot {index} duplicates an earlier slot")
        if not independent_verify(entry.scheme, n, n, n):
            raise RuntimeError(f"symmetry bank slot {index} is not tensor-exact")
        if not is_c3_closed(entry.scheme, n):
            raise RuntimeError(f"symmetry bank slot {index} lost C3 closure")
        actual_profile = profile_scheme(entry.scheme, base, n)
        if entry.profile != actual_profile or not actual_profile["c3"]:
            raise RuntimeError(f"symmetry bank slot {index} has a false profile")
        seen.add(entry.scheme)
        checked.append(entry)
    return tuple(checked)
