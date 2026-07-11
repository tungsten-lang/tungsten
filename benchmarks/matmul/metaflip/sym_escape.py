"""Exact generic and C3 escape moves for square matrix multiplication over GF(2).

The reference symmetric-flips solver freezes its invariant one-term C3 orbits.
That is useful for quotient search, but it separates searches with different
fixed terms.  This module supplies small, explicitly tensor-zero identities
that can thaw such a term before continuing in either the full or C3 quotient
flip graph.

Stored terms use the local ``(u, v, w)`` convention.  The C3 action is

    rho(u, v, w) = (v, transpose(w), transpose(u)).

Thus a fixed term has the form ``cube(x) = (x, x, transpose(x))``.  The four
implemented involutions toggle tensor-zero identities:

``split``
    Split one factor of any term.  This is the generic +1 escape used for
    non-C3 records such as the tracked 3x3 and 4x4 schemes.

``break``
    Split one factor of a fixed term.  This breaks C3 symmetry and normally
    changes rank by +1.  It is the cheapest bridge to the ordinary flip graph.

``orbit-split``
    C3-symmetrize that split.  It normally replaces one fixed term by two
    three-term orbits, changing rank by +5 while preserving C3 closure.

``polarize``
    Toggle the characteristic-two polarization identity

      C(x) + C(y) + C(x+y) + O(x,x,y) + O(x,y,y) = 0.

    Here ``O`` denotes the full C3 orbit (and the displayed third arguments
    are in the common, transpose-identified vector space).  It changes the
    fixed-orbit count and therefore the rank residue modulo three.  The actual
    delta depends on which of the other cubes/orbits are already present; the
    collision-free rank delta is +7, while the record campaigns produced +5.

All insertions are parity toggles: duplicate terms cancel and zero-factor
terms vanish.  The command-line interface exact-checks both input and output.

Examples:

  python3 sym_escape.py analyze waypoint.txt 4
  python3 sym_escape.py bridge record.txt 4 --kind split > escaped.txt
  python3 sym_escape.py bridge waypoint.txt 4 --kind break > thawed.txt
  python3 sym_escape.py bridge waypoint.txt 4 --kind orbit-split > c3-thawed.txt
  python3 sym_escape.py bridge waypoint.txt 3 --kind polarize --part 1 > p.txt
"""

import argparse
import sys

from bench_decomp import parse_scheme
from metaflip_proto2 import T, recon
from seed_prep import entries_to_masks, parse_terms


def transpose(mask, n):
    """Transpose an ``n`` by ``n`` row-major bit mask."""
    out = 0
    for bit in range(n * n):
        if mask >> bit & 1:
            i, j = divmod(bit, n)
            out |= 1 << (j * n + i)
    return out


def c3_image(term, n):
    """Apply the order-three matrix-multiplication tensor symmetry."""
    u, v, w = term
    return v, transpose(w, n), transpose(u, n)


def c3_orbit(term, n):
    """Return the one- or three-element C3 orbit of ``term``."""
    second = c3_image(term, n)
    return frozenset((term, second, c3_image(second, n)))


def cube(x, n):
    """The fixed C3 term represented by the common-space vector ``x``."""
    return x, x, transpose(x, n)


def parity_terms(terms):
    """Normalize a term iterable as a GF(2) sum."""
    out = set()
    for term in terms:
        if not all(term):
            continue
        out.discard(term) if term in out else out.add(term)
    return out


def toggle_identity(scheme, identity):
    """Return ``scheme XOR identity`` after zero/duplicate normalization."""
    out = set(scheme)
    for term in parity_terms(identity):
        out.discard(term) if term in out else out.add(term)
    return out


def fixed_terms(scheme, n):
    """Return all one-element C3 orbits in deterministic order."""
    return sorted(term for term in scheme if c3_image(term, n) == term)


def is_c3_closed(scheme, n):
    scheme = set(scheme)
    return all(c3_image(term, n) in scheme for term in scheme)


def split_identity(term, axis, part):
    """Return ``t + t[f=part] + t[f=old+part]``, a tensor-zero sum.

    ``part`` must be a nontrivial split of the selected factor.  Applying this
    to a fixed C3 term deliberately leaves the C3-closed subspace.
    """
    if axis not in (0, 1, 2):
        raise ValueError("axis must be 0, 1, or 2")
    old = term[axis]
    if not part or part == old:
        raise ValueError("part must be nonzero and different from the factor")
    left = list(term)
    right = list(term)
    left[axis] = part
    right[axis] = old ^ part
    return parity_terms((term, tuple(left), tuple(right)))


def orbit_split_identity(x, part, n):
    """C3-symmetric split of ``cube(x)`` into two generic C3 orbits."""
    if not x or not part or part == x:
        raise ValueError("x and part must be distinct nonzero masks")
    xt = transpose(x, n)
    terms = [cube(x, n)]
    terms.extend(c3_orbit((part, x, xt), n))
    terms.extend(c3_orbit((x ^ part, x, xt), n))
    return parity_terms(terms)


def polarization_identity(x, y, n):
    """Characteristic-two cubic polarization identity in C3 storage form."""
    if not x or not y or x == y:
        raise ValueError("x and y must be distinct nonzero masks")
    terms = [cube(x, n), cube(y, n), cube(x ^ y, n)]
    terms.extend(c3_orbit((x, x, transpose(y, n)), n))
    terms.extend(c3_orbit((x, y, transpose(y, n)), n))
    return parity_terms(terms)


def flip_pair_count(scheme):
    """Count ordinary shared-factor pairs, with axes counted separately."""
    counts = 0
    terms = list(scheme)
    for axis in range(3):
        buckets = {}
        for term in terms:
            buckets[term[axis]] = buckets.get(term[axis], 0) + 1
        counts += sum(size * (size - 1) // 2 for size in buckets.values())
    return counts


def density(scheme):
    return sum(bin(u).count("1") + bin(v).count("1") + bin(w).count("1")
               for u, v, w in scheme)


def common_factors(scheme, n):
    """Candidate masks in the common transpose-identified C3 factor space."""
    return sorted({u for u, _, _ in scheme} |
                  {v for _, v, _ in scheme} |
                  {transpose(w, n) for _, _, w in scheme})


def _candidate_parts(scheme, n, exhaustive):
    if exhaustive:
        if n > 4:
            raise ValueError("exhaustive mask enumeration is limited to n <= 4")
        return range(1, 1 << (n * n))
    return common_factors(scheme, n)


def bridge_error(scheme, n, kind):
    """Return an actionable eligibility error, or ``None`` when applicable."""
    if kind not in ("split", "break", "orbit-split", "polarize"):
        return f"unknown bridge kind: {kind}"
    if not scheme:
        return "scheme has no nonzero term to split"
    if kind != "split" and not fixed_terms(scheme, n):
        return "scheme has no fixed C3 term to thaw"
    if kind in ("orbit-split", "polarize") and not is_c3_closed(scheme, n):
        return f"{kind} requires a C3-closed input scheme"
    return None


def best_bridge(scheme, n, kind="break", exhaustive=False, part=None):
    """Choose a deterministic, connectivity-biased exact bridge.

    The score is rank first, then more ordinary flip pairs, then density.  This
    is a local seed heuristic only; it is not evidence about global rank.
    Returns ``(output_scheme, metadata)``.
    """
    if not isinstance(n, int) or n <= 0:
        raise ValueError("n must be positive")
    error = bridge_error(scheme, n, kind)
    if error:
        raise ValueError(error)
    sources = sorted(scheme) if kind == "split" else fixed_terms(scheme, n)
    best = None
    best_key = None
    parts = [part] if part is not None else _candidate_parts(scheme, n, exhaustive)
    split_axis_parts = (
        {term[0] for term in scheme},
        {term[1] for term in scheme},
        {transpose(term[2], n) for term in scheme},
    )
    for term in sources:
        x = term[0]
        for candidate in parts:
            if not candidate:
                continue
            if kind in ("orbit-split", "polarize") and candidate == x:
                continue
            items = []
            if kind in ("split", "break"):
                for axis in range(3):
                    # The generic move follows the structured-plus policy:
                    # draw the inserted factor from the same live axis.  Fixed
                    # C3 breaks retain their common-space cross-axis pool.
                    if (kind == "split" and part is None and not exhaustive and
                            candidate not in split_axis_parts[axis]):
                        continue
                    factor = transpose(term[axis], n) if axis == 2 else term[axis]
                    if candidate == factor:
                        continue
                    # ``candidate`` lives in the common C3 factor space; the
                    # stored W factor uses the transposed representation.
                    axis_part = transpose(candidate, n) if axis == 2 else candidate
                    ident = split_identity(term, axis, axis_part)
                    out = toggle_identity(scheme, ident)
                    meta = {"kind": kind, "x": x if kind == "break" else None,
                            "factor": factor, "part": candidate, "axis": axis,
                            "term": term}
                    items.append((out, meta))
            elif kind == "orbit-split":
                out = toggle_identity(scheme, orbit_split_identity(x, candidate, n))
                meta = {"kind": kind, "x": x, "part": candidate, "axis": None}
                items.append((out, meta))
            elif kind == "polarize":
                out = toggle_identity(scheme, polarization_identity(x, candidate, n))
                meta = {"kind": kind, "x": x, "part": candidate, "axis": None}
                items.append((out, meta))
            else:
                raise ValueError(f"unknown bridge kind: {kind}")
            for item in items:
                output, metadata = item
                key = (
                    len(output),
                    -flip_pair_count(output),
                    density(output),
                    metadata.get("factor", metadata["x"]),
                    metadata["part"],
                    -1 if metadata["axis"] is None else metadata["axis"],
                )
                if best_key is None or key < best_key:
                    best = item
                    best_key = key
    if best is None:
        raise ValueError("no nontrivial bridge candidate")
    return best


def load_scheme(path, n):
    masks, raw = parse_terms(path)
    if masks is not None:
        terms = masks
    elif raw:
        terms = entries_to_masks(raw, n, n, n)
    else:
        # ``emit_bare`` and FlipFleet use rank-on-the-first-line dumps.  Keep
        # the CLI closed under its own output format instead of interpreting a
        # bare dump as an empty MP-style scheme.
        terms = parse_scheme(path)
    return parity_terms(terms)


def emit_scheme(scheme, stream=sys.stdout, style="bare"):
    terms = sorted(scheme)
    if style == "bare":
        print(len(terms), file=stream)
        for u, v, w in terms:
            print(u, v, w, file=stream)
    elif style == "r":
        for u, v, w in terms:
            print("R", u, v, w, file=stream)
    elif style == "usvw":
        for axis, name in enumerate(("us", "vs", "ws")):
            for index, term in enumerate(terms):
                print(f"{name}[{index}] = {term[axis]}", file=stream)
    else:
        raise ValueError(f"unknown output style: {style}")


def emit_bare(scheme, stream=sys.stdout):
    """Backward-compatible convenience wrapper for a FlipFleet dump."""
    emit_scheme(scheme, stream, "bare")


def describe(scheme, n):
    if not isinstance(n, int) or n <= 0:
        raise ValueError("n must be positive")
    limit = 1 << (n * n)
    well_formed = (len(scheme) == len(set(scheme)) and
                   all(len(term) == 3 and
                       all(isinstance(mask, int) and 0 < mask < limit
                           for mask in term)
                       for term in scheme))
    return {
        "rank": len(scheme),
        "density": density(scheme),
        "fixed": len(fixed_terms(scheme, n)),
        "c3": is_c3_closed(scheme, n),
        "flip_pairs": flip_pair_count(scheme),
        "well_formed": well_formed,
        "exact": well_formed and recon(scheme, n, n, n) == T(n, n, n),
    }


def _print_description(label, info):
    fields = " ".join(f"{key}={value}" for key, value in info.items())
    print(f"{label} {fields}", file=sys.stderr)


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Analyze or apply exact GF(2) escape identities to a square scheme.")
    sub = parser.add_subparsers(dest="command", required=True)
    analyze = sub.add_parser("analyze", help="exact-check and describe a scheme")
    analyze.add_argument("scheme", help="MP text, R lines, us/vs/ws, or bare dump")
    analyze.add_argument("n", type=int, help="square matrix dimension")
    bridge = sub.add_parser("bridge", help="toggle one exact escape identity")
    bridge.add_argument("scheme", help="MP text, R lines, us/vs/ws, or bare dump")
    bridge.add_argument("n", type=int, help="square matrix dimension")
    bridge.add_argument(
        "--kind", choices=("split", "break", "orbit-split", "polarize"),
        default="break",
        help=("split=any term; break=fixed cube and lose C3; orbit-split/polarize="
              "fixed cube while preserving C3"))
    bridge.add_argument(
        "--part", type=lambda value: int(value, 0),
        help="common-space factor mask (Python integer syntax; W is transposed internally)")
    bridge.add_argument(
        "--exhaustive", action="store_true",
        help="scan every nonzero part (n<=4; potentially expensive)")
    bridge.add_argument(
        "--format", choices=("bare", "r", "usvw"), default="bare",
        help="stdout scheme format; diagnostics are written to stderr")
    args = parser.parse_args(argv)
    if args.n <= 0:
        parser.error("n must be positive")
    if args.command == "bridge":
        if args.part is not None and not 0 < args.part < (1 << (args.n * args.n)):
            parser.error("--part must fit the nonzero n-by-n factor mask")
        if args.part is not None and args.exhaustive:
            parser.error("--part and --exhaustive are mutually exclusive")

    scheme = load_scheme(args.scheme, args.n)
    before = describe(scheme, args.n)
    _print_description("input", before)
    if not before["exact"]:
        raise SystemExit("input is not an exact matrix-multiplication scheme")
    if args.command == "analyze":
        return
    error = bridge_error(scheme, args.n, args.kind)
    if error:
        raise SystemExit(error)

    output, meta = best_bridge(
        scheme, args.n, kind=args.kind, exhaustive=args.exhaustive, part=args.part
    )
    after = describe(output, args.n)
    _print_description(
        f"bridge kind={meta['kind']} x={meta['x']} factor={meta.get('factor')} "
        f"part={meta['part']} "
        f"axis={meta['axis']}",
        after,
    )
    if not after["exact"]:
        raise AssertionError("bridge violated the tensor identity")
    if args.kind in ("orbit-split", "polarize") and not after["c3"]:
        raise AssertionError("C3-preserving bridge lost closure")
    emit_scheme(output, style=args.format)


if __name__ == "__main__":
    main()
