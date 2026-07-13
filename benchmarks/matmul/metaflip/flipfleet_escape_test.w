use flipfleet_escape

CAP = 512 ## i64

-> ffet_init_naive(us, vs, ws, n) (i64[] i64[] i64[] i64) i64
  rank = 0 ## i64
  one = 1 ## i64
  i = 0 ## i64
  while i < n
    j = 0 ## i64
    while j < n
      k = 0 ## i64
      while k < n
        us[rank] = one << (i * n + j)
        vs[rank] = one << (j * n + k)
        ws[rank] = one << (i * n + k)
        rank += 1
        k += 1
      j += 1
    i += 1
  rank

-> ffet_copy(du, dv, dw, su, sv, sw, rank) (i64[] i64[] i64[] i64[] i64[] i64[] i64) i64
  i = 0 ## i64
  while i < rank
    du[i] = su[i]
    dv[i] = sv[i]
    dw[i] = sw[i]
    i += 1
  rank

-> ffet_verify(us, vs, ws, rank, n) (i64[] i64[] i64[] i64 i64) i64
  ok = 1 ## i64
  width = n * n ## i64
  ai = 0 ## i64
  while ai < width
    bi = 0 ## i64
    while bi < width
      ci = 0 ## i64
      while ci < width
        got = 0 ## i64
        t = 0 ## i64
        while t < rank
          if ((us[t] >> ai) & 1) == 1
            if ((vs[t] >> bi) & 1) == 1
              if ((ws[t] >> ci) & 1) == 1
                got = got ^ 1
          t += 1
        want = 0 ## i64
        if (ai % n) == (bi / n)
          if (ai / n) == (ci / n)
            if (bi % n) == (ci % n)
              want = 1
        if got != want
          ok = 0
          ci = width
          bi = width
          ai = width
        else
          ci += 1
      bi += 1
    ai += 1
  ok

failures = 0 ## i64
n = 3 ## i64
while n <= 7
  baseu = i64[CAP]
  basev = i64[CAP]
  basew = i64[CAP]
  base_rank = ffet_init_naive(baseu, basev, basew, n) ## i64
  if ffet_verify(baseu, basev, basew, base_rank, n) != 1
    << "FAIL naive n=" + n.to_s()
    failures += 1
  kind = 1 ## i64
  while kind <= 5
    us = i64[CAP]
    vs = i64[CAP]
    ws = i64[CAP]
    copied = ffet_copy(us, vs, ws, baseu, basev, basew, base_rank) ## i64
    meta = i64[8]
    rank = ffe_apply(us, vs, ws, copied, CAP, n, kind, n * 17 + kind, meta) ## i64
    if rank < 0 || meta[7] != 1
      << "FAIL ineligible n=" + n.to_s() + " kind=" + kind.to_s()
      failures += 1
    else
      if ffet_verify(us, vs, ws, rank, n) != 1
        << "FAIL tensor n=" + n.to_s() + " kind=" + kind.to_s() + " rank=" + rank.to_s()
        failures += 1
      else
        << "PASS n=" + n.to_s() + " kind=" + kind.to_s() + " rank " + base_rank.to_s() + "->" + rank.to_s()
    kind += 1
  n += 1

if failures != 0
  << "flipfleet_escape_test: " + failures.to_s() + " failure(s)"
  exit(1)
<< "flipfleet_escape_test: all exact identities passed"
