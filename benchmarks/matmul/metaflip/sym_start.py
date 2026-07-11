"""Build the diagonal-partition starts used by symmetric flip search.

Moosbauer--Poole's record searches do not start from the naive scheme.  They
replace a partition of the diagonal basis tensors by invariant diagonal cubes,
then expand the correction tensor in the standard basis.  In a symmetric solver
that freezes these invariant cubes (including the Moosbauer--Poole reference
implementation), their number fixes the reachable rank residue:

    rank == number_of_cubes (mod 3).

The local ``sym_gen2*`` prototypes do not freeze singleton orbits: a plus move
can split a cube, and some ordinary flips can touch a one-hot singleton cube.
Either changes this residue.  For those walkers the partition is still a
structural seed choice, but not an invariant by itself.

Examples (indices are one-based):

  python3 sym_start.py 5 '1,5;2,4;3' > mp5_start.txt
  python3 sym_start.py 5 '1,2,4,5;3' > target92_start.txt
  python3 sym_start.py 6 '1,2;3,4;5,6' --check-reversal > mp6_start.txt

The default output is the ``us[i] = ...`` format accepted by sym_gen2*.py.
"""

import argparse

from metaflip_proto2 import T, recon


def parse_partition(spec, n):
    """Parse a one-based ``1,5;2,4;3`` partition specification."""
    blocks = []
    for raw_block in spec.split(";"):
        if not raw_block.strip():
            raise ValueError("partition contains an empty block")
        block = tuple(int(x.strip()) - 1 for x in raw_block.split(","))
        if any(i < 0 or i >= n for i in block):
            raise ValueError(f"partition index outside 1..{n}")
        if len(set(block)) != len(block):
            raise ValueError("partition repeats an index inside a block")
        blocks.append(block)
    flat = [i for block in blocks for i in block]
    if sorted(flat) != list(range(n)):
        raise ValueError(f"blocks must partition every index in 1..{n} exactly once")
    return tuple(blocks)


def diagonal_partition_scheme(n, blocks):
    """Return the exact GF(2) start associated with ``blocks``.

    If D_P is the diagonal mask of a block P, the start is a standard-basis
    decomposition of M_n - sum_P D_P^3, together with the grouped terms D_P^3.
    Subtraction is XOR over GF(2).
    """
    basis = {
        (1 << (i * n + j), 1 << (j * n + k), 1 << (i * n + k))
        for i in range(n)
        for j in range(n)
        for k in range(n)
    }
    cubes = []
    for block in blocks:
        diagonal = sum(1 << (i * n + i) for i in block)
        cubes.append((diagonal, diagonal, diagonal))
        for i in block:
            for j in block:
                for k in block:
                    term = (1 << (i * n + i), 1 << (j * n + j), 1 << (k * n + k))
                    basis.discard(term) if term in basis else basis.add(term)
    scheme = set(basis)
    for term in cubes:
        scheme.discard(term) if term in scheme else scheme.add(term)
    if recon(scheme, n, n, n) != T(n, n, n):
        raise AssertionError("constructed diagonal-partition start is invalid")
    return sorted(scheme)


def transpose(mask, n):
    out = 0
    for bit in range(n * n):
        if mask >> bit & 1:
            i, j = divmod(bit, n)
            out |= 1 << (j * n + i)
    return out


def c3_image(term, n):
    u, v, w = term
    return v, transpose(w, n), transpose(u, n)


def reverse_mask(mask, n):
    out = 0
    for bit in range(n * n):
        if mask >> bit & 1:
            i, j = divmod(bit, n)
            out |= 1 << ((n - 1 - i) * n + (n - 1 - j))
    return out


def check_c3(terms, n):
    terms = set(terms)
    return all(c3_image(term, n) in terms for term in terms)


def check_reversal(terms, n):
    terms = set(terms)
    return all(tuple(reverse_mask(x, n) for x in term) in terms for term in terms)


def emit(terms, style):
    if style == "bare":
        print(len(terms))
        for u, v, w in terms:
            print(u, v, w)
    elif style == "r":
        for u, v, w in terms:
            print("R", u, v, w)
    else:
        for axis, name in enumerate(("us", "vs", "ws")):
            for i, term in enumerate(terms):
                print(f"{name}[{i}] = {term[axis]}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("n", type=int)
    parser.add_argument("partition", help="one-based blocks, e.g. '1,5;2,4;3'")
    parser.add_argument("--style", choices=("usvw", "bare", "r"), default="usvw")
    parser.add_argument("--check-reversal", action="store_true")
    args = parser.parse_args()

    blocks = parse_partition(args.partition, args.n)
    terms = diagonal_partition_scheme(args.n, blocks)
    assert check_c3(terms, args.n), "start is not C3-invariant"
    if args.check_reversal:
        assert check_reversal(terms, args.n), "start is not reversal-invariant"
    print(
        f"start n={args.n} rank={len(terms)} cubes={len(blocks)} "
        f"C3-residue={len(blocks) % 3} c3=True "
        f"reversal={check_reversal(terms, args.n)}",
        file=__import__("sys").stderr,
    )
    emit(terms, args.style)


if __name__ == "__main__":
    main()
