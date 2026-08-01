# Proof-of-work search as a Tungsten `@gpu fn`, at hand-written-kernel speed.
#
# lib/miner.w is the specification — it explains which parts of the double
# SHA-256 can be lifted out of the per-nonce loop and why. Nothing here
# changes that argument: the midstate reuse, the three precomputed rounds,
# the two precomputed schedule words and the H7-only reject are the same
# four reuses. Words 0..20 of the job buffer ARE `miner_prepare`'s output,
# copied across, so the CPU and GPU cannot disagree about the work.
#
# How this reaches hand-written-MSL speed
# =======================================
#
# An earlier `@gpu` version of this search ran at about a third of the speed
# of a hand-written MSL kernel. The gap was three things: `@gpu` could not
# ask for a full unroll or a constant table (both now expressible — see the
# emitter features below), and a loop-shape problem that needs no compiler
# support at all. Fixing all three brought this to parity with hand-written
# MSL, which is why this is now the only GPU kernel in the bit.
#
# Measured on an M5 Max (40 GPU cores), every candidate dispatched
# round-robin inside one process so they all see the same machine load —
# the only way to compare on a box whose load average swings 4x. Medians of
# 15, tg=128 per=64, load average ~14:
#
#   an un-unrolled @gpu kernel                               401 MH/s
#   this kernel                                             1040 MH/s
#   a hand-written MSL reference                            1108 MH/s
#
# Within a few percent of hand-written MSL; across configurations the two
# trade places, so call it parity. For
# scale, the 18-thread ARMv8 crypto-extension miner measures 348 MH/s on
# the same box at the same load.
#
# The four levers, in the order they matter
# =========================================
#
# 1. SPLIT LOOPS, NO BRANCH CHAIN. This is the big one and it is a source
#    property, not a compiler feature. SHA-256's rounds fall into two
#    shapes: rounds that only read the message schedule, and rounds that
#    expand it first. Written as one loop with `if i == 16 / elsif i == 17 /
#    elsif i > 17` inside, the body is large enough that the unroller gives
#    up, `m[]` stays in scratch memory, and the kernel runs at un-unrolled
#    speed. Written as two loops with no branch in either, it unrolls.
#    Splitting the hand-written kernel's loops the wrong way costs it 2.6x
#    (509 -> 197 MH/s), which is how this was found.
#
#    The branch chain is avoidable entirely: rounds 3..15 never read m[0] or
#    m[1], so the two precomputed schedule words w[16] and w[17] can be
#    stored before the loop starts instead of being spliced in mid-loop.
#
# 2. `## u32 unroll` on the induction variable — a new `@gpu` type-hint
#    flag. A thread-private array indexed by a loop variable can only live
#    in registers once every index is a compile-time constant. Worth 4.4x
#    on this kernel.
#
# 3. The round constants as an array literal, which the emitter lifts to a
#    program-scope `constant` table — also new. Read through a `device`
#    pointer they are 128 loads per nonce. Worth 1.3x, but only once the
#    loops unroll: rolled, the index is not a constant and there is nothing
#    to fold.
#
# 4. Not writing this kernel at all, but a fix in the emitter: it used to
#    declare 256 bytes of threadgroup scratch in EVERY kernel, for
#    reduction helpers this one never calls. Threadgroup memory bounds how
#    many threadgroups stay resident on a GPU core, so that was 1.55x
#    (795 -> 1236 MH/s) of pure occupancy loss. Every `@gpu fn` in the repo
#    that does no threadgroup reduction gets that back.
#
# The `u32` hints are load-bearing. SHA-256 is defined on unsigned 32-bit
# words: it needs logical right shift, wrapping addition, and unsigned
# comparison. `## i32` compiles and produces wrong answers.
#
# What the kernel does NOT do
# ===========================
#
# It never assembles a digest and never runs the full 256-bit compare. It
# computes H7 — which after byteswapping is the most significant word of the
# compared value — and reports every nonce whose H7 does not already lose.
# That is a necessary condition for a win, so no winner is missed, and it is
# met about once in 2^32 candidates at difficulty 1.
#
# The decision is then made on the CPU by `miner_hash_nonce` and
# `btc_meets_target`, the reference implementations. The GPU is a filter;
# the reference says what counts. A false positive costs one CPU hash and a
# false win is impossible.
#
# Job buffer layout (32 u32 words)
# ================================
#
#   [0..7]    midstate — chaining state after header block 1
#   [8..15]   working variables after rounds 0..2 of block 2
#   [16..18]  block-2 schedule words w[0], w[1], w[2]
#   [19..20]  precomputed schedule words w[16], w[17]
#   [21..28]  target, big-endian words; [21] is the most significant
#   [29]      base nonce
#   [30]      nonce count
#   [31]      nonces per thread
#
# Result buffer is `i32[18]`: slot 0 an atomic candidate counter, slots
# 1..15 the candidate nonces, slot 16 the sign-biased minimum value seen
# (for the display's best-so-far), slot 17 a nonce that produced it.

use bitcoin
use miner
use core/metal

# ---- kernels --------------------------------------------------------------

## u32[]: job
## i32[]: out
@gpu fn sha256d_mine(job, out)
  # First 32 bits of the fractional parts of the cube roots of the first 64
  # primes. An array literal in a kernel body becomes a program-scope
  # `constant` table — see gpu_declare_const_table in metal_emitter.w.
  kc = [0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2] ## u32[]
  gid = gpu.thread_position_in_grid.x ## u32
  base = job[29] ## u32
  count = job[30] ## u32
  per = job[31] ## u32
  top = job[21] ## u32
  idx = gid * per ## u32
  last = idx + per ## u32
  if last > count
    last = count
  m = u32[16]
  # Best-so-far, tracked per THREAD and reduced once at the end. v7 is the top
  # word of the value and is computed for the reject test anyway, so keeping a
  # running minimum over this thread's nonces is free; doing the atomic per
  # candidate would be one contended write per nonce.
  best_val = 0xFFFFFFFF ## u32
  best_nonce = 0 ## u32
  while idx < last
    nonce = base + idx ## u32
    # ---- first hash, block 2, resumed from the round-2 state ----
    # m[0] and m[1] hold w[16] and w[17], not w[0] and w[1]: rounds 0..2 are
    # precomputed and rounds 3..15 never read those two slots, so the
    # precomputed expansion words can be placed up front. That is what keeps
    # the round loop free of a branch chain.
    m[0] = job[19]
    m[1] = job[20]
    m[2] = job[18]
    # The header stores the nonce little-endian, so the big-endian word the
    # compression consumes is its byteswap.
    m[3] = ((nonce >> 24) & 255) | ((nonce >> 8) & 65280) | ((nonce & 65280) << 8) | (nonce << 24)
    m[4] = 0x80000000
    m[5] = 0
    m[6] = 0
    m[7] = 0
    m[8] = 0
    m[9] = 0
    m[10] = 0
    m[11] = 0
    m[12] = 0
    m[13] = 0
    m[14] = 0
    m[15] = 640
    a = job[8] ## u32
    b = job[9] ## u32
    c = job[10] ## u32
    d = job[11] ## u32
    e = job[12] ## u32
    f = job[13] ## u32
    g = job[14] ## u32
    h = job[15] ## u32
    # Rounds 3..17: schedule already in place, nothing to expand.
    i = 3 ## u32 unroll
    while i < 18
      t1 = h + (((e >> 6) | (e << 26)) ^ ((e >> 11) | (e << 21)) ^ ((e >> 25) | (e << 7))) + (g ^ (e & (f ^ g))) + kc[i] + m[i & 15] ## u32
      t2 = (((a >> 2) | (a << 30)) ^ ((a >> 13) | (a << 19)) ^ ((a >> 22) | (a << 10))) + ((a & b) ^ (c & (a ^ b))) ## u32
      h = g
      g = f
      f = e
      e = d + t1
      d = c
      c = b
      b = a
      a = t1 + t2
      i = i + 1
    # Rounds 18..63: expand one word, then round.
    i = 18
    while i < 64
      x = m[(i + 1) & 15] ## u32
      y = m[(i + 14) & 15] ## u32
      m[i & 15] = m[i & 15] + (((x >> 7) | (x << 25)) ^ ((x >> 18) | (x << 14)) ^ (x >> 3)) + m[(i + 9) & 15] + (((y >> 17) | (y << 15)) ^ ((y >> 19) | (y << 13)) ^ (y >> 10))
      t1 = h + (((e >> 6) | (e << 26)) ^ ((e >> 11) | (e << 21)) ^ ((e >> 25) | (e << 7))) + (g ^ (e & (f ^ g))) + kc[i] + m[i & 15]
      t2 = (((a >> 2) | (a << 30)) ^ ((a >> 13) | (a << 19)) ^ ((a >> 22) | (a << 10))) + ((a & b) ^ (c & (a ^ b)))
      h = g
      g = f
      f = e
      e = d + t1
      d = c
      c = b
      b = a
      a = t1 + t2
      i = i + 1
    # ---- second hash, of the 32-byte digest, stopped at round 61 ----
    # The round variables rotate, so the `h` feeding H7 after round 63 is
    # the `e` standing after round 60: rounds 61..63 cannot influence it.
    m[0] = job[0] + a
    m[1] = job[1] + b
    m[2] = job[2] + c
    m[3] = job[3] + d
    m[4] = job[4] + e
    m[5] = job[5] + f
    m[6] = job[6] + g
    m[7] = job[7] + h
    m[8] = 0x80000000
    m[9] = 0
    m[10] = 0
    m[11] = 0
    m[12] = 0
    m[13] = 0
    m[14] = 0
    m[15] = 256
    a = 0x6a09e667
    b = 0xbb67ae85
    c = 0x3c6ef372
    d = 0xa54ff53a
    e = 0x510e527f
    f = 0x9b05688c
    g = 0x1f83d9ab
    h = 0x5be0cd19
    i = 0
    while i < 16
      t1 = h + (((e >> 6) | (e << 26)) ^ ((e >> 11) | (e << 21)) ^ ((e >> 25) | (e << 7))) + (g ^ (e & (f ^ g))) + kc[i] + m[i & 15]
      t2 = (((a >> 2) | (a << 30)) ^ ((a >> 13) | (a << 19)) ^ ((a >> 22) | (a << 10))) + ((a & b) ^ (c & (a ^ b)))
      h = g
      g = f
      f = e
      e = d + t1
      d = c
      c = b
      b = a
      a = t1 + t2
      i = i + 1
    i = 16
    while i < 61
      x = m[(i + 1) & 15]
      y = m[(i + 14) & 15]
      m[i & 15] = m[i & 15] + (((x >> 7) | (x << 25)) ^ ((x >> 18) | (x << 14)) ^ (x >> 3)) + m[(i + 9) & 15] + (((y >> 17) | (y << 15)) ^ ((y >> 19) | (y << 13)) ^ (y >> 10))
      t1 = h + (((e >> 6) | (e << 26)) ^ ((e >> 11) | (e << 21)) ^ ((e >> 25) | (e << 7))) + (g ^ (e & (f ^ g))) + kc[i] + m[i & 15]
      t2 = (((a >> 2) | (a << 30)) ^ ((a >> 13) | (a << 19)) ^ ((a >> 22) | (a << 10))) + ((a & b) ^ (c & (a ^ b)))
      h = g
      g = f
      f = e
      e = d + t1
      d = c
      c = b
      b = a
      a = t1 + t2
      i = i + 1
    # Report every candidate whose most significant word does not already
    # lose. The host settles it with the reference implementation.
    h7 = 0x5be0cd19 + e ## u32
    v7 = ((h7 >> 24) & 255) | ((h7 >> 8) & 65280) | ((h7 & 65280) << 8) | (h7 << 24) ## u32
    if v7 < best_val
      best_val = v7
      best_nonce = nonce
    if v7 <= top
      slot = gpu.atomic_fetch_add_i32(out, 0, 1) ## i32
      if slot < 15
        gpu.atomic_store_i32(out, 1 + slot, nonce)
    idx = idx + 1
  # Reduce the thread-local minimum into out[16], nonce into out[17]. The
  # atomic min is SIGNED, so bias by the sign bit: XOR-ing 0x80000000 makes
  # unsigned order match signed order. The nonce store races the value, so it
  # is best-effort — the host recomputes the digest and shows it only if its
  # top word still equals out[16]. The leading-zero COUNT is always exact.
  mybias = best_val ^ 0x80000000 ## u32
  gpu.atomic_min_i32(out, 16, mybias)
  cur = gpu.atomic_load_i32(out, 16) ## u32
  if cur == mybias
    gpu.atomic_store_i32(out, 17, best_nonce)

# One full digest per thread. The search kernel only ever reports nonces, so
# proving the GPU's arithmetic against the CPU's nonce by nonce needs a
# kernel that surrenders the digest itself. Same rounds; it runs the second
# hash to 64 and feeds forward instead of stopping at 61. Not on the mining
# path — a differential-test kernel.
## u32[]: job, out
@gpu fn sha256d_digest(job, out)
  kc = [0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2] ## u32[]
  gid = gpu.thread_position_in_grid.x ## u32
  count = job[30] ## u32
  if gid < count
    nonce = job[29] + gid ## u32
    m = u32[16]
    m[0] = job[19]
    m[1] = job[20]
    m[2] = job[18]
    m[3] = ((nonce >> 24) & 255) | ((nonce >> 8) & 65280) | ((nonce & 65280) << 8) | (nonce << 24)
    m[4] = 0x80000000
    m[5] = 0
    m[6] = 0
    m[7] = 0
    m[8] = 0
    m[9] = 0
    m[10] = 0
    m[11] = 0
    m[12] = 0
    m[13] = 0
    m[14] = 0
    m[15] = 640
    a = job[8] ## u32
    b = job[9] ## u32
    c = job[10] ## u32
    d = job[11] ## u32
    e = job[12] ## u32
    f = job[13] ## u32
    g = job[14] ## u32
    h = job[15] ## u32
    i = 3 ## u32 unroll
    while i < 18
      t1 = h + (((e >> 6) | (e << 26)) ^ ((e >> 11) | (e << 21)) ^ ((e >> 25) | (e << 7))) + (g ^ (e & (f ^ g))) + kc[i] + m[i & 15] ## u32
      t2 = (((a >> 2) | (a << 30)) ^ ((a >> 13) | (a << 19)) ^ ((a >> 22) | (a << 10))) + ((a & b) ^ (c & (a ^ b))) ## u32
      h = g
      g = f
      f = e
      e = d + t1
      d = c
      c = b
      b = a
      a = t1 + t2
      i = i + 1
    i = 18
    while i < 64
      x = m[(i + 1) & 15] ## u32
      y = m[(i + 14) & 15] ## u32
      m[i & 15] = m[i & 15] + (((x >> 7) | (x << 25)) ^ ((x >> 18) | (x << 14)) ^ (x >> 3)) + m[(i + 9) & 15] + (((y >> 17) | (y << 15)) ^ ((y >> 19) | (y << 13)) ^ (y >> 10))
      t1 = h + (((e >> 6) | (e << 26)) ^ ((e >> 11) | (e << 21)) ^ ((e >> 25) | (e << 7))) + (g ^ (e & (f ^ g))) + kc[i] + m[i & 15]
      t2 = (((a >> 2) | (a << 30)) ^ ((a >> 13) | (a << 19)) ^ ((a >> 22) | (a << 10))) + ((a & b) ^ (c & (a ^ b)))
      h = g
      g = f
      f = e
      e = d + t1
      d = c
      c = b
      b = a
      a = t1 + t2
      i = i + 1
    m[0] = job[0] + a
    m[1] = job[1] + b
    m[2] = job[2] + c
    m[3] = job[3] + d
    m[4] = job[4] + e
    m[5] = job[5] + f
    m[6] = job[6] + g
    m[7] = job[7] + h
    m[8] = 0x80000000
    m[9] = 0
    m[10] = 0
    m[11] = 0
    m[12] = 0
    m[13] = 0
    m[14] = 0
    m[15] = 256
    a = 0x6a09e667
    b = 0xbb67ae85
    c = 0x3c6ef372
    d = 0xa54ff53a
    e = 0x510e527f
    f = 0x9b05688c
    g = 0x1f83d9ab
    h = 0x5be0cd19
    i = 0
    while i < 16
      t1 = h + (((e >> 6) | (e << 26)) ^ ((e >> 11) | (e << 21)) ^ ((e >> 25) | (e << 7))) + (g ^ (e & (f ^ g))) + kc[i] + m[i & 15]
      t2 = (((a >> 2) | (a << 30)) ^ ((a >> 13) | (a << 19)) ^ ((a >> 22) | (a << 10))) + ((a & b) ^ (c & (a ^ b)))
      h = g
      g = f
      f = e
      e = d + t1
      d = c
      c = b
      b = a
      a = t1 + t2
      i = i + 1
    i = 16
    while i < 64
      x = m[(i + 1) & 15]
      y = m[(i + 14) & 15]
      m[i & 15] = m[i & 15] + (((x >> 7) | (x << 25)) ^ ((x >> 18) | (x << 14)) ^ (x >> 3)) + m[(i + 9) & 15] + (((y >> 17) | (y << 15)) ^ ((y >> 19) | (y << 13)) ^ (y >> 10))
      t1 = h + (((e >> 6) | (e << 26)) ^ ((e >> 11) | (e << 21)) ^ ((e >> 25) | (e << 7))) + (g ^ (e & (f ^ g))) + kc[i] + m[i & 15]
      t2 = (((a >> 2) | (a << 30)) ^ ((a >> 13) | (a << 19)) ^ ((a >> 22) | (a << 10))) + ((a & b) ^ (c & (a ^ b)))
      h = g
      g = f
      f = e
      e = d + t1
      d = c
      c = b
      b = a
      a = t1 + t2
      i = i + 1
    o = gid * 8 ## u32
    out[o] = 0x6a09e667 + a
    out[o + 1] = 0xbb67ae85 + b
    out[o + 2] = 0x3c6ef372 + c
    out[o + 3] = 0xa54ff53a + d
    out[o + 4] = 0x510e527f + e
    out[o + 5] = 0x9b05688c + f
    out[o + 6] = 0x1f83d9ab + g
    out[o + 7] = 0x5be0cd19 + h

# ---- host side ------------------------------------------------------------

# How many nonces gpu_search_digests can return in one call, fixed by the
# result buffer it allocates up front.
GPU_SEARCH_DIGEST_MAX = 8192

# `@gpu fn` sidecars land next to the SOURCE .w, so this is the path from
# the repo root. Override when running from elsewhere.
-> gpu_search_metal_path
  p = env("TUNGSTEN_CRYPTO_GPU_SEARCH_METAL")
  if p != nil && p != ""
    return p
  "bits/tungsten-crypto/lib/gpu_search.metal"

# True when this host can run the kernels at all: a Metal device, and an
# emitted sidecar to load. Returns false rather than raising.
-> gpu_search_available
  if !file_exists?(gpu_search_metal_path())
    return false
  metal_device() != nil

# Compile the kernels and allocate every buffer the search reuses. Returns a
# context hash, or nil when there is no sidecar to load.
#
# The buffers are page-aligned `metal_array`s wrapped zero-copy: on unified
# memory, writing `job[29]` on the CPU IS writing the bytes the GPU reads.
# The search loop has no upload and no readback step.
-> gpu_search_open
  if !file_exists?(gpu_search_metal_path())
    return nil
  device = metal_device()
  library = metal_compile_source(device, read_file(gpu_search_metal_path()))
  job = metal_array(32, 32)
  out = metal_array(33, 18)
  # Eight big-endian words per nonce, so this holds GPU_SEARCH_DIGEST_MAX
  # digests — the cap gpu_search_digests enforces.
  dig = metal_array(32, GPU_SEARCH_DIGEST_MAX * 8)
  {
    device: device,
    queue: metal_queue(device),
    mine: metal_pipeline(library, "sha256d_mine"),
    digest: metal_pipeline(library, "sha256d_digest"),
    job: job,
    out: out,
    dig: dig,
    job_buf: metal_buffer_for(device, job),
    out_buf: metal_buffer_for(device, out),
    dig_buf: metal_buffer_for(device, dig)
  }

# Load the job constants. `prepared` is miner_prepare's i64[24] — the same
# derivation the CPU miner uses — and `target` the eight big-endian words
# from btc_target_from_bits.
-> gpu_search_load(g, prepared, target)
  job = g[:job]
  i = 0 ## i64
  while i < 21
    job[i] = prepared[i] & 0xFFFFFFFF
    i += 1
  i = 0
  while i < 8
    job[21 + i] = target[i] & 0xFFFFFFFF
    i += 1
  nil

# Dispatch the filter over [start, start+count) and return the candidate
# nonces it reported, unconfirmed and in completion order.
#
#   per  nonces per thread; count / per threads are launched
#   tg   threads per threadgroup
-> gpu_search_candidates(g, start, count, per, tg)
  job = g[:job]
  out = g[:out]
  job[29] = start & 0xFFFFFFFF
  job[30] = count
  job[31] = per
  out[0] = 0
  threads = (count + per - 1) / per
  groups = (threads + tg - 1) / tg
  metal_dispatch_groups(g[:queue], g[:mine], [g[:job_buf], g[:out_buf]], groups, tg)
  n = out[0]
  if n > 15
    n = 15
  hits = []
  i = 0 ## i64
  while i < n
    hits.push(out[1 + i] & 0xFFFFFFFF)
    i += 1
  hits

# Search [start, start+count) and return the lowest nonce that actually
# meets the target, or -1. Every candidate the GPU reports is settled here
# by `miner_hash_nonce` and `btc_meets_target` — the reference
# implementations — so the GPU cannot report a win that is not one.
-> gpu_search_run(g, prepared, target, start, count, per, tg, k)
  hits = gpu_search_candidates(g, start, count, per, tg)
  best = -1 ## i64
  i = 0 ## i64
  while i < hits.size()
    n = hits[i]
    if btc_meets_target(miner_hash_nonce(prepared, n, k), target) == 1
      if best == -1 || n < best
        best = n
    i += 1
  best

# Search a chunk and also report the smallest value seen, so a live display
# can show progress. Returns {nonce: winner or -1, best: min top word,
# best_nonce: a nonce that produced it}. gpu_search_load must have been
# called for the current header first.
-> gpu_search_run_best(g, prepared, target, start, count, per, tg, k)
  job = g[:job]
  out = g[:out]
  job[29] = start & 0xFFFFFFFF
  job[30] = count
  job[31] = per
  out[0] = 0
  out[16] = 0x7FFFFFFF
  out[17] = 0
  threads = (count + per - 1) / per
  groups = (threads + tg - 1) / tg
  metal_dispatch_groups(g[:queue], g[:mine], [g[:job_buf], g[:out_buf]], groups, tg)
  n = out[0]
  if n > 15
    n = 15
  nonce = -1 ## i64
  i = 0 ## i64
  while i < n
    c = out[1 + i] & 0xFFFFFFFF
    if btc_meets_target(miner_hash_nonce(prepared, c, k), target) == 1
      if nonce == -1 || c < nonce
        nonce = c
    i += 1
  best = (out[16] ^ 0x80000000) & 0xFFFFFFFF
  {nonce: nonce, best: best, best_nonce: out[17] & 0xFFFFFFFF}

# Full digests for `count` consecutive nonces from `start`, as an
# i64[count * 8] of big-endian chaining words — the same form
# miner_hash_nonce returns, so sha256_hex_le applies unchanged. Returns nil
# past GPU_SEARCH_DIGEST_MAX rather than reading off the end of the buffer.
-> gpu_search_digests(g, start, count)
  if count > GPU_SEARCH_DIGEST_MAX
    return nil
  job = g[:job]
  dig = g[:dig]
  job[29] = start & 0xFFFFFFFF
  job[30] = count
  metal_dispatch_groups(g[:queue], g[:digest], [g[:job_buf], g[:dig_buf]], (count + 63) / 64, 64)
  d = i64[count * 8]
  i = 0 ## i64
  while i < count * 8
    d[i] = dig[i] & 0xFFFFFFFF
    i += 1
  d
