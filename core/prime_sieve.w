# PrimeSieve — mod-30 wheel, bit-packed, segmented, parallel sieve of
# Eratosthenes. The compiled fast path behind Int.nth_prime, Int.primes,
# Int.prime_pi and the fused `range /prime? :count` pipeline.
#
# Storage: byte b holds the eight candidates 30b + {1,7,11,13,17,19,23,29},
# one per bit — 1 byte per 30 integers, so a 128 KB segment (one P-core L1D)
# covers 3.9M integers.
#
# Marking: for a prime p coprime to 30 the multiples split into eight
# progressions p*(30t + R[j]). Each has CONSTANT byte stride p (30p integers
# = p bytes) and a CONSTANT bit mask, since p*(30t+R[j]) ≡ p*R[j] (mod 30)
# independent of t — so the inner loop is `seg[b] |= m; b += p`.
#
# Large primes: a prime with stride ≥ segment width marks at most once per
# segment, so instead of re-examining every base prime per segment, each
# progression is filed in a ring of buckets keyed by the segment it next
# lands in (ring depth √hi/outer_bytes + 3) and only the current bucket is
# walked.
#
# Presieve: the multiples of every prime 7..163 are periodic in byte space,
# so they live in 16 small (~6-10 KB, L1-resident) tables that are OR-ed
# into each segment four at a time in vectorized run-length passes. That
# replaces the memset AND the 35 densest marking loops — 37% of all marks.
#
# Checkpoints: a table of (n, p_n) rungs (16 per decade of n up to 2e11,
# every entry computed by this sieve) so nth_prime(n) starts from the
# nearest rung below n, and pi(x) = k + primes in (p_k, x] skips everything
# below the nearest rung. An exact hit returns without sieving.
#
# Parallelism: the range is cut into chunks handed out through an atomic
# counter to cpu_count - 1 threads (TUNGSTEN_PRIME_THREADS overrides); each
# thread owns its scratch, base primes and pattern are shared read-only.
# Chunk counts are exact, so nth_prime locates its answer by prefix-summing
# them and re-sieving one chunk; Int.primes fills its output in parallel
# from the same prefix sums.
#
# The hot kernels are top-level fns with annotated signatures: class methods
# never get the raw-int ABI (they receive self as a WValue), and a typed-
# array read inside an unannotated fn is boxed. The C twin of this file
# (runtime.c, w_p30_*) still serves the interpreter; the two agree to the
# last prime and run at the same speed, which is why this one is the
# compiled path.

# ---------------------------------------------------------------- kernels --
# Every hot loop lives in a fn with an annotated signature (see the header).
# Two tiers of sieving primes:
#   small  (p < small_max): one loop per prime marks all eight residues of a
#          cycle per iteration (8 independent RMWs, one add), walked linearly
#          every segment — these primes make many marks per segment;
#   medium/large: ONE record per prime that walks its eight residues with the
#          wheel state machine (byte += p30*dr[j] + ctab[cls][j], bit =
#          bitm[cls][j]), filed in the bucket ring by the segment its next
#          multiple lands in. Eight times fewer bucket entries than one entry
#          per progression — that overhead, not marking, dominated at 1e11+.
#          (primesieve-style packed 8-byte records in contiguous bucket
#          blocks were measured 15-25% SLOWER here at 1e12+, single- and
#          multi-threaded, even with the wheel cycle unrolled — cause not
#          identified; the parallel-array records stay.)

# Presieve tables: the multiples of the 35 primes 7..163 (coprime to 30) in
# 16 periodic byte tables — 2-3 primes each so every table is ~6-10 KB and
# L1-resident (products: {7,23,37} {11,19,31} {13,17,29} {41,163} {43,157}
# {47,151} {53,149} {59,139} {61,137} {67,131} {71,127} {73,113} {79,109}
# {83,107} {89,103} {97,101}). Each table is stored with its first 8 bytes
# repeated at the end so an unaligned 8-byte load at any phase < period is
# in bounds. A segment starts as the OR of all 16, four tables per pass:
# ~4 word-ops per byte, against the 3.9 marks per byte these primes would
# otherwise cost (37% of all marks).
-> psv_build_tabs(tabs, toff, tper, tprimes, rtab) (u8[] i64[] i64[] i64[] i64[]) i64
  k = 0
  while k < 16
    p0 = tprimes[k * 3]
    p1 = tprimes[k * 3 + 1]
    p2 = tprimes[k * 3 + 2]
    per = tper[k]
    base = toff[k]
    b = 0
    while b < per
      v = 0
      j = 0
      while j < 8
        x = 30 * b + rtab[j]
        if x % p0 == 0 || x % p1 == 0 || (p2 > 1 && x % p2 == 0)
          v = v | (1 << j)
        j += 1
      tabs[base + b] = v
      b += 1
    e = 0
    while e < 8
      tabs[base + per + e] = tabs[base + e]
      e += 1
    k += 1
  0

# OR four tables (g..g+3) into the segment, phased to cur_byte. rmw = 0 for
# the first pass (overwrites), 1 afterwards (ORs into what is there).
-> psv_or_tabs(seg, zoff, nbytes, tabs, toff, tper, g, cur_byte, rmw) (u8[] i64 i64 u8[] i64[] i64[] i64 i64 i64) i64
  a0 = toff[g] + cur_byte % tper[g]
  a1 = toff[g + 1] + cur_byte % tper[g + 1]
  a2 = toff[g + 2] + cur_byte % tper[g + 2]
  a3 = toff[g + 3] + cur_byte % tper[g + 3]
  l0 = toff[g] + tper[g]
  l1 = toff[g + 1] + tper[g + 1]
  l2 = toff[g + 2] + tper[g + 2]
  l3 = toff[g + 3] + tper[g + 3]
  z = zoff
  whole = zoff + nbytes - (nbytes & 7)
  # run-length: between wraps the four table streams advance in lockstep
  # with no bounds checks, so the inner loop is a plain 5-load/1-store
  # stream LLVM can widen.
  while z < whole
    run = whole - z
    run = l0 - a0 if l0 - a0 < run
    run = l1 - a1 if l1 - a1 < run
    run = l2 - a2 if l2 - a2 < run
    run = l3 - a3 if l3 - a3 < run
    run = run - (run & 7)
    if run < 8
      # a stream is within 8 bytes of its wrap: do this word with the
      # extended tail, then let the wrap adjustments below catch up
      run = 8
    # dead-local offset loop: `w` is the only induction and nothing outside
    # the loop reads it, so LLVM can count and vectorize it — the previous
    # form advanced z/a0..a3 in the loop, and five live-out inductions make
    # the loop vectorizer refuse ("value used outside the loop")
    if rmw == 0
      w = 0
      while w < run
        array_store_u64(seg, z + w, array_load_u64(tabs, a0 + w) | array_load_u64(tabs, a1 + w) | array_load_u64(tabs, a2 + w) | array_load_u64(tabs, a3 + w))
        w += 8
    else
      w = 0
      while w < run
        array_store_u64(seg, z + w, array_load_u64(seg, z + w) | array_load_u64(tabs, a0 + w) | array_load_u64(tabs, a1 + w) | array_load_u64(tabs, a2 + w) | array_load_u64(tabs, a3 + w))
        w += 8
    z += run
    a0 += run
    a1 += run
    a2 += run
    a3 += run
    a0 -= tper[g] if a0 >= l0
    a1 -= tper[g + 1] if a1 >= l1
    a2 -= tper[g + 2] if a2 >= l2
    a3 -= tper[g + 3] if a3 >= l3
  # tail bytes (only the last, short segment): one byte at a time
  while z < zoff + nbytes
    v = tabs[a0] | tabs[a1] | tabs[a2] | tabs[a3]
    v = v | seg[z] if rmw != 0
    seg[z] = v
    z += 1
    a0 += 1
    a0 -= tper[g] if a0 >= l0
    a1 += 1
    a1 -= tper[g + 1] if a1 >= l1
    a2 += 1
    a2 -= tper[g + 2] if a2 >= l2
    a3 += 1
    a3 -= tper[g + 3] if a3 >= l3
  0

-> psv_fill_tabs(seg, zoff, nbytes, tabs, toff, tper, cur_byte, ntab) (u8[] i64 i64 u8[] i64[] i64[] i64 i64) i64
  psv_or_tabs(seg, zoff, nbytes, tabs, toff, tper, 0, cur_byte, 0)
  g = 4
  while g < ntab
    psv_or_tabs(seg, zoff, nbytes, tabs, toff, tper, g, cur_byte, 1)
    g += 4
  0

# Unmarked candidates in the segment: 8 per byte minus the set bits. Eight
# bytes (240 integers) per popcount; the byte table only finishes the tail.
-> psv_count_zeros(seg, nbytes, pop) (u8[] i64 u8[]) i64
  n = 0
  z = 0
  whole = nbytes - (nbytes & 7)
  while z < whole
    n += popcount(array_load_u64(seg, z))
    z += 8
  while z < nbytes
    n += pop[seg[z]]
    z += 1
  nbytes * 8 - n

# Integer square root (floor), exact for the whole i64 range — the sieve
# bounds can exceed 2^48, where a Float sqrt loses precision and the boxed
# value is a bigint with no `sqrt` at all.
-> psv_isqrt(n) (i64) i64
  return 0 if n <= 0
  x = n
  y = (x + 1) / 2
  while y < x
    x = y
    y = (x + n / x) / 2
  x

# Primes coprime to 30 in [7, root] that the presieve tables do not cover.
-> psv_base_primes(root, bps, tpr, ntab) (i64 i64[] i64[] i64) i64
  half = (root - 1) / 2
  small = u8[half + 2]
  i = 1
  p = 3
  while p * p <= root
    if small[i] == 0
      j = (p * p - 1) / 2
      while j <= half
        small[j] = 1
        j += p
    i += 1
    p = 2 * i + 1
  idx = 0
  k = 1
  while k <= half
    if small[k] == 0
      q = 2 * k + 1
      if q >= 7 && q % 3 != 0 && q % 5 != 0
        # primes the presieve tables in use already cover never sieve
        covered = false
        if q <= 163
          t = 0
          while t < ntab * 3
            covered = true if tpr[t] == q
            t += 1
        if !covered
          bps[idx] = q
          idx += 1
    k += 1
  idx

# --- small tier: one loop per prime marks all 8 residues of a cycle ---
# Multiples p*(30t + R[j]) sit at byte p*t + off[j], off[j] = p30*R[j] +
# (r*R[j])/30 — eight constant offsets and eight constant masks per prime,
# so one loop iteration marks a whole cycle (8 independent RMWs, one add).
# State per prime: the cycle base byte (absolute) and the first residue of
# that cycle not yet marked (a cycle can straddle a segment boundary).
-> psv_seed_small(i, p, lo, sbase, sj, soff, scls, rtab, clsof) (i64 i64 i64 i64[] u8[] i64[] u8[] i64[] i64[]) i64
  p30 = p / 30
  r = p % 30
  scls[i] = clsof[r]
  j = 0
  while j < 8
    soff[i * 8 + j] = p30 * rtab[j] + (r * rtab[j]) / 30
    j += 1
  # first cycle t with some multiple >= lo: t = max(ceil(lo/p), p) rounded to
  # the cycle base p*floor(q/30); then skip residues below lo
  # first multiple to mark is >= max(lo, p*p): the cycle base is p*t for
  # t = floor(q/30), and the residues of that cycle below the bound are
  # skipped (for 23 and 29 cycle 0 even contains p*1 — the prime itself)
  start = lo
  start = p * p if start < p * p
  q = (start + p - 1) / p
  t = q / 30
  base = p * t
  jj = 0
  jj += 1 while jj < 8 && p * (30 * t + rtab[jj]) < start
  if jj == 8
    base += p
    jj = 0
  sbase[i] = base
  sj[i] = jj
  0

-> psv_mark_small(seg, zoff, bps, sbase, sj, soff, scls, bitm, n_small, cur_byte, nbytes) (u8[] i64 i64[] i64[] u8[] i64[] u8[] u8[] i64 i64 i64) i64
  lim = zoff + nbytes
  i = 0
  while i < n_small
    p = bps[i]
    by = sbase[i] - cur_byte + zoff
    j = sj[i]
    i8 = i * 8
    c8 = scls[i] * 8
    o0 = soff[i8]
    o1 = soff[i8 + 1]
    o2 = soff[i8 + 2]
    o3 = soff[i8 + 3]
    o4 = soff[i8 + 4]
    o5 = soff[i8 + 5]
    o6 = soff[i8 + 6]
    o7 = soff[i8 + 7]
    m0 = bitm[c8]
    m1 = bitm[c8 + 1]
    m2 = bitm[c8 + 2]
    m3 = bitm[c8 + 3]
    m4 = bitm[c8 + 4]
    m5 = bitm[c8 + 5]
    m6 = bitm[c8 + 6]
    m7 = bitm[c8 + 7]
    # finish a cycle left half-done by the previous segment
    done = false
    while j < 8 && !done
      o = by + soff[i8 + j]
      if o < lim
        seg[o] = seg[o] | bitm[c8 + j]
        j += 1
      else
        done = true
    if !done
      by += p
      # whole cycles: all eight marks in bounds
      while by + o7 < lim
        seg[by + o0] = seg[by + o0] | m0
        seg[by + o1] = seg[by + o1] | m1
        seg[by + o2] = seg[by + o2] | m2
        seg[by + o3] = seg[by + o3] | m3
        seg[by + o4] = seg[by + o4] | m4
        seg[by + o5] = seg[by + o5] | m5
        seg[by + o6] = seg[by + o6] | m6
        seg[by + o7] = seg[by + o7] | m7
        by += p
      # partial tail cycle
      j = 0
      while j < 8 && by + soff[i8 + j] < lim
        o = by + soff[i8 + j]
        seg[o] = seg[o] | bitm[c8 + j]
        j += 1
    sbase[i] = by - zoff + cur_byte
    sj[i] = j
    i += 1
  0

# --- medium/large tier: one record per prime, wheel state machine ---

# Seed record i (prime index i) at its first multiple ≥ start (never below
# p*p): next multiplier q coprime to 30, its residue rank, the prime's class.
-> psv_seed(i, p, start, nxt, wj, cls, p30, nextq, rank, clsof) (i64 i64 i64 i64[] u8[] u8[] i64[] i64[] i64[] i64[]) i64
  q0 = (start + p - 1) / p
  q0 = p if q0 < p
  s = q0 % 30
  q = q0 - s + nextq[s]
  nxt[i] = (p * q) / 30
  wj[i] = rank[q % 30]
  cls[i] = clsof[p % 30]
  p30[i] = p / 30
  nxt[i]

# File record i under the bucket of the segment its next multiple (byte gb)
# lands in.
-> psv_file(i, gb, cur_byte, seg_bytes, ring, rp, link, head) (i64 i64 i64 i64 i64 i64 i64[] i64[]) i64
  slot = rp + (gb - cur_byte) / seg_bytes
  slot -= ring if slot >= ring
  link[i] = head[slot]
  head[slot] = i
  0

# Flat medium tier: a record whose largest in-cycle mark gap (p/5 bytes)
# fits inside an outer segment lands in EVERY segment, so ring bookkeeping
# (file, link-chase, slot math) buys nothing — walk those records as a
# plain array sweep, state staying in nxt/wj. Sequential loads of
# nxt/wj/cls/p30 prefetch perfectly and consecutive records' marks are
# independent, unlike the ring's serial link chase. (primesieve's
# EratMedium/EratBig split, arrived at from our own bound: at 1e12 every
# base prime is medium — the ring is empty until root > 5·outer_bytes.)
-> psv_mark_medium(seg, nxt, wj, cls, p30, dr, ctab, bitm, from, to, cur_byte, nbytes) (u8[] i64[] u8[] u8[] i64[] i64[] i64[] u8[] i64 i64 i64 i64) i64
  i = from
  while i < to
    by = nxt[i] - cur_byte
    if by < nbytes
      j = wj[i]
      c8 = cls[i] * 8
      q = p30[i]
      # roll to the top of the wheel cycle …
      while j != 0 && by < nbytes
        seg[by] = seg[by] | bitm[c8 + j]
        by += q * dr[j] + ctab[c8 + j]
        j = (j + 1) & 7
      if by + q * 30 + 30 < nbytes
        # … then whole cycles with the eight steps and masks hoisted: one
        # add + one RMW per mark keeps the reorder window packed with
        # marks, so many L2 misses stay in flight at once (the rolled
        # loop's table loads and madd cost 3x the window per mark)
        s0 = q * dr[0] + ctab[c8]
        s1 = q * dr[1] + ctab[c8 + 1]
        s2 = q * dr[2] + ctab[c8 + 2]
        s3 = q * dr[3] + ctab[c8 + 3]
        s4 = q * dr[4] + ctab[c8 + 4]
        s5 = q * dr[5] + ctab[c8 + 5]
        s6 = q * dr[6] + ctab[c8 + 6]
        s7 = q * dr[7] + ctab[c8 + 7]
        m0 = bitm[c8]
        m1 = bitm[c8 + 1]
        m2 = bitm[c8 + 2]
        m3 = bitm[c8 + 3]
        m4 = bitm[c8 + 4]
        m5 = bitm[c8 + 5]
        m6 = bitm[c8 + 6]
        m7 = bitm[c8 + 7]
        pb = s0 + s1 + s2 + s3 + s4 + s5 + s6 + s7
        while by + pb <= nbytes
          seg[by] = seg[by] | m0
          by += s0
          seg[by] = seg[by] | m1
          by += s1
          seg[by] = seg[by] | m2
          by += s2
          seg[by] = seg[by] | m3
          by += s3
          seg[by] = seg[by] | m4
          by += s4
          seg[by] = seg[by] | m5
          by += s5
          seg[by] = seg[by] | m6
          by += s6
          seg[by] = seg[by] | m7
          by += s7
      # … and the partial cycle at the segment's end
      while by < nbytes
        seg[by] = seg[by] | bitm[c8 + j]
        by += q * dr[j] + ctab[c8 + j]
        j = (j + 1) & 7
      nxt[i] = by + cur_byte
      wj[i] = j
    i += 1
  0

# Walk this segment's bucket: each record marks through the segment along
# its residue cycle, then is re-filed under the segment it lands in next.
-> psv_mark_bucket(seg, nxt, wj, cls, p30, link, head, dr, ctab, bitm, rp, ring, cur_byte, nbytes, end_byte, seg_bytes) (u8[] i64[] u8[] u8[] i64[] i64[] i64[] i64[] i64[] u8[] i64 i64 i64 i64 i64 i64) i64
  i = head[rp]
  head[rp] = -1
  while i >= 0
    ni = link[i]
    by = nxt[i] - cur_byte
    j = wj[i]
    c8 = cls[i] * 8
    q = p30[i]
    while by < nbytes
      seg[by] = seg[by] | bitm[c8 + j]
      by += q * dr[j] + ctab[c8 + j]
      j = (j + 1) & 7
    gb = by + cur_byte
    nxt[i] = gb
    wj[i] = j
    if gb < end_byte
      slot = rp + (gb - cur_byte) / seg_bytes
      slot -= ring if slot >= ring
      link[i] = head[slot]
      head[slot] = i
    i = ni
  0

# Enumerate a segment's primes in order. mode 1: stop at the want-th prime
# overall (`have` were seen before this segment), store it in out[0] and
# return the count seen here. mode 2: append each prime to outarr from
# out_off, never past out_cap.
-> psv_scan_segment(seg, nbytes, seg_lo_byte, rtab, mode, want, have, outarr, out_off, out_cap, out) (u8[] i64 i64 i64[] i64 i64 i64 i64[] i64 i64 i64[]) i64
  n = 0
  i = 0
  while i < nbytes
    v = seg[i]
    if v != 255
      bb = seg_lo_byte + i
      j = 0
      while j < 8
        if (v & (1 << j)) == 0
          n += 1
          prime = 30 * bb + rtab[j]
          if mode == 1
            if have + n == want
              out[0] = prime
              return n
          else
            if out_off + n - 1 < out_cap
              outarr[out_off + n - 1] = prime
        j += 1
    i += 1
  n

# Gap-encode a segment's primes ≤ limit into gbuf (mode 3): one byte per
# prime, (p - previous)/2, with 0 meaning "add 255 and read on" — odds only,
# so every gap is even and 2 is never encoded. State rides in out:
# out[1] = previous prime (0 = none yet: the first prime is recorded in
# out[3] as the chunk's header instead of encoded), out[2] = write offset,
# out[4] = overflow flag, out[5] = gbuf capacity. Walks the zero bits of
# each 64-bit word with cttz, so a prime costs a handful of ops.
-> psv_gap_segment(seg, nbytes, seg_lo_byte, rtab, limit, gbuf, out) (u8[] i64 i64 i64[] i64 u8[] i64[]) i64
  n = 0
  last = out[1]
  o = out[2]
  cap = out[5]
  i = 0
  while i < nbytes
    if o + 32 > cap
      out[4] = 1
      out[1] = last
      out[2] = o
      return n
    w = array_load_u64(seg, i)
    w = w | ((0 - 1) << ((nbytes - i) * 8)) if nbytes - i < 8
    z = w ^ (0 - 1)
    while z != 0
      t = cttz(z)
      z = z & (z - 1)
      p = 30 * (seg_lo_byte + i + (t >> 3)) + rtab[t & 7]
      if p <= limit
        n += 1
        if last == 0
          out[3] = p
        else
          g = (p - last) >> 1
          while g > 255
            gbuf[o] = 0
            o += 1
            g -= 255
          gbuf[o] = g
          o += 1
        last = p
    i += 8
  out[1] = last
  out[2] = o
  n

# Sieve the wheel candidates in [lo, hi) — both multiples of 30 — with this
# thread's scratch. mode 0: return the prime count. mode 1: return the count
# through the want-th prime and write it to out[0]. mode 2: write every prime
# into outarr from out_off (bounded by out_cap) and return how many. mode 3:
# gap-encode every prime ≤ want into gbuf (see psv_gap_segment).
-> psv_sieve_range(lo, hi, bps, nbase, n_small, rtab, btab, tabs, toff, tper, tprimes, ntab, pop, seg_bytes, outer_bytes, ring, seg, sbase, sj, soff, scls, nxt, wj, cls, p30, link, head, dr, ctab, bitm, nextq, rank, clsof, mode, want, outarr, out_off, out_cap, out, gbuf) (i64 i64 i64[] i64 i64 i64[] i64[] u8[] i64[] i64[] i64[] i64 u8[] i64 i64 i64 u8[] i64[] u8[] i64[] u8[] i64[] u8[] u8[] i64[] i64[] i64[] i64[] i64[] u8[] i64[] i64[] i64[] i64 i64 i64[] i64 i64 i64[] u8[]) i64
  base_byte = lo / 30
  end_byte = hi / 30
  k = 0
  while k < ring
    head[k] = -1
    k += 1
  # small tier: seed each prime's cycle state at lo
  b = 0
  while b < n_small
    psv_seed_small(b, bps[b], lo, sbase, sj, soff, scls, rtab, clsof)
    b += 1
  # Medium/large boundary: the largest gap between a record's marks is
  # p/5 bytes, so p < 5·outer never skips an outer segment — flat sweep;
  # only larger primes use the ring (empty until root > 5·outer_bytes).
  med_max = outer_bytes * 5
  # medium/large already in play at lo: seed each record; only large ones
  # get filed in the ring
  active = n_small
  while active < nbase && bps[active] * bps[active] < lo
    gb = psv_seed(active, bps[active], lo, nxt, wj, cls, p30, nextq, rank, clsof)
    psv_file(active, gb, base_byte, outer_bytes, ring, 0, link, head) if gb < end_byte && bps[active] >= med_max
    active += 1
  med_end = active
  med_end = n_small if med_end < n_small
  # (primes enter in ascending order, so actives split at the first large
  # prime; at benchmark scales that is all of them)
  while med_end > n_small && bps[med_end - 1] >= med_max
    med_end -= 1
  count = 0
  cur_byte = base_byte
  rp = 0
  while cur_byte < end_byte
    nbytes = end_byte - cur_byte
    nbytes = outer_bytes if nbytes > outer_bytes
    # L1 sub-segments: presieve fill + small tier, in place
    sub = 0
    while sub < nbytes
      sublen = nbytes - sub
      sublen = seg_bytes if sublen > seg_bytes
      cur_sub = cur_byte + sub
      psv_fill_tabs(seg, sub, sublen, tabs, toff, tper, cur_sub, ntab)
      if cur_sub <= 5
        # the tables mark 7..163 themselves (p*1, bytes 0..5): clear those
        # bits in whichever sub-segment holds them; candidate 1 is composite
        t = 0
        while t < ntab * 3
          pp = tprimes[t]
          if pp > 1 && pp / 30 >= cur_sub && pp / 30 < cur_sub + sublen
            seg[sub + pp / 30 - cur_sub] = seg[sub + pp / 30 - cur_sub] & (255 - (1 << rank[pp % 30]))
          t += 1
        seg[0] = seg[0] | 1 if cur_sub == 0
      psv_mark_small(seg, sub, bps, sbase, sj, soff, scls, bitm, n_small, cur_sub, sublen)
      sub += sublen
    # primes whose square first lands in this outer segment enter now
    top = (cur_byte + nbytes) * 30
    while active < nbase && bps[active] * bps[active] < top
      p = bps[active]
      gb = psv_seed(active, p, p * p, nxt, wj, cls, p30, nextq, rank, clsof)
      if p < med_max
        med_end = active + 1 if med_end == active
      else
        psv_file(active, gb, cur_byte, outer_bytes, ring, rp, link, head) if gb < end_byte
      active += 1
    # flat medium sweep, then the (usually empty) large-prime ring
    psv_mark_medium(seg, nxt, wj, cls, p30, dr, ctab, bitm, n_small, med_end, cur_byte, nbytes)
    psv_mark_bucket(seg, nxt, wj, cls, p30, link, head, dr, ctab, bitm, rp, ring, cur_byte, nbytes, end_byte, outer_bytes)
    if mode == 0
      count += psv_count_zeros(seg, nbytes, pop)
    else
      if mode == 3
        count += psv_gap_segment(seg, nbytes, cur_byte, rtab, want, gbuf, out)
        return count if out[4] != 0
      else
        got = psv_scan_segment(seg, nbytes, cur_byte, rtab, mode, want, count, outarr, out_off + count, out_cap, out)
        count += got
        return count if mode == 1 && count >= want
    cur_byte += nbytes
    rp += 1
    rp = 0 if rp >= ring
  count

# ----------------------------------------------------------------- drivers --

# Worker threads: cpu_count - 1 (one core left for the OS and the caller);
# TUNGSTEN_PRIME_THREADS overrides.
-> psv_threads
  e = env("TUNGSTEN_PRIME_THREADS")
  if e != nil && e != ""
    t = e.to_i
    return t if t > 0
  t = cpu_count - 1
  t = 1 if t < 1
  t

# Segment = one L1D; primes below half the segment (in bytes = stride) take
# the small tier — measured best at 1e11–1e12 (a 2-mark stride loop still
# beats the state machine).
-> psv_seg_bytes
  # Half the L1D, not all of it: PMC profiling (flame --counters, 1e12)
  # showed the small tier missing L1 on ~1 of 3 marks with full-L1
  # sub-segments — the segment alone fills the cache and the offset/mask
  # tables evict it. L1/2 measured ~2% faster single-threaded, 4-6% at
  # 1e11/15T, ~3% at 1e12/15T; L1/4 is slower, and moving the small/bucket
  # boundary (seg/5, seg*0.35) gains nothing over seg/2.
  l1d_cache_bytes / 2

-> psv_small_max(seg_bytes)
  seg_bytes / 2

# Shared read-only context for a sieve up to root, as an array:
#   0 rtab  1 btab  2 tabs  3 pop  4 bps  5 nbase  6 n_small  7 dr  8 ctab
#   9 bitm  10 nextq  11 rank  12 clsof  13 toff  14 tper  15 tpr  16 ntab
#   17 outer_bytes
# Outer (bucket-tier) segment: a power of two, ~2·√N like primesieve, never
# below one L1,
# and capped at a quarter of a core's L2 share (l2_cache_bytes / cpus_per_l2)
# — the rest of the share is for the sieving-prime records and the presieve
# tables that stream through L2 with it. On a 16 MB L2 shared by 6 P-cores
# that is 512 KB, measured best at 1e12 with 15 threads (13.9 s vs 17.7 s at
# 4 MB); single-threaded the cap costs ~0.5%.
-> psv_outer_bytes(root, seg_bytes)
  want = 2 * root
  cap = l2_cache_bytes / cpus_per_l2 / 4
  cap = seg_bytes if cap < seg_bytes
  o = 1
  o *= 2 while o * 2 <= seg_bytes
  o *= 2 while o * 2 <= want && o * 2 <= cap
  o

-> psv_setup(root, small_max, seg_bytes)
  rtab = i64[8]
  rtab[0] = 1
  rtab[1] = 7
  rtab[2] = 11
  rtab[3] = 13
  rtab[4] = 17
  rtab[5] = 19
  rtab[6] = 23
  rtab[7] = 29
  rank = i64[30]
  clsof = i64[30]
  i = 0
  while i < 30
    rank[i] = -1
    clsof[i] = -1
    i += 1
  i = 0
  while i < 8
    rank[rtab[i]] = i
    clsof[rtab[i]] = i
    i += 1
  # nextq[s]: smallest residue ≥ s coprime to 30 (31 wraps to the next 1)
  nextq = i64[30]
  s = 0
  while s < 30
    v = s
    v += 1 while v < 30 && rank[v] < 0
    v = 31 if v >= 30
    nextq[s] = v
    s += 1
  btab = i64[240]
  i = 0
  while i < 30
    j = 0
    while j < 8
      btab[i * 8 + j] = rank[(i * rtab[j]) % 30]
      j += 1
    i += 1
  # wheel state machine: residue gaps, per-class byte carries and bit masks
  dr = i64[8]
  j = 0
  while j < 8
    nj = 31
    nj = rtab[j + 1] if j < 7
    dr[j] = nj - rtab[j]
    j += 1
  ctab = i64[64]
  bitm = u8[64]
  c = 0
  while c < 8
    r = rtab[c]
    j = 0
    while j < 8
      nj = 31
      nj = rtab[j + 1] if j < 7
      ctab[c * 8 + j] = (r * nj) / 30 - (r * rtab[j]) / 30
      bitm[c * 8 + j] = 1 << rank[(r * rtab[j]) % 30]
      j += 1
    c += 1
  pop = u8[256]
  t = 1
  while t < 256
    pop[t] = pop[t >> 1] + (t & 1)
    t += 1
  # presieve tables (see psv_build_tabs); tprimes holds 3 slots per table
  # (1 = unused). All 16 measured best; ntab is kept as a knob.
  ntab = 16
  tprimes = [7,23,37, 11,19,31, 13,17,29, 41,163,1, 43,157,1, 47,151,1, 53,149,1, 59,139,1, 61,137,1, 67,131,1, 71,127,1, 73,113,1, 79,109,1, 83,107,1, 89,103,1, 97,101,1]
  tpr = i64[48]
  tper = i64[16]
  toff = i64[16]
  total = 0
  k = 0
  while k < 16
    tpr[k * 3] = tprimes[k * 3]
    tpr[k * 3 + 1] = tprimes[k * 3 + 1]
    tpr[k * 3 + 2] = tprimes[k * 3 + 2]
    tper[k] = tprimes[k * 3] * tprimes[k * 3 + 1] * tprimes[k * 3 + 2]
    toff[k] = total
    total += tper[k] + 8
    k += 1
  tabs = u8[total]
  psv_build_tabs(tabs, toff, tper, tpr, rtab)
  bps = i64[root / 2 + 64]
  nbase = psv_base_primes(root, bps, tpr, ntab)
  n_small = 0
  n_small += 1 while n_small < nbase && bps[n_small] < small_max
  [rtab, btab, tabs, pop, bps, nbase, n_small, dr, ctab, bitm, nextq, rank, clsof, toff, tper, tpr, ntab, psv_outer_bytes(root, seg_bytes)]

# Per-thread scratch for a context:
#   0 seg  1 sbase  2 sj  3 soff  4 scls  5 nxt  6 wj  7 cls  8 p30  9 link
#   10 head  11 out
# head and out are padded to their own cache lines: they are written on
# every record visit / segment, and threads allocate scratch concurrently.
-> psv_scratch(ctx, seg_bytes, ring)
  nbase = ctx[5]
  n_small = ctx[6]
  [u8[ctx[17]], i64[n_small + 1], u8[n_small + 1], i64[n_small * 8 + 8], u8[n_small + 1], i64[nbase + 1], u8[nbase + 1], u8[nbase + 1], i64[nbase + 1], i64[nbase + 1], i64[ring + 64], i64[64]]

# Sieve one chunk with a context and a scratch set (unpacks for the kernel).
-> psv_run_chunk(ctx, sc, lo, hi, seg_bytes, ring, mode, want, outarr, out_off, out_cap)
  psv_run_chunk_g(ctx, sc, lo, hi, seg_bytes, ring, mode, want, outarr, out_off, out_cap, u8[1])

# Same, with the gap buffer for mode 3.
-> psv_run_chunk_g(ctx, sc, lo, hi, seg_bytes, ring, mode, want, outarr, out_off, out_cap, gbuf)
  psv_sieve_range(lo, hi, ctx[4], ctx[5], ctx[6], ctx[0], ctx[1], ctx[2], ctx[13], ctx[14], ctx[15], ctx[16], ctx[3], seg_bytes, ctx[17], ring, sc[0], sc[1], sc[2], sc[3], sc[4], sc[5], sc[6], sc[7], sc[8], sc[9], sc[10], ctx[7], ctx[8], ctx[9], ctx[10], ctx[11], ctx[12], mode, want, outarr, out_off, out_cap, sc[11], gbuf)

# Count the primes in [lo, hi) — multiples of 30 — across threads. Every
# chunk's count lands in counts[c] (size it with psv_threads * 4 + 8);
# meta[0] = chunk span, meta[1] = chunk count. Returns the total.
-> psv_sieve_parallel(lo, hi, root, ctx, seg_bytes, counts, meta)
  nthreads = psv_threads
  span = hi - lo
  # ~4 chunks per thread so a slow chunk cannot strand a core, never smaller
  # than 4 segments (chunk setup costs nbase divisions).
  chunk = span / (nthreads * 4) + 1
  min_chunk = ctx[17] * 30 * 4
  chunk = min_chunk if chunk < min_chunk
  chunk = chunk - chunk % 30
  chunk = 30 if chunk == 0
  nchunks = (span + chunk - 1) / chunk
  meta[0] = chunk
  meta[1] = nchunks
  ring = root / ctx[17] + 3
  counter = Atomic.new(0)
  nth = nthreads
  nth = nchunks if nchunks < nth
  threads = []
  i = 0
  while i < nth
    th = Thread.new ->
      sc = psv_scratch(ctx, seg_bytes, ring)
      none = i64[1]
      running = true
      while running
        c = counter.add(1)
        if c >= nchunks
          running = false
        else
          clo = lo + c * chunk
          chi = clo + chunk
          chi = hi if chi > hi
          counts[c] = psv_run_chunk(ctx, sc, clo, chi, seg_bytes, ring, 0, 0, none, 0, 0)
    threads.push(th)
    i += 1
  threads.each -> (t) t.join
  total = 0
  c = 0
  while c < nchunks
    total += counts[c]
    c += 1
  total

# Second pass for Int.primes: re-sieve each chunk in parallel, writing its
# primes straight into outarr at base_off + offs[c] (the prefix sum of the
# counting pass), never past base_off + cap.
-> psv_fill_parallel(lo, hi, root, ctx, seg_bytes, chunk, nchunks, offs, outarr, base_off, cap)
  ring = root / ctx[17] + 3
  counter = Atomic.new(0)
  nth = psv_threads
  nth = nchunks if nchunks < nth
  threads = []
  i = 0
  while i < nth
    th = Thread.new ->
      sc = psv_scratch(ctx, seg_bytes, ring)
      running = true
      while running
        c = counter.add(1)
        if c >= nchunks
          running = false
        elsif offs[c] < cap
          clo = lo + c * chunk
          chi = clo + chunk
          chi = hi if chi > hi
          psv_run_chunk(ctx, sc, clo, chi, seg_bytes, ring, 2, 0, outarr, base_off + offs[c], base_off + cap)
    threads.push(th)
    i += 1
  threads.each -> (t) t.join
  0

# ------------------------------------------------------------- checkpoints --

# (n, p_n) rungs: 16 per decade of n (ratio 1.155) up to 2e11 — the worst-case
# residual sieve is ~15% of the range. Generated by this sieve;
# the round-decade entries cross-check against the published A006988.
-> psv_ck_ranks
  [
    1, 2, 3, 4, 5, 6, 7, 8,
    9, 10, 12, 13, 15, 18, 21, 24,
    27, 32, 37, 42, 49, 56, 65, 75,
    87, 100, 115, 133, 154, 178, 205, 237,
    274, 316, 365, 422, 487, 562, 649, 750,
    866, 1000, 1155, 1334, 1540, 1778, 2054, 2371,
    2738, 3162, 3652, 4217, 4870, 5623, 6494, 7499,
    8660, 10000, 11548, 13335, 15399, 17783, 20535, 23714,
    27384, 31623, 36517, 42170, 48697, 56234, 64938, 74989,
    86596, 100000, 115478, 133352, 153993, 177828, 205353, 237137,
    273842, 316228, 365174, 421697, 486968, 562341, 649382, 749894,
    865964, 1000000, 1154782, 1333521, 1539927, 1778279, 2053525, 2371374,
    2738420, 3162278, 3651741, 4216965, 4869675, 5623413, 6493816, 7498942,
    8659643, 10000000, 11547820, 13335214, 15399265, 17782794, 20535250, 23713737,
    27384196, 31622777, 36517413, 42169650, 48696753, 56234133, 64938163, 74989421,
    86596432, 100000000, 115478198, 133352143, 153992653, 177827941, 205352503, 237137371,
    273841963, 316227766, 365174127, 421696503, 486967525, 562341325, 649381632, 749894209,
    865964323, 1000000000, 1154781985, 1333521432, 1539926526, 1778279410, 2053525026, 2371373706,
    2738419634, 3162277660, 3651741273, 4216965034, 4869675252, 5623413252, 6493816316, 7498942093,
    8659643234, 10000000000, 11547819847, 13335214322, 15399265261, 17782794100, 20535250265, 23713737057,
    27384196343, 31622776602, 36517412725, 42169650343, 48696752517, 56234132519, 64938163158, 74989420933,
    86596432336, 100000000000, 115478198469, 133352143216, 153992652606, 177827941004, 200000000000
  ]

-> psv_ck_primes
  [
    2, 3, 5, 7, 11, 13, 17, 19,
    23, 29, 37, 41, 47, 61, 73, 89,
    103, 131, 157, 181, 227, 263, 313, 379,
    449, 541, 631, 751, 887, 1061, 1259, 1489,
    1759, 2089, 2467, 2917, 3469, 4079, 4817, 5693,
    6709, 7919, 9337, 10987, 12923, 15233, 17921, 21089,
    24749, 29077, 34171, 40151, 47221, 55351, 65003, 76163,
    89431, 104729, 122827, 143879, 168851, 197567, 231223, 270821,
    317333, 371341, 434411, 508373, 594641, 695663, 813419, 951053,
    1111933, 1299709, 1518359, 1775483, 2073263, 2422499, 2829173, 3303673,
    3858037, 4504187, 5257771, 6138347, 7162783, 8359217, 9753283, 11379911,
    13275047, 15485863, 18057719, 21059411, 24556643, 28631353, 33377957, 38911853,
    45354593, 52861967, 61607851, 71788657, 83647931, 97458523, 113532631, 132256987,
    154058459, 179424673, 208971977, 243352939, 283369813, 329948117, 384144283, 447228029,
    520634327, 606021547, 705387541, 820986011, 955483121, 1111902161, 1293902201, 1505553317,
    1751752693, 2038074743, 2371057831, 2758286197, 3208566457, 3732123991, 4340926267, 5048751619,
    5871653539, 6828315107, 7940524673, 9233320783, 10736084431, 12482775703, 14513005769, 16872544243,
    19614909773, 22801763489, 26505317239, 30808934659, 35809720553, 41620456477, 48372005141, 56216065657,
    65329729973, 75917591177, 88217720893, 102506342207, 119105068351, 138385765559, 160781234923, 186794173759,
    217007113927, 252097800623, 292851683297, 340180945801, 395145714077, 458974701277, 533095247933, 619164573091,
    719105134339, 835147893659, 969885063803, 1126322354959, 1307948901911, 1518814549367, 1763619982541, 2047817065183,
    2377739396033, 2760727302517, 3205307224573, 3721369481477, 4320388749199, 5015681859119, 5665449960167
  ]

# Index of the largest rung with n ≤ want (always ≥ 0 for want ≥ 1).
-> psv_ck_by_rank(want)
  ns = psv_ck_ranks
  best = -1
  i = 0
  while i < ns.size
    return best if ns[i] > want
    best = i
    i += 1
  best

# Index of the largest rung with p ≤ x, or -1.
-> psv_ck_by_value(x)
  ps = psv_ck_primes
  best = -1
  i = 0
  while i < ps.size
    return best if ps[i] > x
    best = i
    i += 1
  best

# --------------------------------------------------------------------- api --

-> psv_wheel_candidate?(x)
  r = x % 30
  r == 1 || r == 7 || r == 11 || r == 13 || r == 17 || r == 19 || r == 23 || r == 29

# Primes in [lo, hi] inclusive, sieved directly (no checkpoint skip). The
# window is widened to multiples of 30 and the edge candidates outside
# [lo, hi] — at most 8 per side — are settled with the scalar test.
-> psv_count_raw(lo, hi)
  return 0 if hi < 2 || hi < lo
  lo = 2 if lo < 2
  count = 0
  count += 1 if lo <= 2 && hi >= 2
  count += 1 if lo <= 3 && hi >= 3
  count += 1 if lo <= 5 && hi >= 5
  return count if hi < 7
  lo = 7 if lo < 7
  alo = (lo / 30) * 30
  ahi = ((hi / 30) + 1) * 30
  root = psv_isqrt(hi) + 1
  seg_bytes = psv_seg_bytes
  ctx = psv_setup(root, psv_small_max(seg_bytes), seg_bytes)
  counts = i64[psv_threads * 4 + 8]
  meta = i64[2]
  count += psv_sieve_parallel(alo, ahi, root, ctx, seg_bytes, counts, meta)
  x = alo
  while x < lo
    count -= 1 if x > 1 && psv_wheel_candidate?(x) && x.prime?
    x += 1
  x = hi + 1
  while x < ahi
    count -= 1 if psv_wheel_candidate?(x) && x.prime?
    x += 1
  count

# π(x): primes ≤ x, starting from the nearest rung at or below x.
-> psv_pi(x)
  return 0 if x < 2
  i = psv_ck_by_value(x)
  return psv_count_raw(2, x) if i < 0
  ns = psv_ck_ranks
  ps = psv_ck_primes
  return ns[i] if ps[i] == x
  ns[i] + psv_count_raw(ps[i] + 1, x)

# Primes in [lo, hi] inclusive. Uses the rungs as π(hi) - π(lo - 1) whenever
# that sieves less than the range itself.
-> psv_count(lo, hi)
  return 0 if hi < 2 || hi < lo
  lo = 2 if lo < 2
  return psv_pi(hi) if lo == 2
  ps = psv_ck_primes
  ih = psv_ck_by_value(hi)
  il = psv_ck_by_value(lo - 1)
  return psv_count_raw(lo, hi) if ih < 0
  via = hi - ps[ih]
  via += lo
  via = via - lo + (lo - 1 - ps[il]) if il >= 0
  return psv_pi(hi) - psv_pi(lo - 1) if via < hi - lo
  psv_count_raw(lo, hi)

# The n-th prime, sieving forward from rung (rank0, prime0).
-> psv_nth_from(n, rank0, prime0)
  need = n - rank0
  # Dusart: p_n < n(ln n + ln ln n) for n ≥ 6 — a safe upper end.
  nf = n.to_f
  ln = Math.log(nf)
  two = 2.to_f
  ln = two if ln < two
  lnln = Math.log(ln)
  hi = (nf * (ln + lnln)).to_i + 64
  lo = (prime0 / 30) * 30 + 30
  # primes between the rung and the aligned window start
  x = prime0 + 1
  while x < lo
    if x.prime?
      need -= 1
      return x if need == 0
    x += 1
  seg_bytes = psv_seg_bytes
  while true
    ahi = ((hi / 30) + 1) * 30
    root = psv_isqrt(ahi) + 1
    ctx = psv_setup(root, psv_small_max(seg_bytes), seg_bytes)
    counts = i64[psv_threads * 4 + 8]
    meta = i64[2]
    total = psv_sieve_parallel(lo, ahi, root, ctx, seg_bytes, counts, meta)
    if total >= need
      chunk = meta[0]
      nchunks = meta[1]
      acc = 0
      c = 0
      while c < nchunks && acc + counts[c] < need
        acc += counts[c]
        c += 1
      clo = lo + c * chunk
      chi = clo + chunk
      chi = ahi if chi > ahi
      want = need - acc
      # Narrow the hit chunk with all threads before the single-threaded find:
      # re-count it as sub-chunks, keep the one holding the want-th prime.
      # A chunk is ~span/(4·threads); one narrowing pass takes the find down
      # to a few outer segments.
      ring = root / ctx[17] + 3
      if chi - clo > ctx[17] * 30 * 8
        counts2 = i64[psv_threads * 4 + 8]
        meta2 = i64[2]
        psv_sieve_parallel(clo, chi, root, ctx, seg_bytes, counts2, meta2)
        chunk2 = meta2[0]
        nchunks2 = meta2[1]
        acc2 = 0
        c2 = 0
        while c2 < nchunks2 && acc2 + counts2[c2] < want
          acc2 += counts2[c2]
          c2 += 1
        want -= acc2
        clo = clo + c2 * chunk2
        chi2 = clo + chunk2
        chi = chi2 if chi2 < chi
      sc = psv_scratch(ctx, seg_bytes, ring)
      none = i64[1]
      psv_run_chunk(ctx, sc, clo, chi, seg_bytes, ring, 1, want, none, 0, 0)
      out = sc[11]
      return out[0]
    # the estimate fell short — extend the window and keep going
    need -= total
    lo = ahi
    hi = ahi + ahi / 16 + 1000
  0

# The n-th prime, 1-indexed: exact rung hit, else sieve up from the rung below.
-> psv_nth(n)
  return 0 if n <= 0
  i = psv_ck_by_rank(n)
  ns = psv_ck_ranks
  ps = psv_ck_primes
  return ps[i] if ns[i] == n
  psv_nth_from(n, ns[i], ps[i])

# The first n primes, ascending, as an i64 typed array.
-> psv_first(n)
  n = 0 if n < 0
  raise "Int.primes: refusing above 200M primes (1.6 GB) — sieve a range instead" if n > 200000000
  out = i64[n]
  return out if n == 0
  small = [2, 3, 5]
  i = 0
  while i < n && i < 3
    out[i] = small[i]
    i += 1
  return out if n <= 3
  need = n - 3
  nf = n.to_f
  ln = Math.log(nf)
  two = 2.to_f
  ln = two if ln < two
  lnln = Math.log(ln)
  hi = (nf * (ln + lnln)).to_i + 64
  seg_bytes = psv_seg_bytes
  while true
    ahi = ((hi / 30) + 1) * 30
    root = psv_isqrt(ahi) + 1
    ctx = psv_setup(root, psv_small_max(seg_bytes), seg_bytes)
    counts = i64[psv_threads * 4 + 8]
    meta = i64[2]
    total = psv_sieve_parallel(0, ahi, root, ctx, seg_bytes, counts, meta)
    if total >= need
      chunk = meta[0]
      nchunks = meta[1]
      offs = i64[nchunks + 1]
      acc = 0
      c = 0
      while c < nchunks
        offs[c] = acc
        acc += counts[c]
        c += 1
      psv_fill_parallel(0, ahi, root, ctx, seg_bytes, chunk, nchunks, offs, out, 3, need)
      return out
    hi += hi / 8 + 1000
  out

# Write the first n primes as gap-encoded files dir/primes.NNN of up to
# ~1e9 primes each (at least one file per thread for lists above 1e6·threads): an 8-byte little-endian first prime, then one byte per
# following prime = (p - previous)/2, 0 meaning "add 255 and read on".
# Odds only — 2 is implied, the first file starts at 3. p_n comes from the
# rungs (instant on a rung, otherwise nth_prime sieves for it); the range
# [0, p_n] is cut into as many chunks as files and each thread sieves its
# chunk in gap mode into its own buffer, then writes the file — no ordering
# between threads, every file decodes on its own. Buffer bound per chunk:
# 1.05·Δ/(ln(mid) − 1.1) plus one escape per 510 (overflow raises).
# TUNGSTEN_PRIME_KEEP=K keeps only the first K files, deleting the others
# right after they are written — to time the pipeline on a disk too small
# for the whole list. Returns the byte count written.
-> psv_gap_files(n, dir)
  raise "primes: n must be at least 3 (the first file starts at 3)" if n < 3
  pn = psv_nth(n)
  ahi = ((pn / 30) + 1) * 30
  root = psv_isqrt(ahi) + 1
  seg_bytes = psv_seg_bytes
  ctx = psv_setup(root, psv_small_max(seg_bytes), seg_bytes)
  ring = root / ctx[17] + 3
  # ~1e9 primes per file, but never fewer files than threads (down to 1e6
  # primes each) so a small list is still sieved in parallel
  nfiles = (n + 999999999) / 1000000000
  small = n / 1000000
  small = psv_threads if small > psv_threads
  nfiles = small if nfiles < small
  chunk = ((ahi / nfiles) / 30 + 1) * 30
  nchunks = (ahi + chunk - 1) / chunk
  bound = psv_gap_bound(0, chunk)
  keep = nchunks
  ek = env("TUNGSTEN_PRIME_KEEP")
  keep = ek.to_i if ek != nil && ek != ""
  counts = i64[nchunks + 1]
  sizes = i64[nchunks + 1]
  counter = Atomic.new(0)
  nth = psv_threads
  nth = nchunks if nchunks < nth
  threads = []
  i = 0
  while i < nth
    th = Thread.new ->
      sc = psv_scratch(ctx, seg_bytes, ring)
      gbuf = u8[bound]
      none = i64[1]
      out = sc[11]
      running = true
      while running
        c = counter.add(1)
        if c >= nchunks
          running = false
        else
          clo = c * chunk
          chi = clo + chunk
          chi = ahi if chi > ahi
          out[1] = 0
          out[2] = 8
          out[3] = 0
          out[4] = 0
          out[5] = bound
          got = 0
          if c == 0
            # 2 is implied; the file opens at 3, then 5 (gap byte 1)
            out[3] = 3
            gbuf[8] = 1
            out[2] = 9
            out[1] = 5
            got = 2
          got += psv_run_chunk_g(ctx, sc, clo, chi, seg_bytes, ring, 3, pn, none, 0, 0, gbuf)
          raise "primes: gap buffer overflow in chunk " + c.to_s if out[4] != 0
          first = out[3]
          k = 0
          while k < 8
            gbuf[k] = (first >> (k * 8)) & 255
            k += 1
          nbytes = out[2]
          path = dir + "/primes." + psv_pad3(c)
          ok = write_file_bytes_n(path, gbuf, nbytes)
          raise "primes: could not write " + path if !ok
          File.rm(path) if c >= keep
          counts[c] = got
          sizes[c] = nbytes
    threads.push(th)
    i += 1
  threads.each -> (t) t.join
  total = 0
  bytes = 0
  c = 0
  while c < nchunks
    total += counts[c]
    bytes += sizes[c]
    c += 1
  raise "primes: wrote " + total.to_s + " primes, expected " + n.to_s if total + 1 != n
  bytes

# Integer bound on the bytes a chunk [lo, lo + span) can encode to:
# 1.05·span/(ln(mid) − 1.1) primes (ln via floor(log2)·0.693, which only
# lowers the denominator) plus an escape byte per 510 plus slack.
-> psv_gap_bound(lo, span)
  mid = lo + span / 2
  l2 = 0
  t = mid
  while t > 1
    t = t >> 1
    l2 += 1
  ln10 = l2 * 693 / 100
  ln10 = 12 if ln10 < 12
  span * 1050 / (100 * (ln10 - 11)) + span / 510 + 4096

-> psv_pad3(c)
  return "00" + c.to_s if c < 10
  return "0" + c.to_s if c < 100
  c.to_s

+ PrimeSieve
  # Primes in [lo, hi], inclusive.
  -> .count(lo, hi)
    psv_count(lo, hi)

  # π(x): how many primes are ≤ x.
  -> .pi(x)
    psv_pi(x)

  # The n-th prime, 1-indexed: PrimeSieve.nth(1) is 2.
  -> .nth(n)
    psv_nth(n)

  # The first n primes, ascending, as an i64 typed array.
  -> .first(n)
    psv_first(n)

  -> .write_gaps(n, dir)
    psv_gap_files(n, dir)
