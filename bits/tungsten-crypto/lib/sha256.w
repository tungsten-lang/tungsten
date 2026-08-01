# SHA-256 (FIPS 180-4) for Tungsten.
#
# Word-oriented by design. Every routine here works on `i64[]` arrays whose
# elements hold one 32-bit word in the low bits, because the miner in
# miner.w needs to reach *inside* the hash: it saves the chaining state
# after the first message block and resumes from it for every nonce. A
# byte-string-only API could not express that.
#
# 32-bit arithmetic on 64-bit lanes
# --------------------------------
# Words are kept canonical (0 <= w < 2**32) after every operation. Sums are
# masked with 0xFFFFFFFF; rotations are built so no intermediate ever
# exceeds 2**32:
#
#   rotr32(x, n) = (x >> n) | ((x & ((1 << n) - 1)) << (32 - n))
#
# The naive `(x << (32 - n)) & 0xFFFFFFFF` spelling would transiently reach
# 2**63 and sits right on the edge of the tagged-integer range, so it is
# avoided even though it looks tidier.
#
# Do not write a type ascription mid-expression (`1 ## i64 << n`): the
# lexer takes `## ...` to end-of-line, so the shift is silently swallowed
# and you get `1`. Ascribe on its own statement instead.

# ---- constants ------------------------------------------------------------

# First 32 bits of the fractional parts of the cube roots of the first 64
# primes. Returned as a fresh i64[64]; callers hoist this out of hot loops
# and pass it down rather than rebuilding it per hash.
-> sha256_k
  k = i64[64]
  k[0]  = 0x428a2f98
  k[1]  = 0x71374491
  k[2]  = 0xb5c0fbcf
  k[3]  = 0xe9b5dba5
  k[4]  = 0x3956c25b
  k[5]  = 0x59f111f1
  k[6]  = 0x923f82a4
  k[7]  = 0xab1c5ed5
  k[8]  = 0xd807aa98
  k[9]  = 0x12835b01
  k[10] = 0x243185be
  k[11] = 0x550c7dc3
  k[12] = 0x72be5d74
  k[13] = 0x80deb1fe
  k[14] = 0x9bdc06a7
  k[15] = 0xc19bf174
  k[16] = 0xe49b69c1
  k[17] = 0xefbe4786
  k[18] = 0x0fc19dc6
  k[19] = 0x240ca1cc
  k[20] = 0x2de92c6f
  k[21] = 0x4a7484aa
  k[22] = 0x5cb0a9dc
  k[23] = 0x76f988da
  k[24] = 0x983e5152
  k[25] = 0xa831c66d
  k[26] = 0xb00327c8
  k[27] = 0xbf597fc7
  k[28] = 0xc6e00bf3
  k[29] = 0xd5a79147
  k[30] = 0x06ca6351
  k[31] = 0x14292967
  k[32] = 0x27b70a85
  k[33] = 0x2e1b2138
  k[34] = 0x4d2c6dfc
  k[35] = 0x53380d13
  k[36] = 0x650a7354
  k[37] = 0x766a0abb
  k[38] = 0x81c2c92e
  k[39] = 0x92722c85
  k[40] = 0xa2bfe8a1
  k[41] = 0xa81a664b
  k[42] = 0xc24b8b70
  k[43] = 0xc76c51a3
  k[44] = 0xd192e819
  k[45] = 0xd6990624
  k[46] = 0xf40e3585
  k[47] = 0x106aa070
  k[48] = 0x19a4c116
  k[49] = 0x1e376c08
  k[50] = 0x2748774c
  k[51] = 0x34b0bcb5
  k[52] = 0x391c0cb3
  k[53] = 0x4ed8aa4a
  k[54] = 0x5b9cca4f
  k[55] = 0x682e6ff3
  k[56] = 0x748f82ee
  k[57] = 0x78a5636f
  k[58] = 0x84c87814
  k[59] = 0x8cc70208
  k[60] = 0x90befffa
  k[61] = 0xa4506ceb
  k[62] = 0xbef9a3f7
  k[63] = 0xc67178f2
  k

# First 32 bits of the fractional parts of the square roots of the first 8
# primes — the IV every SHA-256 starts from.
-> sha256_iv
  h = i64[8]
  h[0] = 0x6a09e667
  h[1] = 0xbb67ae85
  h[2] = 0x3c6ef372
  h[3] = 0xa54ff53a
  h[4] = 0x510e527f
  h[5] = 0x9b05688c
  h[6] = 0x1f83d9ab
  h[7] = 0x5be0cd19
  h

# ---- primitives -----------------------------------------------------------

-> rotr32(x, n) (i64 i64) i64
  low = x >> n
  keep = (1 << n) - 1
  low | ((x & keep) << (32 - n))

# Small sigma (message schedule) and big sigma (round function) mixers.
-> sha256_ssig0(x) (i64) i64
  rotr32(x, 7) ^ rotr32(x, 18) ^ (x >> 3)

-> sha256_ssig1(x) (i64) i64
  rotr32(x, 17) ^ rotr32(x, 19) ^ (x >> 10)

-> sha256_bsig0(x) (i64) i64
  rotr32(x, 2) ^ rotr32(x, 13) ^ rotr32(x, 22)

-> sha256_bsig1(x) (i64) i64
  rotr32(x, 6) ^ rotr32(x, 11) ^ rotr32(x, 25)

# ---- message schedule -----------------------------------------------------

# Expands w[0..15] (already set by the caller) into w[16..63] in place.
# `w` must have room for 64 words.
-> sha256_expand(w) (i64[]) i64
  i = 16 ## i64
  while i < 64
    s0 = sha256_ssig0(w[i - 15])
    s1 = sha256_ssig1(w[i - 2])
    w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xFFFFFFFF
    i += 1
  0

# ---- compression ----------------------------------------------------------

# The Merkle-Damgard step: fold one 512-bit block (the 64-word expanded
# schedule `w`) into the 8-word chaining state `st`, in place.
#
# This is THE reusable unit. `st` after a call is a "midstate": a complete
# summary of every byte hashed so far. Hand the same midstate to this
# function with different later blocks and the earlier blocks never get
# recomputed. The miner leans on exactly that.
-> sha256_compress(st, w, k) (i64[] i64[] i64[]) i64
  sha256_compress_resume(st, st, w, k, 0)

# Compression with an explicit entry point.
#
# `st` is the chaining state the round output is added into at the end;
# `work` supplies the eight working variables to start from; `start` is the
# first round to run. The plain call above passes `st` for both, which is
# exactly the standard function: working variables initialized from the
# chaining state, all 64 rounds. Aliasing is safe because `work` is fully
# read into locals before `st` is touched.
#
# The separation exists for the miner. Rounds 0..2 of a block consume only
# w[0..2]; if those words are fixed across a search (they are — for a block
# header's second SHA block they hold merkle tail, time and bits, while the
# nonce sits in w[3]), the state after round 2 can be computed once and
# resumed from for every candidate.
-> sha256_compress_resume(st, work, w, k, start) (i64[] i64[] i64[] i64[] i64) i64
  a = work[0] ## i64
  b = work[1] ## i64
  c = work[2] ## i64
  d = work[3] ## i64
  e = work[4] ## i64
  f = work[5] ## i64
  g = work[6] ## i64
  h = work[7] ## i64
  i = start ## i64
  while i < 64
    ch = (e & f) ^ ((e ^ 0xFFFFFFFF) & g)
    t1 = (h + sha256_bsig1(e) + ch + k[i] + w[i]) & 0xFFFFFFFF
    maj = (a & b) ^ (a & c) ^ (b & c)
    t2 = (sha256_bsig0(a) + maj) & 0xFFFFFFFF
    h = g
    g = f
    f = e
    e = (d + t1) & 0xFFFFFFFF
    d = c
    c = b
    b = a
    a = (t1 + t2) & 0xFFFFFFFF
    i += 1
  st[0] = (st[0] + a) & 0xFFFFFFFF
  st[1] = (st[1] + b) & 0xFFFFFFFF
  st[2] = (st[2] + c) & 0xFFFFFFFF
  st[3] = (st[3] + d) & 0xFFFFFFFF
  st[4] = (st[4] + e) & 0xFFFFFFFF
  st[5] = (st[5] + f) & 0xFFFFFFFF
  st[6] = (st[6] + g) & 0xFFFFFFFF
  st[7] = (st[7] + h) & 0xFFFFFFFF
  0

# Run rounds [start, stop) starting from `work`, leaving the eight working
# variables in `out`. No chaining-state addition happens — this is the raw
# round function, used to precompute a partial block.
-> sha256_rounds_into(out, work, w, k, start, stop) (i64[] i64[] i64[] i64[] i64 i64) i64
  a = work[0] ## i64
  b = work[1] ## i64
  c = work[2] ## i64
  d = work[3] ## i64
  e = work[4] ## i64
  f = work[5] ## i64
  g = work[6] ## i64
  h = work[7] ## i64
  i = start ## i64
  while i < stop
    ch = (e & f) ^ ((e ^ 0xFFFFFFFF) & g)
    t1 = (h + sha256_bsig1(e) + ch + k[i] + w[i]) & 0xFFFFFFFF
    maj = (a & b) ^ (a & c) ^ (b & c)
    t2 = (sha256_bsig0(a) + maj) & 0xFFFFFFFF
    h = g
    g = f
    f = e
    e = (d + t1) & 0xFFFFFFFF
    d = c
    c = b
    b = a
    a = (t1 + t2) & 0xFFFFFFFF
    i += 1
  out[0] = a
  out[1] = b
  out[2] = c
  out[3] = d
  out[4] = e
  out[5] = f
  out[6] = g
  out[7] = h
  0

# The last output word H7, computed without finishing the block.
#
# Rounds rotate the working variables, so the `h` that lands in H7 after
# round 63 is the `g` before round 63, the `f` before round 62, and the `e`
# before round 61 — that is, `e` as it stands once round 60 completes.
# Rounds 61..63 therefore cannot influence H7 and are skipped outright.
#
# For a miner this is the only word that matters on the overwhelming
# majority of candidates: a share or block requires the top of the value to
# be zero, and the top of the value is a byte-swap of H7. Callers use this
# to reject, then re-run the full hash on the rare survivor.
-> sha256_h7_only(work, w, k, start, chain7) (i64[] i64[] i64[] i64 i64) i64
  a = work[0] ## i64
  b = work[1] ## i64
  c = work[2] ## i64
  d = work[3] ## i64
  e = work[4] ## i64
  f = work[5] ## i64
  g = work[6] ## i64
  h = work[7] ## i64
  i = start ## i64
  while i < 61
    ch = (e & f) ^ ((e ^ 0xFFFFFFFF) & g)
    t1 = (h + sha256_bsig1(e) + ch + k[i] + w[i]) & 0xFFFFFFFF
    maj = (a & b) ^ (a & c) ^ (b & c)
    t2 = (sha256_bsig0(a) + maj) & 0xFFFFFFFF
    h = g
    g = f
    f = e
    e = (d + t1) & 0xFFFFFFFF
    d = c
    c = b
    b = a
    a = (t1 + t2) & 0xFFFFFFFF
    i += 1
  (chain7 + e) & 0xFFFFFFFF

# Convenience: expand then compress. `w` must hold 64 words with w[0..15]
# already loaded.
-> sha256_block(st, w, k) (i64[] i64[] i64[]) i64
  sha256_expand(w)
  sha256_compress(st, w, k)

# ---- byte-oriented API ----------------------------------------------------

# Hash `n` bytes taken from `bytes` (values 0..255, one per element).
# Returns a fresh 8-word i64[] digest, big-endian word order.
-> sha256_bytes(bytes, n, k) (i64[] i64 i64[]) i64[]
  st = sha256_iv()
  w = i64[64]
  # Total message length in bits, needed by the padding block.
  bitlen = n * 8 ## i64
  # Number of whole 64-byte blocks, and the tail left over.
  full = n / 64 ## i64
  blk = 0 ## i64
  while blk < full
    base = blk * 64
    j = 0 ## i64
    while j < 16
      off = base + j * 4
      w[j] = (bytes[off] << 24) | (bytes[off + 1] << 16) | (bytes[off + 2] << 8) | bytes[off + 3]
      j += 1
    sha256_block(st, w, k)
    blk += 1
  # Padding: 0x80, then zeros, then the 64-bit big-endian bit length. If the
  # tail plus the 0x80 plus the length field does not fit in one block, it
  # spills into a second all-padding block.
  rest = n - full * 64 ## i64
  tail = i64[128]
  t = 0 ## i64
  while t < rest
    tail[t] = bytes[full * 64 + t]
    t += 1
  tail[rest] = 0x80
  t = rest + 1
  pad_blocks = 1 ## i64
  if rest >= 56
    pad_blocks = 2
  padlen = pad_blocks * 64 ## i64
  while t < padlen
    tail[t] = 0
    t += 1
  # Bit length occupies the final 8 bytes. Bitcoin messages are far below
  # 2**32 bits, but write all 8 bytes so the routine stays general.
  bl = bitlen ## i64
  t = padlen - 1
  while t >= padlen - 8
    tail[t] = bl & 0xFF
    bl = bl >> 8
    t -= 1
  pb = 0 ## i64
  while pb < pad_blocks
    base = pb * 64
    j = 0 ## i64
    while j < 16
      off = base + j * 4
      w[j] = (tail[off] << 24) | (tail[off + 1] << 16) | (tail[off + 2] << 8) | tail[off + 3]
      j += 1
    sha256_block(st, w, k)
    pb += 1
  st

# SHA-256 of a Tungsten string's bytes. Returns the 8-word digest.
-> sha256_string_words(s, k)
  bs = s.bytes
  n = bs.size ## i64
  buf = i64[n + 1]
  i = 0 ## i64
  while i < n
    buf[i] = bs[i]
    i += 1
  sha256_bytes(buf, n, k)

# ---- double SHA-256 -------------------------------------------------------

# Bitcoin hashes everything twice: SHA256(SHA256(m)). Given an 8-word
# digest, run the second pass. The input is exactly 32 bytes, so the second
# block is one padded block that we build directly in word space — no byte
# array, no re-serialization.
-> sha256d_second(digest, k) (i64[] i64[]) i64[]
  st = sha256_iv()
  w = i64[64]
  j = 0 ## i64
  while j < 8
    w[j] = digest[j]
    j += 1
  w[8] = 0x80000000
  j = 9
  while j < 15
    w[j] = 0
    j += 1
  w[15] = 256
  sha256_block(st, w, k)
  st

# Double SHA-256 over `n` bytes of `bytes`.
-> sha256d_bytes(bytes, n, k) (i64[] i64 i64[]) i64[]
  sha256d_second(sha256_bytes(bytes, n, k), k)

# ---- formatting -----------------------------------------------------------

# Big-endian hex of an 8-word digest: the order SHA-256 itself defines.
-> sha256_hex(digest)
  out = ""
  i = 0 ## i64
  while i < 8
    word = digest[i] ## i64
    shift = 28 ## i64
    while shift >= 0
      out = out + "0123456789abcdef".slice((word >> shift) & 0xF, 1)
      shift -= 4
    i += 1
  out

# Byte-reversed hex, which is how Bitcoin displays block and transaction
# hashes. The protocol treats a hash as a little-endian 256-bit integer, so
# the human-readable form is the digest read backwards.
-> sha256_hex_le(digest)
  out = ""
  i = 7 ## i64
  while i >= 0
    word = digest[i] ## i64
    b = 0 ## i64
    while b < 4
      byte = (word >> (b * 8)) & 0xFF
      out = out + "0123456789abcdef".slice((byte >> 4) & 0xF, 1)
      out = out + "0123456789abcdef".slice(byte & 0xF, 1)
      b += 1
    i -= 1
  out

# ---- timing ---------------------------------------------------------------

# Monotonic milliseconds, usable from BOTH engines. `clock_ms` is not
# reachable as a bare call interpreted, and `ccall("__w_clock_ms")` is
# rejected by the interpreter outright; `clock()` (monotonic float seconds)
# is the one spelling both accept.
-> crypto_now_ms
  (clock() * 1000).to_i
