# Proof metadata for GF(2) bilinear tensor rank, not measured search plateaus.
# Hopcroft--Kerr: <2,2,k> = ceil(7k/2), <2,3,3> = 15.
# <2,3,4> = 20: checked local n324 quotient-rank certificates; see
# benchmarks/matmul/metaflip/FINDINGS.md, 2026-07-14 and proof_n324 manifest.
# Unknown returns zero. This does not classify arbitrary arithmetic circuits.
-> ffpr_exact_rank(n, m, p) (i64 i64 i64) i64
  if n < 1 || m < 1 || p < 1 || n > 32 || m > 32 || p > 32
    return 0
  a = n ## i64
  b = m ## i64
  c = p ## i64
  if a > b
    t = a ## i64
    a = b
    b = t
  if b > c
    t = b ## i64
    b = c
    c = t
  if a > b
    t = a ## i64
    a = b
    b = t
  if a == 1
    return b*c
  if a == 2 && b == 2
    return (7*c+1)/2
  if a == 2 && b == 3 && c == 3
    return 15
  if a == 2 && b == 3 && c == 4
    return 20
  0

-> ffpr_source(n, m, p) (i64 i64 i64)
  rank = ffpr_exact_rank(n,m,p) ## i64
  if rank == 0
    return "unknown"
  if n == 1 || m == 1 || p == 1
    return "flattening"
  if (n == 2 || m == 2 || p == 2) && (n == 3 || m == 3 || p == 3) && (n == 4 || m == 4 || p == 4)
    return "checked-n324-quotient"
  "hopcroft-kerr-1971"
