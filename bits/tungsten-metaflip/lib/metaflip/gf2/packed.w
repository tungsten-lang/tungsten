# A GF(2) matrix-multiplication scheme as flat 64-bit limb arrays, and the two
# exactness gates that run on it. The two are independent formulations of the
# check, but they share this one representation and whatever reader and limb
# conversion filled it; the gate that shares neither is fiber_gate.w, which
# Scheme#defect(:both) and TensorVerifier.verify_text run after these two.
#
# A scheme <n,m,p> is a list of terms (u, v, w): u an n x m mask, v an m x p
# mask, w an n x p mask, packed row-major (u bit i*m+j = A[i][j], v bit j*p+k =
# B[j][k], w bit i*p+k = C[i][k]). It is exact when
#
#     sum over terms of  u (x) v (x) w  ==  sum over i,j,k of  a_ij (x) b_jk (x) c_ik
#
# over GF(2), i.e. for every coefficient (a, b) with a in [0, n*m) and b in
# [0, m*p) the XOR of the w masks of the terms whose u has bit a and whose v has
# bit b is exactly the bit i*p+k when a = i*m+j and b = j*p+k, and 0 otherwise.
#
# Packed keeps each of the three axes as one `i64[]` of rank * limbs entries,
# term-major (term t of u occupies ulimbs[t*wu, (t+1)*wu)), little-endian limbs
# (see bits.w). No BigInt is created anywhere on this path, which is what makes
# checking a rank-14,271 scheme of 1,024-bit masks a matter of milliseconds.
# Scheme (scheme.w) is the Integer-mask view of the same data; Packed.from_masks
# and Packed#masks convert between them.
#
# Invariant the gates rely on: every stored factor is nonzero and narrower than
# its matrix. The certificate reader (tensor_verifier.w) enforces it while
# parsing; from_masks stores what it is given (Scheme#defect tests the Integer
# masks first); `defect` starts with `range_defect`, which checks the arrays
# themselves, and reports a violation as a :range Defect before any gate runs.
#
# The two gates (both return nil for an exact scheme, else the first failing
# coefficient in row-major (a, b) order, so they must agree on the whole
# verdict, not just accept/reject):
#
#   defect_dense    A dense table T[a][b] of n*p-bit words is filled by XORing w
#                   into T[a][b] for every set bit a of u and b of v, then every
#                   one of the n*m * m*p entries is compared with the expected
#                   tensor (formulated like tools/verify_tensor.rb). The table
#                   is filled a band of rows at a time so that it stays within
#                   Packed.band_words limbs (a single band whenever it fits).
#   defect_sparse   Only the touched coefficients are stored, in an open-
#                   addressing hash keyed by a*(m*p)+b; the expected tensor is
#                   XORed in and every stored entry must end up zero
#                   (formulated like the `exact` of the Python tooling).
#
# `defect(gate)` selects :dense, :sparse, or :both (run both; they must agree,
# anything else is an internal error; on a Packed, :both is these two gates
# only, since the fiber gate needs the text or the masks the Packed came from). A gate only reports WHERE it saw a wrong
# coefficient; the Defect's expected and actual masks are then recomputed from the
# terms by a third, trivial routine (cell_row), and a report that does not
# reconstruct raises "internal error" instead of returning a wrong explanation.
#
# Memory: compiled Tungsten has no GC, so every gate frees its scratch arrays and
# `release` frees the limb arrays of a Packed scheme (see bits.w).
#
# Wide-argument note: nothing here relies on a 64-bit limb being sign-safe. Bit
# tests use `& 1` after an arithmetic shift and bit lists are read through
# 32-bit halves, so the results are engine-independent.

use core/bit_ops
use bits

# The first way a scheme fails to be exact. kind is :range (term/axis name a
# factor that is zero or wider than its matrix) or :coefficient (a, b name the
# first wrong entry of the tensor; expected and actual are its w masks).
+ Metaflip:Gf2:Defect
  ro :kind, :term, :axis, :a, :b, :expected, :actual

  -> new(@kind, @term = -1, @axis = -1, @a = -1, @b = -1, @expected = 0, @actual = 0)

  -> message
    if @kind == :range
      return "zero or out-of-bounds factor at term [@term]"
    "inexact GF(2) tensor at coefficients [@a],[@b]"

  -> to_s
    message

+ Metaflip:Gf2:Packed
  ro :n, :m, :p, :rank, :wu, :wv, :ww, :ulimbs, :vlimbs, :wlimbs

  # Table budget of the dense gate, in limbs (32 MiB): larger tables are filled
  # in bands of rows. Tunable, not part of the contract; on the 28x32x32,
  # rank-14,271 tensor a 32 MiB budget (4 bands) runs 15% faster than 8 MiB and
  # as fast as the unbanded 103 MiB table.
  -> .band_words
    4194304

  # An empty (all-zero, hence invalid until filled) scheme of `rank` terms.
  -> new(@n, @m, @p, @rank)
    @wu = Metaflip:Gf2:Bits.limbs_for(@n * @m)
    @wv = Metaflip:Gf2:Bits.limbs_for(@m * @p)
    @ww = Metaflip:Gf2:Bits.limbs_for(@n * @p)
    @ulimbs = i64[@rank * @wu]
    @vlimbs = i64[@rank * @wv]
    @wlimbs = i64[@rank * @ww]

  # Packs parallel Arrays of Integer masks. Raises for a mask that is negative or
  # needs more limbs than its matrix; a zero or too-wide-but-fitting mask is
  # stored as is and reported by `range_defect`.
  -> .from_masks(n, m, p, us, vs, ws)
    packed = Metaflip:Gf2:Packed.new(n, m, p, us.size)
    us.each_with_index -> (u, t)
      Metaflip:Gf2:Bits.to_limbs(u, packed.ulimbs, t * packed.wu, packed.wu)
    vs.each_with_index -> (v, t)
      Metaflip:Gf2:Bits.to_limbs(v, packed.vlimbs, t * packed.wv, packed.wv)
    ws.each_with_index -> (w, t)
      Metaflip:Gf2:Bits.to_limbs(w, packed.wlimbs, t * packed.ww, packed.ww)
    packed

  # Frees the limb arrays; the scheme is unusable afterwards.
  -> release
    Metaflip:Gf2:Bits.release(@ulimbs)
    Metaflip:Gf2:Bits.release(@vlimbs)
    Metaflip:Gf2:Bits.release(@wlimbs)
    nil

  # The three Integer-mask Arrays [us, vs, ws].
  -> masks
    us = (0...@rank).map -> (t) Metaflip:Gf2:Bits.from_limbs(@ulimbs, t * @wu, @wu)
    vs = (0...@rank).map -> (t) Metaflip:Gf2:Bits.from_limbs(@vlimbs, t * @wv, @wv)
    ws = (0...@rank).map -> (t) Metaflip:Gf2:Bits.from_limbs(@wlimbs, t * @ww, @ww)
    [us, vs, ws]

  # ---- typed kernels (class methods so they carry no global name) ---------

  # Set-bit indices of the mask limbs[base, base + words) into out, ascending;
  # returns how many. `out` must hold at least words * 64 entries.
  -> .bit_list(limbs, base, words, out) (i64[] i64 i64 i64[]) i64
    count = 0 ## i64
    q = 0 ## i64
    while q < words
      limb = limbs[base + q] ## i64
      half = limb & 4294967295 ## i64
      while half != 0
        out[count] = 64 * q + BitOps.trailing_zeros_u64(half)
        half = half & (half - 1)
        count += 1
      half = (limb >> 32) & 4294967295
      while half != 0
        out[count] = 64 * q + 32 + BitOps.trailing_zeros_u64(half)
        half = half & (half - 1)
        count += 1
      q += 1
    count

  # Total set bits of limbs[0, count).
  -> .popcount_limbs(limbs, count) (i64[] i64) i64
    total = 0 ## i64
    i = 0 ## i64
    while i < count
      total += BitOps.count_ones_u64(limbs[i])
      i += 1
    total

  # 1 when the mask limbs[base, base + words) is nonzero and below 2^width.
  -> .factor_ok(limbs, base, words, width) (i64[] i64 i64 i64) i64
    nonzero = 0 ## i64
    q = 0 ## i64
    while q < words
      if limbs[base + q] != 0
        nonzero = 1
      q += 1
    if nonzero == 0
      return 0
    top_bits = width - 64 * (words - 1) ## i64
    if top_bits < 64 && (limbs[base + words - 1] >> top_bits) != 0
      return 0
    1

  # Scans every factor; out[0] = 1 and out[1], out[2] = term, axis for the first
  # bad one, else out[0] = 0.
  -> .range_scan(ulimbs, vlimbs, wlimbs, dims, out) (i64[] i64[] i64[] i64[] i64[]) i64
    n = dims[0] ## i64
    m = dims[1] ## i64
    p = dims[2] ## i64
    rank = dims[3] ## i64
    wu = dims[4] ## i64
    wv = dims[5] ## i64
    ww = dims[6] ## i64
    out[0] = 0
    t = 0 ## i64
    while t < rank
      if Metaflip:Gf2:Packed.factor_ok(ulimbs, t * wu, wu, n * m) == 0
        out[0] = 1
        out[1] = t
        out[2] = 0
        return 1
      if Metaflip:Gf2:Packed.factor_ok(vlimbs, t * wv, wv, m * p) == 0
        out[0] = 1
        out[1] = t
        out[2] = 1
        return 1
      if Metaflip:Gf2:Packed.factor_ok(wlimbs, t * ww, ww, n * p) == 0
        out[0] = 1
        out[1] = t
        out[2] = 2
        return 1
      t += 1
    0

  # The dense gate. table holds band_rows * m*p*ww limbs and want m*p*ww, both
  # zeroed on entry (want is left zeroed). dims = [n, m, p, rank, wu, wv, ww,
  # band_rows]. out[0] = 1 and out[1], out[2] = a, b for the first wrong entry.
  -> .dense_scan(ulimbs, vlimbs, wlimbs, dims, table, want, out) (i64[] i64[] i64[] i64[] i64[] i64[] i64[]) i64
    n = dims[0] ## i64
    m = dims[1] ## i64
    p = dims[2] ## i64
    rank = dims[3] ## i64
    wu = dims[4] ## i64
    wv = dims[5] ## i64
    ww = dims[6] ## i64
    band_rows = dims[7] ## i64
    nm = n * m ## i64
    mp = m * p ## i64
    row_words = mp * ww ## i64
    ubits = i64[64 * wu]
    vbits = i64[64 * wv]
    out[0] = 0
    a0 = 0 ## i64
    while a0 < nm
      a1 = a0 + band_rows ## i64
      if a1 > nm
        a1 = nm
      cells = (a1 - a0) * row_words ## i64
      x = 0 ## i64
      while x < cells
        table[x] = 0
        x += 1
      # T[a][b] ^= w for every set bit a of u (within the band) and b of v.
      t = 0 ## i64
      while t < rank
        nu = Metaflip:Gf2:Packed.bit_list(ulimbs, t * wu, wu, ubits) ## i64
        nv = Metaflip:Gf2:Packed.bit_list(vlimbs, t * wv, wv, vbits) ## i64
        wbase = t * ww ## i64
        i = 0 ## i64
        while i < nu
          a = ubits[i] ## i64
          if a >= a0 && a < a1
            rbase = (a - a0) * row_words ## i64
            j = 0 ## i64
            while j < nv
              cell = rbase + vbits[j] * ww ## i64
              q = 0 ## i64
              while q < ww
                table[cell + q] = table[cell + q] ^ wlimbs[wbase + q]
                q += 1
              j += 1
          i += 1
        t += 1
      # Compare every entry of the band with the expected tensor: row a = i*m+j
      # is nonzero exactly at b = j*p+k, where it is the single bit i*p+k.
      a = a0 ## i64
      while a < a1
        row_i = a / m ## i64
        row_j = a % m ## i64
        k = 0 ## i64
        while k < p
          bit = row_i * p + k ## i64
          x = (row_j * p + k) * ww + (bit >> 6)
          want[x] = want[x] | Metaflip:Gf2:Bits.bit_mask(bit)
          k += 1
        base = (a - a0) * row_words ## i64
        first = -1 ## i64
        x = 0
        while x < row_words
          if table[base + x] != want[x]
            first = x
            break
          x += 1
        k = 0
        while k < p
          bit = row_i * p + k
          want[(row_j * p + k) * ww + (bit >> 6)] = 0
          k += 1
        if first >= 0
          out[0] = 1
          out[1] = a
          out[2] = first / ww
          Metaflip:Gf2:Bits.release(ubits)
          Metaflip:Gf2:Bits.release(vbits)
          return 1
        a += 1
      a0 = a1
    Metaflip:Gf2:Bits.release(ubits)
    Metaflip:Gf2:Bits.release(vbits)
    0

  # Number of (a, b) pairs the terms touch: sum of popcount(u) * popcount(v).
  -> .pair_count(ulimbs, vlimbs, dims) (i64[] i64[] i64[]) i64
    rank = dims[3] ## i64
    wu = dims[4] ## i64
    wv = dims[5] ## i64
    total = 0 ## i64
    t = 0 ## i64
    while t < rank
      nu = 0 ## i64
      q = 0 ## i64
      while q < wu
        nu += BitOps.count_ones_u64(ulimbs[t * wu + q])
        q += 1
      nv = 0 ## i64
      q = 0
      while q < wv
        nv += BitOps.count_ones_u64(vlimbs[t * wv + q])
        q += 1
      total += nu * nv
      t += 1
    total

  # Slot of `key` in the open-addressing table ht (entries [key + 1, slot];
  # 0 marks an empty entry), inserting it as slot counter[0] when new.
  -> .slot_for(ht, key, mask, shift, counter) (i64[] i64 i64 i64 i64[]) i64
    stored = key + 1 ## i64
    mixed = stored * -7046029254386353131 ## i64
    h = (mixed >> shift) & mask ## i64
    while true
      seen = ht[2 * h] ## i64
      if seen == stored
        return ht[2 * h + 1]
      if seen == 0
        slot = counter[0] ## i64
        ht[2 * h] = stored
        ht[2 * h + 1] = slot
        counter[0] = slot + 1
        return slot
      h = (h + 1) & mask
    0

  # The sparse gate. ht holds 2 * cap entries (cap a power of two), pool one
  # ww-limb row per possible slot; both zeroed on entry. dims = [n, m, p, rank,
  # wu, wv, ww, cap, 64 - log2(cap)]. out[0] = 1 and out[1], out[2] = a, b for
  # the wrong entry with the smallest (a, b).
  -> .sparse_scan(ulimbs, vlimbs, wlimbs, dims, ht, pool, out) (i64[] i64[] i64[] i64[] i64[] i64[] i64[]) i64
    n = dims[0] ## i64
    m = dims[1] ## i64
    p = dims[2] ## i64
    rank = dims[3] ## i64
    wu = dims[4] ## i64
    wv = dims[5] ## i64
    ww = dims[6] ## i64
    cap = dims[7] ## i64
    shift = dims[8] ## i64
    mask = cap - 1 ## i64
    mp = m * p ## i64
    counter = i64[1]
    ubits = i64[64 * wu]
    vbits = i64[64 * wv]
    t = 0 ## i64
    while t < rank
      nu = Metaflip:Gf2:Packed.bit_list(ulimbs, t * wu, wu, ubits) ## i64
      nv = Metaflip:Gf2:Packed.bit_list(vlimbs, t * wv, wv, vbits) ## i64
      wbase = t * ww ## i64
      i = 0 ## i64
      while i < nu
        j = 0 ## i64
        while j < nv
          slot = Metaflip:Gf2:Packed.slot_for(ht, ubits[i] * mp + vbits[j], mask, shift, counter) ## i64
          pbase = slot * ww ## i64
          q = 0 ## i64
          while q < ww
            pool[pbase + q] = pool[pbase + q] ^ wlimbs[wbase + q]
            q += 1
          j += 1
        i += 1
      t += 1
    # Add the target tensor: entry (i*m+j, j*p+k) gets bit i*p+k.
    ti = 0 ## i64
    while ti < n
      tj = 0 ## i64
      while tj < m
        tk = 0 ## i64
        while tk < p
          slot = Metaflip:Gf2:Packed.slot_for(ht, (ti * m + tj) * mp + tj * p + tk, mask, shift, counter) ## i64
          bit = ti * p + tk ## i64
          x = slot * ww + (bit >> 6) ## i64
          pool[x] = pool[x] ^ Metaflip:Gf2:Bits.bit_mask(bit)
          tk += 1
        tj += 1
      ti += 1
    # Every stored entry must now be zero; report the smallest nonzero key.
    best = -1 ## i64
    h = 0 ## i64
    while h < cap
      seen = ht[2 * h] ## i64
      if seen != 0
        pbase = ht[2 * h + 1] * ww ## i64
        nonzero = 0 ## i64
        q = 0 ## i64
        while q < ww
          if pool[pbase + q] != 0
            nonzero = 1
          q += 1
        if nonzero != 0 && (best < 0 || seen - 1 < best)
          best = seen - 1
      h += 1
    out[0] = 0
    if best >= 0
      out[0] = 1
      out[1] = best / mp
      out[2] = best % mp
    Metaflip:Gf2:Bits.release(counter)
    Metaflip:Gf2:Bits.release(ubits)
    Metaflip:Gf2:Bits.release(vbits)
    out[0]

  # XOR of the w limbs of every term whose u has bit a and v has bit b, into row.
  -> .cell_row(ulimbs, vlimbs, wlimbs, dims, a, b, row) (i64[] i64[] i64[] i64[] i64 i64 i64[]) i64
    rank = dims[3] ## i64
    wu = dims[4] ## i64
    wv = dims[5] ## i64
    ww = dims[6] ## i64
    hits = 0 ## i64
    t = 0 ## i64
    while t < rank
      if ((ulimbs[t * wu + (a >> 6)] >> (a & 63)) & 1) != 0 && ((vlimbs[t * wv + (b >> 6)] >> (b & 63)) & 1) != 0
        q = 0 ## i64
        while q < ww
          row[q] = row[q] ^ wlimbs[t * ww + q]
          q += 1
        hits += 1
      t += 1
    hits

  # ---- queries -----------------------------------------------------------------

  -> dims
    d = i64[9]
    d[0] = @n
    d[1] = @m
    d[2] = @p
    d[3] = @rank
    d[4] = @wu
    d[5] = @wv
    d[6] = @ww
    d

  # Total number of set bits over all factors (the scheme's density).
  -> density
    total = Metaflip:Gf2:Packed.popcount_limbs(@ulimbs, @rank * @wu)
    total += Metaflip:Gf2:Packed.popcount_limbs(@vlimbs, @rank * @wv)
    total += Metaflip:Gf2:Packed.popcount_limbs(@wlimbs, @rank * @ww)
    total

  # A :range Defect for the first zero or too-wide factor, or nil.
  -> range_defect
    out = i64[3]
    d = dims
    Metaflip:Gf2:Packed.range_scan(@ulimbs, @vlimbs, @wlimbs, d, out)
    found = out[0]
    term = out[1]
    axis = out[2]
    Metaflip:Gf2:Bits.release(out)
    Metaflip:Gf2:Bits.release(d)
    return nil if found == 0
    Metaflip:Gf2:Defect.new(:range, term, axis)

  # The :coefficient Defect for entry (a, b), recomputed from the terms alone
  # (independently of whichever gate reported it). Raises if that entry is in
  # fact correct, which would mean the gate lied.
  -> coefficient_defect(a, b)
    row = i64[@ww]
    d = dims
    Metaflip:Gf2:Packed.cell_row(@ulimbs, @vlimbs, @wlimbs, d, a, b, row)
    actual = Metaflip:Gf2:Bits.from_limbs(row, 0, @ww)
    Metaflip:Gf2:Bits.release(row)
    Metaflip:Gf2:Bits.release(d)
    expected = 0
    expected = 1 << ((a / @m) * @p + b % @p) if a % @m == b / @p
    raise "internal error: entry [a],[b] reported wrong but reconstructs correctly" if actual == expected
    Metaflip:Gf2:Defect.new(:coefficient, -1, -1, a, b, expected, actual)

  # ---- gates -------------------------------------------------------------------

  # Dense gate alone: nil or the :coefficient Defect (ranges are not checked).
  # `budget` is the table size in limbs above which the rows are filled band by
  # band (default Packed.band_words); it never changes the verdict.
  -> defect_dense(budget = nil)
    budget = Metaflip:Gf2:Packed.band_words if budget == nil
    row_words = @m * @p * @ww
    raise "dense gate needs too much memory for this shape; use the sparse gate" if row_words > 268435456
    band_rows = budget / row_words
    band_rows = 1 if band_rows < 1
    band_rows = @n * @m if band_rows > @n * @m
    d = dims
    d[7] = band_rows
    table = i64[band_rows * row_words]
    want = i64[row_words]
    out = i64[3]
    Metaflip:Gf2:Packed.dense_scan(@ulimbs, @vlimbs, @wlimbs, d, table, want, out)
    found = out[0]
    a = out[1]
    b = out[2]
    Metaflip:Gf2:Bits.release(table)
    Metaflip:Gf2:Bits.release(want)
    Metaflip:Gf2:Bits.release(out)
    Metaflip:Gf2:Bits.release(d)
    return nil if found == 0
    coefficient_defect(a, b)

  # Sparse gate alone: nil or the :coefficient Defect (ranges are not checked).
  -> defect_sparse
    d = dims
    bound = Metaflip:Gf2:Packed.pair_count(@ulimbs, @vlimbs, d) + @n * @m * @p
    bound = @n * @m * @m * @p if bound > @n * @m * @m * @p
    raise "sparse gate needs too much memory for this scheme; use the dense gate" if bound * @ww > 268435456
    cap = 64
    log2 = 6
    while cap < 2 * bound
      cap = cap * 2
      log2 += 1
    d[7] = cap
    d[8] = 64 - log2
    ht = i64[2 * cap]
    pool = i64[bound * @ww]
    out = i64[3]
    Metaflip:Gf2:Packed.sparse_scan(@ulimbs, @vlimbs, @wlimbs, d, ht, pool, out)
    found = out[0]
    a = out[1]
    b = out[2]
    Metaflip:Gf2:Bits.release(ht)
    Metaflip:Gf2:Bits.release(pool)
    Metaflip:Gf2:Bits.release(out)
    Metaflip:Gf2:Bits.release(d)
    return nil if found == 0
    coefficient_defect(a, b)

  # nil when the scheme is exact, else its first Defect. gate is :dense,
  # :sparse or :both. Range violations come first, as in the reference gates;
  # with :both the dense and sparse verdicts must be identical.
  -> defect(gate = :both)
    bad = range_defect
    return bad if bad != nil
    if gate == :dense
      return defect_dense
    if gate == :sparse
      return defect_sparse
    raise "unknown gate [gate]; expected :dense, :sparse or :both" if gate != :both
    first = defect_dense
    second = defect_sparse
    agree = (first == nil) == (second == nil)
    agree = first.a == second.a && first.b == second.b if agree && first != nil
    if !agree
      left = "exact"
      left = first.message if first != nil
      right = "exact"
      right = second.message if second != nil
      raise "gate disagreement: dense says [left], sparse says [right]"
    first
