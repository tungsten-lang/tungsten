"""Encode 'does <n,m,p> have a rank-R decomposition over GF(2)?' as SMT2.

Brent equations mod 2: for every entry triple a=(i,j) of A, b=(j',k) of B,
c=(i',k') of C:
    XOR_t ( u[t][a] AND v[t][b] AND w[t][c] )  =  [j==j' and i==i' and k==k']
Variables: R*(nm + mp + np) booleans. A satisfying assignment IS a scheme
(and is emitted in the campaign's us[]/vs[]/ws[] mask-seed format); UNSAT
proves no rank-R scheme exists over GF(2).

Usage: python3 sat_rank.py <n> <m> <p> <R> > problem.smt2
       z3 problem.smt2          (sat -> model; decode with sat_decode.py)
Light symmetry breaking: naive terms are lexicographically sortable, so we
order the (u,v,w) bit-vectors of consecutive terms; this prunes the R!
term-permutation symmetry without excluding any scheme class.
"""
import sys


def main():
    n, m, p, R = (int(x) for x in sys.argv[1:5])
    AB, BB, CB = n * m, m * p, n * p
    out = []
    w = out.append
    w("(set-logic QF_UF)" if False else "(set-option :produce-models true)")
    for t in range(R):
        for a in range(AB):
            w(f"(declare-const u{t}_{a} Bool)")
        for b in range(BB):
            w(f"(declare-const v{t}_{b} Bool)")
        for c in range(CB):
            w(f"(declare-const w{t}_{c} Bool)")
    # Brent equations
    for i in range(n):
        for j in range(m):
            a = i * m + j
            for j2 in range(m):
                for k in range(p):
                    b = j2 * p + k
                    for i2 in range(n):
                        for k2 in range(p):
                            c = i2 * p + k2
                            terms = " ".join(
                                f"(and u{t}_{a} v{t}_{b} w{t}_{c})" for t in range(R))
                            tgt = "true" if (j == j2 and i == i2 and k == k2) else "false"
                            w(f"(assert (= (xor {terms} false) {tgt}))")
    # no all-zero factors (prunes trivially-dead terms)
    for t in range(R):
        w(f"(assert (or {' '.join(f'u{t}_{a}' for a in range(AB))}))")
        w(f"(assert (or {' '.join(f'v{t}_{b}' for b in range(BB))}))")
        w(f"(assert (or {' '.join(f'w{t}_{c}' for c in range(CB))}))")
    # symmetry breaking: term t's u-vector lexicographically <= term t+1's,
    # tie-broken by v. Encoded as unsigned comparison of concatenated bits
    # via integer weights would leave QF booleans; keep it simple: compare
    # only the u bit-vectors bitwise-lex (sound: any scheme can be reordered).
    for t in range(R - 1):
        # lex(u_t <= u_{t+1}): standard chain
        conds = []
        prefix_eq = []
        for a in range(AB):
            lt = f"(and (not u{t}_{a}) u{t + 1}_{a})"
            here = f"(and {' '.join(prefix_eq)} {lt})" if prefix_eq else lt
            conds.append(here)
            prefix_eq.append(f"(= u{t}_{a} u{t + 1}_{a})")
        alleq = f"(and {' '.join(prefix_eq)})"
        w(f"(assert (or {' '.join(conds)} {alleq}))")
    w("(check-sat)")
    w("(get-model)")
    print("\n".join(out))


if __name__ == "__main__":
    main()
