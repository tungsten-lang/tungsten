# Bitcoin proof-of-work search.
#
# What can actually be reused across nonces
# =========================================
#
# SHA-256 is a Merkle-Damgard construction: the message is cut into 512-bit
# blocks and folded one at a time into a 256-bit chaining state. Block i's
# output is block i+1's input, and nothing else from block i survives. So
# *any* prefix that fills whole blocks can be hashed once and reused for
# every message sharing that prefix.
#
# The block header is 80 bytes, which SHA-256 pads to 128 — exactly two
# blocks:
#
#   block 1  bytes  0..63   version | prev_hash | merkle_root[0..27]
#   block 2  bytes 64..79   merkle_root[28..31] | time | bits | NONCE
#            + padding      0x80, zeros, length=640
#
# The nonce lands in block 2. Block 1 is therefore constant for an entire
# 2**32-nonce search, and the chaining state after it — the "midstate" — is
# computed once. This is not a trick, it is the structure of the hash, and
# it is why the old getwork protocol shipped a midstate field.
#
# Naive cost per nonce is three compressions: two for the 80-byte first
# hash, one for the 32-byte second. With the midstate it is two. That is a
# 33% reduction and it is the single largest legitimate saving available.
#
# Three smaller reuses, all implemented here:
#
#   * Rounds 0..2 of block 2 consume w[0], w[1], w[2] — merkle tail, time
#     and bits. None is the nonce, so the working variables after round 2
#     are also fixed per work item. The per-nonce compression resumes at
#     round 3. (~3 of 128 rounds)
#
#   * Message-schedule words w[16] and w[17] depend on w[0..2] and w[9..15]
#     but not on w[3], so they are precomputed too. Expansion starts at
#     w[18]. (~2 of 48 expansion steps)
#
#   * The final chaining word H7 is determined by the state after round 60,
#     so the last three rounds of the *second* hash are skipped on the
#     reject path — and since a candidate must have zero high bits, H7
#     alone rejects essentially every nonce. The full digest is only
#     assembled for a survivor. (~3 of 64 rounds, plus the final adds)
#
# What cannot be reused
# =====================
#
# There is no way to compute H(nonce+1) from H(nonce) more cheaply than
# recomputing it, and no way to solve the partial hash for a nonce
# increment that hits a target. Both would be breaks of SHA-256 itself, not
# engineering wins. The nonce enters at w[3], and by round ~8 its influence
# has spread through every working variable via the rotations in the sigma
# functions and the carries of modular addition. Rounds 3..63 of block 2
# and all 64 rounds of the second hash have to be run per candidate.
#
# See the README for the full argument, including where the published
# cryptanalysis actually stands and what AsicBoost does differently.

use bitcoin

# ---- job preparation ------------------------------------------------------

# Everything the inner loop needs, derived once from an 80-byte header.
#
# Layout of the returned i64[]:
#   [0..7]    midstate — chaining state after header block 1
#   [8..15]   working variables after rounds 0..2 of block 2
#   [16..18]  block-2 schedule words w[0], w[1], w[2]
#   [19..20]  precomputed schedule words w[16], w[17]
#
# `header` is the 80 bytes from btc_header_bytes; the nonce field in it is
# ignored, since the search supplies its own.
-> miner_prepare(header, k)
  job = i64[24]
  w = i64[64]
  # --- block 1: bytes 0..63, hashed once ---
  st = sha256_iv()
  j = 0 ## i64
  while j < 16
    off = j * 4
    w[j] = (header[off] << 24) | (header[off + 1] << 16) | (header[off + 2] << 8) | header[off + 3]
    j += 1
  sha256_block(st, w, k)
  j = 0
  while j < 8
    job[j] = st[j]
    j += 1
  # --- block 2 constants ---
  # w[0] is the merkle-root tail, w[1] time, w[2] bits; w[3] is the nonce
  # and is filled per candidate. Then SHA-256 padding for a 640-bit message.
  j = 0
  while j < 3
    off = 64 + j * 4
    job[16 + j] = (header[off] << 24) | (header[off + 1] << 16) | (header[off + 2] << 8) | header[off + 3]
    j += 1
  w[0] = job[16]
  w[1] = job[17]
  w[2] = job[18]
  w[3] = 0
  w[4] = 0x80000000
  j = 5
  while j < 15
    w[j] = 0
    j += 1
  w[15] = 640
  # w[16] and w[17] never see w[3]:
  #   w[16] = s1(w[14]) + w[9]  + s0(w[1]) + w[0]
  #   w[17] = s1(w[15]) + w[10] + s0(w[2]) + w[1]
  job[19] = (sha256_ssig1(w[14]) + w[9] + sha256_ssig0(w[1]) + w[0]) & 0xFFFFFFFF
  job[20] = (sha256_ssig1(w[15]) + w[10] + sha256_ssig0(w[2]) + w[1]) & 0xFFFFFFFF
  # --- rounds 0..2 of block 2, which never touch w[3] ---
  work = i64[8]
  sha256_rounds_into(work, st, w, k, 0, 3)
  j = 0
  while j < 8
    job[8 + j] = work[j]
    j += 1
  job

# ---- the inner loop -------------------------------------------------------

# Search nonces [start, start+count) for one whose double-SHA meets
# `target`. Returns the winning nonce, or -1.
#
# The two hashes per candidate are unavoidable; everything the structure of
# SHA-256 permits to be lifted out has been lifted out by miner_prepare.
-> miner_search(job, target, start, count, k) (i64[] i64[] i64 i64 i64[]) i64
  w1 = i64[64]
  w2 = i64[64]
  st1 = i64[8]
  st2 = i64[8]
  work = i64[8]
  d2 = i64[8]
  # Block-2 schedule: constant words, padding, and the two precomputed
  # expansion words. Only w1[3] moves inside the loop.
  w1[0] = job[16]
  w1[1] = job[17]
  w1[2] = job[18]
  w1[4] = 0x80000000
  j = 5 ## i64
  while j < 15
    w1[j] = 0
    j += 1
  w1[15] = 640
  w1[16] = job[19]
  w1[17] = job[20]
  # Second-hash schedule: the 32-byte digest plus its padding. Words 0..7
  # change per candidate; 8..15 are fixed.
  w2[8] = 0x80000000
  j = 9
  while j < 15
    w2[j] = 0
    j += 1
  w2[15] = 256
  # The high 32 bits of the target. A candidate must not exceed it, and
  # comparing this one word rejects all but a vanishing fraction.
  top = target[0] ## i64
  iv7 = 0x5be0cd19 ## i64
  nonce = start ## i64
  last = start + count ## i64
  while nonce < last
    # --- first hash, block 2, resumed from the midstate ---
    # The header stores the nonce little-endian, so the big-endian word
    # SHA-256 consumes is its byte-swap.
    w1[3] = btc_bswap32(nonce)
    j = 18
    while j < 64
      s0 = sha256_ssig0(w1[j - 15])
      s1 = sha256_ssig1(w1[j - 2])
      w1[j] = (w1[j - 16] + s0 + w1[j - 7] + s1) & 0xFFFFFFFF
      j += 1
    j = 0
    while j < 8
      st1[j] = job[j]
      work[j] = job[8 + j]
      j += 1
    sha256_compress_resume(st1, work, w1, k, 3)
    # --- second hash of the 32-byte digest ---
    j = 0
    while j < 8
      w2[j] = st1[j]
      j += 1
    sha256_expand(w2)
    j = 0
    while j < 8
      st2[j] = sha256_iv_word(j)
      j += 1
    # Reject on H7 alone: it is the top of the value once byte-swapped,
    # and it is available three rounds early.
    h7 = sha256_h7_only(st2, w2, k, 0, iv7)
    if btc_bswap32(h7) <= top
      # Rare. Finish the digest properly and do the full 256-bit compare.
      sha256_compress(st2, w2, k)
      j = 0
      while j < 8
        d2[j] = st2[j]
        j += 1
      if btc_meets_target(d2, target) == 1
        return nonce
      j = 0
      while j < 8
        st2[j] = sha256_iv_word(j)
        j += 1
    nonce += 1
  -1

# Single IV word, so the inner loop can refill a state without allocating.
-> sha256_iv_word(i) (i64) i64
  if i == 0
    return 0x6a09e667
  if i == 1
    return 0xbb67ae85
  if i == 2
    return 0x3c6ef372
  if i == 3
    return 0xa54ff53a
  if i == 4
    return 0x510e527f
  if i == 5
    return 0x9b05688c
  if i == 6
    return 0x1f83d9ab
  0x5be0cd19

# Full double-SHA digest for one nonce, taken through the same midstate
# path the search uses. The search itself never materializes a digest on
# the reject path, so this is how a caller inspects a winner — and how the
# specs prove the optimized path agrees with a plain hash of the header.
-> miner_hash_nonce(job, nonce, k)
  w1 = i64[64]
  st1 = i64[8]
  work = i64[8]
  w1[0] = job[16]
  w1[1] = job[17]
  w1[2] = job[18]
  w1[3] = btc_bswap32(nonce)
  w1[4] = 0x80000000
  j = 5 ## i64
  while j < 15
    w1[j] = 0
    j += 1
  w1[15] = 640
  sha256_expand(w1)
  j = 0
  while j < 8
    st1[j] = job[j]
    work[j] = job[8 + j]
    j += 1
  sha256_compress_resume(st1, work, w1, k, 3)
  sha256d_second(st1, k)

# ---- naive reference ------------------------------------------------------

# The same search with no reuse at all: re-serialize the header and hash all
# 80 bytes from the IV every time, three compressions per candidate. Kept
# because it is the honest baseline for the benchmark, and because it
# independently confirms the optimized loop finds the same nonces.
-> miner_search_naive(header, target, start, count, k) (i64[] i64[] i64 i64 i64[]) i64
  nonce = start ## i64
  last = start + count ## i64
  while nonce < last
    btc_put_u32_le(header, 76, nonce)
    d = sha256d_bytes(header, 80, k)
    if btc_meets_target(d, target) == 1
      return nonce
    nonce += 1
  -1

# ---- convenience ----------------------------------------------------------

# Mine a header, scanning the whole 32-bit nonce range in chunks so a caller
# can report progress. Returns the nonce or -1.
-> miner_mine_header(header, bits, start, k)
  target = btc_target_from_bits(bits)
  if target == nil
    return -1
  job = miner_prepare(header, k)
  miner_search(job, target, start, 4294967296 - start, k)
