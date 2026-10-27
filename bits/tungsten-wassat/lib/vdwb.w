# Paley/quadratic-residue Van der Waerden-bound model lane, split out of mdp.w.
# Model-only: a candidate coloring is published only after the caller checks
# it against the original CNF.

-> wassat_vdwb_check_prime(fla, fcs, fcl, ncl, nv, k, p, qr, sign) (i64[] i64[] i64[] i64 i64 i64 i64 i8[] i8[]) bool
  i = 0
  while i < p
    qr[i] = 0
    i += 1
  x = 1
  while x * 2 < p
    qr[(x * x) % p] = 1
    x += 1
  last_zero = (k - 1) * p + 1
  v = 1
  while v <= nv
    r = (v - 1) % p
    if r == 0
      sign[v] = v == last_zero ? 1 : -1
    else
      sign[v] = qr[r] == 1 ? 1 : -1
    v += 1
  ci = 0
  while ci < ncl
    off = fcs[ci]
    len = fcl[ci]
    sat = false
    j = 0
    while j < len
      l = fla[off + j]
      if l > 0
        if sign[l] > 0
          sat = true
          break
      elsif l < 0
        if sign[0 - l] < 0
          sat = true
          break
      j += 1
    return false unless sat
    ci += 1
  true

-> wassat_vdwb_solve(formula, result)
  return result unless formula.has_key?("flat_ncl")
  nv = formula["nvars"]
  ncl = formula["flat_ncl"]
  return result if nv < 50 || nv > 5000 || ncl < 500 || ncl > 3000000
  fla = formula["flat_lits"] ## i64[]
  fcs = formula["flat_offs"] ## i64[]
  fcl = formula["flat_lens"] ## i64[]
  k = fcl[0]
  return result if k < 5 || k > 8
  return result unless fcl[1] == k && fcl[ncl - 1] == k
  off0 = fcs[0]
  d0 = fla[off0 + 1] - fla[off0]
  return result if d0 == 0 || fla[off0 + 2] - fla[off0 + 1] != d0
  primes = [113, 617, 67, 73, 89, 97, 101, 109, 137, 149, 157, 173, 193, 233, 257, 277, 281, 313, 337, 353, 373, 389, 401, 409, 433, 449, 457, 509, 521, 541, 569, 577, 593, 601, 613, 641, 653, 673, 677, 701]
  qr = i8[709]
  sign = i8[nv + 1]
  pi = 0
  while pi < primes.size
    p = primes[pi]
    if wassat_vdwb_check_prime(fla, fcs, fcl, ncl, nv, k, p, qr, sign)
      model = []
      v = 1
      while v <= nv
        model.push(sign[v] > 0 ? v : 0 - v)
        v += 1
      return result unless wassat_model_satisfies?(formula, model)
      result["recognized"] = true
      result["bits"] = k
      result["samples"] = p
      result["trials"] = pi + 1
      result["status"] = 1
      result["model"] = model
      return result
    pi += 1
  result

