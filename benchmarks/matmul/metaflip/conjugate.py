"""GL-conjugate a scheme: same decomposition, new flip-graph coordinates.

For X in GL(n,2), Y in GL(m,2), Z in GL(p,2), a valid <n,m,p> scheme maps to
another valid scheme via
    U' = X^-T U Y^T      (U is the n x m coefficient matrix of the A factor)
    V' = Y^-T V Z^T
    W' = X W Z^-1
Derivation: substitute A = X^-1 A' Y, B = Y^-1 B' Z into C = AB; then
A'B' = X (AB) Z^-1 and the trilinear form transforms as above. Each random
(X,Y,Z) puts a fleet walker into a distinct basin of the flip graph.

Usage: python3 conjugate.py <seed.txt> <n> <m> <p> <rng-seed> > seed_conj.txt
Exact-validates the result; exits 1 if invalid.
"""
import random
import sys

from metaflip_proto2 import T, recon
from seed_prep import parse_terms


def matmul2(A, B):
    n, k, m = len(A), len(B), len(B[0])
    return [[sum(A[i][t] & B[t][j] for t in range(k)) & 1 for j in range(m)]
            for i in range(n)]


def inverse2(M):
    """Gauss-Jordan over GF(2); returns None if singular."""
    n = len(M)
    aug = [row[:] + [1 if i == j else 0 for j in range(n)] for i, row in enumerate(M)]
    for col in range(n):
        piv = next((r for r in range(col, n) if aug[r][col]), None)
        if piv is None:
            return None
        aug[col], aug[piv] = aug[piv], aug[col]
        for r in range(n):
            if r != col and aug[r][col]:
                aug[r] = [(a ^ b) for a, b in zip(aug[r], aug[col])]
    return [row[n:] for row in aug]


def rand_gl(n, rng):
    while True:
        M = [[rng.randint(0, 1) for _ in range(n)] for _ in range(n)]
        if inverse2(M) is not None:
            return M


def transpose(M):
    return [list(r) for r in zip(*M)]


def mask_to_mat(mask, rows, cols):
    return [[(mask >> (i * cols + j)) & 1 for j in range(cols)] for i in range(rows)]


def mat_to_mask(M, rows, cols):
    return sum(M[i][j] << (i * cols + j) for i in range(rows) for j in range(cols))


def conjugate(terms, n, m, p, rng):
    X, Y, Z = rand_gl(n, rng), rand_gl(m, rng), rand_gl(p, rng)
    XiT = transpose(inverse2(X))
    YiT = transpose(inverse2(Y))
    YT, ZT, Zi = transpose(Y), transpose(Z), inverse2(Z)
    out = []
    for u, v, w in terms:
        U = mask_to_mat(u, n, m)
        V = mask_to_mat(v, m, p)
        W = mask_to_mat(w, n, p)
        U2 = matmul2(matmul2(XiT, U), YT)
        V2 = matmul2(matmul2(YiT, V), ZT)
        W2 = matmul2(matmul2(X, W), Zi)
        out.append((mat_to_mask(U2, n, m), mat_to_mask(V2, m, p), mat_to_mask(W2, n, p)))
    return out


def main():
    path, n, m, p, rseed = (sys.argv[1], int(sys.argv[2]), int(sys.argv[3]),
                            int(sys.argv[4]), int(sys.argv[5]))
    terms = parse_terms(path)[0]
    rng = random.Random(rseed)
    out = conjugate(terms, n, m, p, rng)
    S = set()
    for t in out:
        S.discard(t) if t in S else S.add(t)
    valid = recon(S, n, m, p) == T(n, m, p)
    print(f"conjugated <{n},{m},{p}> rank={len(S)} valid={valid} rseed={rseed}", file=sys.stderr)
    if not valid:
        sys.exit(1)
    terms = sorted(S)
    for k, (u, v, w) in enumerate(terms):
        print(f"us[{k}] = {u}")
    for k, (u, v, w) in enumerate(terms):
        print(f"vs[{k}] = {v}")
    for k, (u, v, w) in enumerate(terms):
        print(f"ws[{k}] = {w}")


if __name__ == "__main__":
    main()
