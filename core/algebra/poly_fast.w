# Typed fast lane for multivariate normal-form reduction.
#
# Profiling cyclic-6 put ~46% of the whole Gröbner run in dynamic method
# dispatch and ~18% in boxed array machinery — the reduction loop's cost is
# the object model, not the mathematics. This lane runs the entire
# reduction inside ONE typed function over flat i64 buffers when the ring
# qualifies:
#
#   - prime coefficient field with p < 2^31 (ring.fastmod), and
#   - grevlex order, arity <= 6, every exponent <= 63, degree <= 511.
#
# Monomials pack into one SMALL i64: deg << 36 | sum_i (63 - e_i) << 6*i —
# 45 bits total, inside the nanboxed small-integer range, so a key that
# leaks into dynamic code never allocates. (v1 of this lane used 8-bit
# fields with deg << 48; those keys promoted to BigInt on every dynamic
# read and the "fast" lane spent 99.8% of its samples in bigint_arena_take.
# Keys must stay under 2^47.)
#
# The complement encoding makes integer order equal grevlex order and
# collapses the step arithmetic: for pending lead P divisible by divisor
# lead D, the quotient in key space is q = P - D and every product term is
# d_j + q — one add per term, byte-local while no 6-bit field overflows
# (guarded per step against the divisor's per-var maxima).
#
# OUTPUT-IDENTICAL to Polynomial#divide's remainder: same
# first-divisor-that-divides scan, same mod-p arithmetic, same term order.
# Any guard trip (field overflow, buffer overflow) returns a bail sentinel
# before any observable effect and the caller reruns the slow path.
#
# Per-polynomial packed forms are cached on the Polynomial (immutable, so
# sound); the divisor bank and scratch buffers are cached on the ring,
# which makes reduction single-threaded per ring (Buchberger is
# sequential).

# The whole reduction loop. Layout:
#   pk/pc        pending keys/coeffs (working buffer A), plen terms
#   qk/qc_buf    ping-pong buffer B
#   bk/bc        divisor bank: all divisor terms concatenated, leads first
#   bptr         divisor start offsets (dn + 1 entries)
#   binv         per-divisor lead-coefficient inverses mod p
#   bmax         per-divisor packed per-var max exponents (6-bit fields)
#   rk/rc        remainder output
#   p            the prime modulus
#   cap          shared capacity of pk/qk/rk
# Returns the remainder length, or -1 on any capacity/encoding bail.
-> pf_run(pk, pc, plen0, qk, qc_buf, bk, bc, bptr, binv, bmax, dn, rk, rc, p, cap) (i64[] i64[] i64 i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64 i64[] i64[] i64 i64) i64
  ps = 0 ## i64
  plen = plen0 ## i64
  rlen = 0 ## i64
  flip = 0 ## i64
  while plen > 0
    lead_key = 0 ## i64
    lead_coeff = 0 ## i64
    if flip == 0
      lead_key = pk[ps]
      lead_coeff = pc[ps]
    else
      lead_key = qk[ps]
      lead_coeff = qc_buf[ps]
    chosen = -1 ## i64
    qraw = 0 ## i64
    d = 0 ## i64
    while d < dn && chosen < 0
      dk0 = bk[bptr[d]] ## i64
      ok = 1 ## i64
      ok = 0 if (dk0 >> 36) > (lead_key >> 36)
      i = 0 ## i64
      while ok == 1 && i < 6
        cd = (dk0 >> (i * 6)) & 63
        cp = (lead_key >> (i * 6)) & 63
        ok = 0 if cd < cp
        i += 1
      if ok == 1
        # overflow guard: quotient exponents + divisor max exponents <= 63
        dm = bmax[d] ## i64
        i = 0
        while ok == 1 && i < 6
          eq = ((dk0 >> (i * 6)) & 63) - ((lead_key >> (i * 6)) & 63)
          em = (dm >> (i * 6)) & 63
          ok = 0 if eq + em > 63
          i += 1
        if ok == 1
          chosen = d
          qraw = lead_key - dk0
      d += 1
    if chosen < 0
      return -1 if rlen >= cap
      rk[rlen] = lead_key
      rc[rlen] = lead_coeff
      rlen += 1
      ps += 1
      plen -= 1
    else
      dstart = bptr[chosen] ## i64
      dcount = bptr[chosen + 1] - dstart ## i64
      qc = (lead_coeff * binv[chosen]) % p ## i64
      i = ps + 1 ## i64
      pend = ps + plen ## i64
      j = dstart + 1 ## i64
      jend = dstart + dcount ## i64
      out = 0 ## i64
      bail = 0 ## i64
      while bail == 0 && (i < pend || j < jend)
        a = 0 ## i64
        b = 0 ## i64
        take = 0 ## i64
        if i < pend && j < jend
          if flip == 0
            a = pk[i]
          else
            a = qk[i]
          b = bk[j] + qraw
          if a > b
            take = 1
          elsif a < b
            take = 2
          else
            take = 3
        elsif i < pend
          take = 1
          if flip == 0
            a = pk[i]
          else
            a = qk[i]
        else
          take = 2
          b = bk[j] + qraw
        if take == 1
          bail = 1 if out >= cap
          if bail == 0
            av = 0 ## i64
            if flip == 0
              av = pc[i]
              qk[out] = a
              qc_buf[out] = av
            else
              av = qc_buf[i]
              pk[out] = a
              pc[out] = av
            out += 1
            i += 1
        elsif take == 2
          bail = 1 if out >= cap
          if bail == 0
            bv = (p - (qc * bc[j]) % p) % p ## i64
            if flip == 0
              qk[out] = b
              qc_buf[out] = bv
            else
              pk[out] = b
              pc[out] = bv
            out += 1
            j += 1
        else
          av = 0 ## i64
          if flip == 0
            av = pc[i]
          else
            av = qc_buf[i]
          s = (av + p - (qc * bc[j]) % p) % p ## i64
          if s != 0
            bail = 1 if out >= cap
            if bail == 0
              if flip == 0
                qk[out] = a
                qc_buf[out] = s
              else
                pk[out] = a
                pc[out] = s
          if bail == 0
            out += 1 if s != 0
            i += 1
            j += 1
      return -1 if bail == 1
      flip = 1 - flip
      ps = 0
      plen = out
  rlen

+ PolyFast
  # Capacity of the scratch buffers (bail to the slow path beyond this).
  -> .capacity
    32768

  # Pack one exponent array into a 45-bit grevlex key, or nil when it
  # exceeds the encoding bounds (exponent > 63 or degree > 511).
  -> .pack_key(exponents)
    deg = 0
    i = 0
    while i < exponents.size
      e = exponents[i]
      return nil if e > 63
      deg += e
      i += 1
    return nil if deg > 511
    key = deg * 68719476736
    i = 0
    while i < exponents.size
      key = key | ((63 - exponents[i]) * (64 ** i))
      i += 1
    key

  # Per-var maxima across a term list, packed as RAW 6-bit exponent fields
  # (no complement, no degree) for the overflow guard.
  -> .pack_max_exps(terms, arity)
    maxes = []
    i = 0
    while i < arity
      maxes.push(0)
      i += 1
    terms.each -> (term)
      i = 0
      while i < arity
        maxes[i] = term[1][i] if term[1][i] > maxes[i]
        i += 1
    key = 0
    i = 0
    while i < arity
      key = key | (maxes[i] * (64 ** i))
      i += 1
    key

  # Unpack a key back to an exponent array.
  -> .unpack_key(key, arity)
    out = []
    i = 0
    while i < arity
      out.push(63 - ((key / (64 ** i)) % 64))
      i += 1
    out

  -> .ring_ok?(ring)
    ring.fastmod != nil && ring.simple_order == "grevlex" && ring.arity <= 6

  # Convert a polynomial to its cached packed form
  # [keys, coeffs, maxkey, lead_inverse, count]; nil (cached as a refusal)
  # when any term exceeds the encoding bounds.
  -> .packed_form(poly)
    cached = poly.pf_cache
    return nil if cached == false
    return cached if cached != nil
    terms = poly.terms
    n = terms.size
    if n == 0
      poly.pf_cache_store(false)
      return nil
    keys = i64[n]
    coeffs = i64[n]
    i = 0
    while i < n
      key = PolyFast.pack_key(terms[i][1])
      if key == nil
        poly.pf_cache_store(false)
        return nil
      keys[i] = key
      coeffs[i] = terms[i][0]
      i += 1
    maxkey = PolyFast.pack_max_exps(terms, poly.ring.arity)
    lead_inv = poly.ring.field.inverse(terms[0][0])
    form = [keys, coeffs, maxkey, lead_inv, n]
    poly.pf_cache_store(form)
    form

  # Scratch buffers cached on the ring:
  # [pk, pc, qk, qc, rk, rc, bk, bc, bptr, binv, bmax, bank_capacity].
  -> .workspace(ring, bank_terms, divisor_count)
    ws = ring.pf_workspace
    cap = PolyFast.capacity
    if ws == nil
      bank_cap = bank_terms * 2 + 256
      ws = [i64[cap], i64[cap], i64[cap], i64[cap], i64[cap], i64[cap],
            i64[bank_cap], i64[bank_cap], i64[512], i64[512], i64[512], bank_cap]
      ring.pf_workspace_store(ws)
    elsif ws[11] < bank_terms || divisor_count >= 511
      bank_cap = bank_terms * 2 + 256
      ws[6] = i64[bank_cap]
      ws[7] = i64[bank_cap]
      ws[11] = bank_cap
    ws

  # Fast normal form: remainder of `poly` under `divisors`, or nil when the
  # lane does not apply / a runtime guard bails.
  -> .normal_form(poly, divisors)
    ring = poly.ring
    return nil if !PolyFast.ring_ok?(ring)
    return nil if poly.zero?
    return nil if divisors.size == 0 || divisors.size >= 511
    self_form = PolyFast.packed_form(poly)
    return nil if self_form == nil
    forms = []
    total = 0
    k = 0
    while k < divisors.size
      form = PolyFast.packed_form(divisors[k])
      return nil if form == nil
      forms.push(form)
      total += form[4]
      k += 1
    p = ring.fastmod
    cap = PolyFast.capacity
    n_terms = self_form[4]
    return nil if n_terms > cap
    ws = PolyFast.workspace(ring, total, divisors.size)
    pk = ws[0]
    pc = ws[1]
    src_keys = self_form[0]
    src_coeffs = self_form[1]
    i = 0
    while i < n_terms
      pk[i] = src_keys[i]
      pc[i] = src_coeffs[i]
      i += 1
    bk = ws[6]
    bc = ws[7]
    bptr = ws[8]
    binv = ws[9]
    bmax = ws[10]
    off = 0
    k = 0
    while k < forms.size
      form = forms[k]
      bptr[k] = off
      binv[k] = form[3]
      bmax[k] = form[2]
      fk = form[0]
      fc = form[1]
      fcount = form[4]
      i = 0
      while i < fcount
        bk[off + i] = fk[i]
        bc[off + i] = fc[i]
        i += 1
      off += fcount
      k += 1
    bptr[forms.size] = off
    rlen = pf_run(pk, pc, n_terms, ws[2], ws[3], bk, bc, bptr, binv, bmax,
                  forms.size, ws[4], ws[5], p, cap)
    return nil if rlen < 0
    arity = ring.arity
    rk = ws[4]
    rc = ws[5]
    terms = []
    i = 0
    while i < rlen
      terms.push([rc[i], PolyFast.unpack_key(rk[i], arity)])
      i += 1
    Polynomial.new(ring, terms, true)
