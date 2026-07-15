"""Square-tensor parsing and evidence-guided FlipFleet defaults.

This module is deliberately independent of :mod:`flipfleet`, so its CLI and
coordinator can consume the same validated configuration without introducing
an import cycle.  ``--tensor`` denotes square matrix multiplication using the
compact spelling ``NxN``; the resulting tensor dimensions are ``<N,N,N>``.

The role weights are starting recommendations, not claims that the fractions
themselves have been experimentally optimized.  Sizes 3--6 use the measured
campaign outcomes recorded in ``FINDINGS.md``.  Size 7 is a conservative,
diverse extrapolation.  Adaptive feedback is expected to move weight after
useful exact candidates are observed.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import math
import os
import re
import unicodedata
from typing import Mapping


HERE = os.path.dirname(os.path.abspath(__file__))

# A square factor occupies N*N bits.  The Tungsten/Metal path intentionally
# keeps the sign bit and the next-highest bit clear, matching validate_format
# and gpu_simdgroup_gen: factor widths must be strictly less than 63.
MIN_SQUARE_SIZE = 3
MAX_FACTOR_BITS = 62
MAX_SQUARE_SIZE = math.isqrt(MAX_FACTOR_BITS)  # 7; 8x8 needs 64 bits.

KNOWN_RECORD_RANKS = {3: 23, 4: 47, 5: 93, 6: 153, 7: 247}
KNOWN_RECORD_SEEDS = {
    3: os.path.join(HERE, "matmul_3x3_rank23_d139_gf2.txt"),
    4: os.path.join(HERE, "matmul_4x4_rank47_d450_gf2.txt"),
    5: os.path.join(HERE, "matmul_5x5_rank93_d968_global_isotropy_gf2.txt"),
    6: os.path.join(HERE, "matmul_6x6_rank153_d1860_global_isotropy_gf2.txt"),
    7: os.path.join(HERE, "matmul_7x7_rank247_d3098_global_isotropy_gf2.txt"),
}
KNOWN_C3_SEEDS = {
    # The new density leaders are generic GL-normalized presentations.  Keep
    # the independently exact C3 frontiers as alternate symmetry-role seeds.
    5: os.path.join(HERE, "matmul_5x5_rank93_d1155_gf2.txt"),
    6: os.path.join(HERE, "matmul_6x6_rank153_d2502_gf2.txt"),
}

# One unified namespace lets the allocator divide all available GPU capacity
# before each engine rounds its share to a legal threadgroup/SIMDgroup shape.
ROLE_KEYS = (
    "rank", "density", "symmetry",
    "split", "break", "orbit", "polarize", "compose",
    "novelty", "simd", "mitm",
)

# Percent weights.  Zeros are intentional eligibility decisions.  In
# particular, the tracked 3x3 and 4x4 record seeds are neither C3-closed nor
# fixed-cube-bearing, so C3/fixed-only work must not receive lanes by default.
_ROLE_WEIGHTS = {
    # Mined/composed escape -> new basin -> cooperative density 266 -> 139.
    3: (18, 15, 0, 12, 0, 0, 0, 15, 10, 25, 5),
    # Isolated zero-flip-pair record; direct SIMD and primitive-five probes
    # were neutral, so deeper escapes, novelty, and MITM get more capacity.
    4: (20, 5, 0, 15, 0, 0, 0, 20, 15, 10, 15),
    # Default record is C3/fixed-cube eligible; scan SIMD measured +50% over
    # hash and the earlier density relay repeatedly improved this frontier.
    5: (15, 15, 12, 6, 5, 7, 6, 8, 7, 15, 4),
    # Keep a smaller C3 share (bounded C3 probes were neutral), while hash SIMD
    # was +9.5% and first improved density 2512 -> 2508; the native mixed CPU
    # fleet subsequently reached the exact density-2502 representative.
    6: (16, 16, 6, 7, 5, 6, 6, 10, 8, 16, 4),
}
_FALLBACK_WEIGHTS = (18, 10, 10, 8, 6, 7, 7, 10, 8, 12, 4)

_BASIS = {
    3: "measured 3x3 mined-escape and cooperative-SIMD campaign",
    4: "measured 4x4 isolated-frontier, SIMD, and surgery negatives",
    5: "measured 5x5 C3, density-relay, and scan-vs-hash campaigns",
    6: "measured 6x6 C3, density-relay, and scan-vs-hash campaigns",
}

_TENSOR_RE = re.compile(r"^\s*([0-9]+)\s*([x\u00d7\u2715\u2a09])\s*([0-9]+)\s*$",
                        re.IGNORECASE)


def validate_square_size(n: int) -> None:
    """Validate a square format against the current signed-i64 mask ABI."""
    if isinstance(n, bool) or not isinstance(n, int):
        raise ValueError("tensor size must be an integer")
    if n < MIN_SQUARE_SIZE:
        raise ValueError(f"tensor size must be at least {MIN_SQUARE_SIZE}")
    factor_bits = n * n
    if factor_bits >= 63:
        raise ValueError(
            f"{n}x{n} needs {factor_bits} factor bits; signed-i64 factors "
            f"support at most {MAX_FACTOR_BITS} (maximum square is "
            f"{MAX_SQUARE_SIZE}x{MAX_SQUARE_SIZE})")


@dataclass(frozen=True)
class TensorSpec:
    """Validated square matrix-multiplication tensor dimensions."""

    n: int
    m: int
    p: int

    def __post_init__(self) -> None:
        if self.n != self.m or self.m != self.p:
            raise ValueError("--tensor requires a square NxN format")
        validate_square_size(self.n)

    @classmethod
    def square(cls, n: int) -> "TensorSpec":
        return cls(n, n, n)

    @property
    def size(self) -> int:
        return self.n

    @property
    def label(self) -> str:
        return f"{self.n}x{self.n}"

    @property
    def tensor_label(self) -> str:
        return f"<{self.n},{self.n},{self.n}>"

    @property
    def dimensions(self) -> tuple[int, int, int]:
        return self.n, self.m, self.p

    @property
    def factor_bits(self) -> int:
        return self.n * self.n

    @property
    def naive_rank(self) -> int:
        return self.n * self.n * self.n


def parse_tensor(value: str) -> TensorSpec:
    """Parse ASCII/full-width/Unicode multiplication spellings of ``NxN``."""
    if not isinstance(value, str):
        raise ValueError("--tensor must be written as NxN, for example 5x5")
    # NFKC handles full-width digits and X; casefold handles ASCII X.
    normalized = unicodedata.normalize("NFKC", value).casefold()
    match = _TENSOR_RE.fullmatch(normalized)
    if match is None:
        raise ValueError("--tensor must be written as NxN, for example 5x5")
    left, right = int(match.group(1)), int(match.group(3))
    if left != right:
        raise ValueError(
            f"--tensor requires a square format; got {left}x{right}")
    return TensorSpec.square(left)


def tensor_arg(value: str) -> TensorSpec:
    """``argparse`` adapter for ``add_argument('--tensor', type=tensor_arg)``."""
    try:
        return parse_tensor(value)
    except ValueError as exc:
        raise argparse.ArgumentTypeError(str(exc)) from exc


def normalize_role_weights(weights: Mapping[str, float]) -> dict[str, float]:
    """Validate and normalize a complete or partial GPU-role weight map."""
    unknown = set(weights).difference(ROLE_KEYS)
    if unknown:
        raise ValueError(f"unknown GPU role(s): {', '.join(sorted(unknown))}")
    values: dict[str, float] = {}
    for role in ROLE_KEYS:
        value = float(weights.get(role, 0.0))
        if not math.isfinite(value) or value < 0:
            raise ValueError(f"GPU role {role!r} must have a finite nonnegative weight")
        values[role] = value
    total = sum(values.values())
    if total <= 0:
        raise ValueError("at least one GPU role weight must be positive")
    return {role: value / total for role, value in values.items()}


@dataclass(frozen=True)
class TensorProfile:
    """Resolved defaults and GPU recommendations for one square tensor."""

    spec: TensorSpec
    known_record: bool
    default_rank: int
    seed_path: str | None
    seed_kind: str
    seed_is_c3: bool
    c3_eligible: bool
    c3_seed_path: str | None
    c3_seed_kind: str
    mask_storage: str
    simd_lookup: str
    simd_mode: int
    role_weights: Mapping[str, int]
    recommendation_measured: bool
    recommendation_basis: str

    @property
    def n(self) -> int:
        return self.spec.n

    @property
    def m(self) -> int:
        return self.spec.m

    @property
    def p(self) -> int:
        return self.spec.p

    @property
    def dimensions(self) -> tuple[int, int, int]:
        return self.spec.dimensions

    @property
    def factor_bits(self) -> int:
        return self.spec.factor_bits

    @property
    def naive_rank(self) -> int:
        return self.spec.naive_rank

    @property
    def target_rank(self) -> int:
        """The first strict improvement over the selected safe baseline."""
        return self.default_rank - 1

    @property
    def role_fractions(self) -> dict[str, float]:
        return normalize_role_weights(self.role_weights)


def profile_for_tensor(value: str | int | TensorSpec) -> TensorProfile:
    """Resolve the checked-in record seed for every supported square size.

    A size without a checked-in record never pretends that its naive rank is a
    literature record: ``known_record`` is false, ``seed_path`` is ``None``,
    and callers should materialize their normal exact naive scheme.
    """
    if isinstance(value, TensorSpec):
        spec = value
    elif isinstance(value, str):
        spec = parse_tensor(value)
    else:
        spec = TensorSpec.square(value)
    n = spec.n
    known = n in KNOWN_RECORD_RANKS
    weights_tuple = _ROLE_WEIGHTS.get(n, _FALLBACK_WEIGHTS)
    weights = dict(zip(ROLE_KEYS, weights_tuple))
    if sum(weights.values()) != 100:
        raise AssertionError(f"internal {n}x{n} role weights do not sum to 100")

    seed_path = KNOWN_RECORD_SEEDS.get(n)
    c3_path = KNOWN_C3_SEEDS.get(n)
    if n in (3, 4):
        c3_eligible, c3_kind = False, "none"
    elif c3_path is not None:
        c3_eligible = True
        c3_kind = "default-record" if c3_path == seed_path else "alternate-record"
    else:
        # The exact naive square scheme is C3-closed under the repository's
        # transpose-aware cyclic action, so an unknown size can seed this role.
        c3_eligible, c3_kind = True, "naive"

    return TensorProfile(
        spec=spec,
        known_record=known,
        default_rank=KNOWN_RECORD_RANKS.get(n, spec.naive_rank),
        seed_path=seed_path,
        seed_kind="record" if known else "naive",
        seed_is_c3=not known,
        c3_eligible=c3_eligible,
        c3_seed_path=c3_path,
        c3_seed_kind=c3_kind,
        mask_storage="i32" if spec.factor_bits <= 30 else "i64",
        simd_lookup="scan" if n <= 5 else "hash",
        simd_mode=0 if n <= 5 else 1,
        role_weights=weights,
        recommendation_measured=n in _ROLE_WEIGHTS,
        recommendation_basis=_BASIS.get(
            n, "conservative extrapolation from the measured 5x5/6x6 crossover"),
    )


# Convenient integration aliases.
resolve_tensor_profile = profile_for_tensor
parse_tensor_spec = parse_tensor


__all__ = [
    "KNOWN_C3_SEEDS", "KNOWN_RECORD_RANKS", "KNOWN_RECORD_SEEDS",
    "MAX_FACTOR_BITS", "MAX_SQUARE_SIZE", "MIN_SQUARE_SIZE", "ROLE_KEYS",
    "TensorProfile", "TensorSpec", "normalize_role_weights", "parse_tensor",
    "parse_tensor_spec", "profile_for_tensor", "resolve_tensor_profile",
    "tensor_arg", "validate_square_size",
]
