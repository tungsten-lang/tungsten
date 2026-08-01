# Multi-threaded nonce search.
#
# The nonce space splits perfectly: each worker scans a disjoint slice and
# they never need to communicate, which is the one genuinely nice property
# of proof-of-work. Speedup is linear in cores until memory bandwidth or
# thermal limits bite, and neither is close for a workload this small.
#
# Worker discipline (this is load-bearing, not style)
# ---------------------------------------------------
# Threads share the parent heap, and a worker that allocates can trip the
# allocator or the inline caches. So every array a worker touches is
# allocated HERE, on the main thread, before any thread is spawned; the
# worker body does nothing but a `ccall` into C with pointers it was
# handed. The main thread only joins while workers run — it must not
# dispatch other work, because inline caches are global.
#
# Layout of the shared `slots` array, one 8-slot row per worker:
#   [0] start nonce      [1] count      [2] result (-1 until found)
#   [3] done flag        [4..7] reserved/padding
#
# The row is 8 words = 64 bytes, one cache line, so workers writing their
# own results never false-share a line with a neighbour.

use accel

CRYPTO_SLOT_STRIDE = 8

# Prepare per-worker state. Everything a worker will touch is allocated
# here, up front.
#
# Returns a hash of the pre-allocated buffers; `mine_parallel` consumes it.
-> crypto_pool_prepare(header, target, workers, k)
  mid = i32[8]
  tail = u8[12]
  tgt = i32[8]
  # One digest buffer per worker, contiguous: worker i writes words
  # [i*8 .. i*8+7]. Allocated as a single array so there is no per-worker
  # object for a thread to chase.
  outs = i32[workers * 8]
  # One best-so-far word per worker: the smallest top-32-bits-of-the-value
  # any candidate in that worker's slice produced. Written once when the
  # worker finishes, never inside the hot loop.
  bests = i32[workers]
  # Full 8-word digest of each worker's best candidate.
  besth = i32[workers * 8]
  # `besth` is SCRATCH that C overwrites on every sub-chunk call. `bestk` is
  # the worker's running best across all its sub-chunks, which is what the
  # display must read — otherwise the reported value and the reported digest
  # come from different calls and disagree.
  bestk = i32[workers * 8]
  slots = i64[workers * CRYPTO_SLOT_STRIDE]

  st = sha256_iv()
  w = i64[64]
  j = 0 ## i64
  while j < 16
    off = j * 4
    w[j] = (header[off] << 24) | (header[off + 1] << 16) | (header[off + 2] << 8) | header[off + 3]
    j += 1
  sha256_block(st, w, k)
  j = 0
  while j < 8
    mid[j] = st[j]
    tgt[j] = target[j]
    j += 1
  j = 0
  while j < 12
    tail[j] = header[64 + j]
    j += 1

  {
    mid: mid, tail: tail, tgt: tgt, outs: outs, slots: slots, bests: bests, besth: besth, bestk: bestk,
    workers: workers,
    bests_ptr: ccall_nobox("w_array_data_ptr", bests),
    besth_ptr: ccall_nobox("w_array_data_ptr", besth),
    mid_ptr: ccall_nobox("w_array_data_ptr", mid),
    tail_ptr: ccall_nobox("w_array_data_ptr", tail),
    tgt_ptr: ccall_nobox("w_array_data_ptr", tgt),
    outs_ptr: ccall_nobox("w_array_data_ptr", outs)
  }

# One worker's body: scan its slice and record the result. Allocation-free —
# every value it uses is a raw integer or a pointer computed by the caller.
-> crypto_pool_worker(slots, slot, mid_ptr, tail_ptr, tgt_ptr, out_ptr, best_ptr, besth_ptr) (i64[] i64 i64 i64 i64 i64 i64 i64) i64
  base = slot * CRYPTO_SLOT_STRIDE ## i64
  start = slots[base] ## i64
  count = slots[base + 1] ## i64
  found = ccall_nobox("w_sha256_hw_mine", mid_ptr, tail_ptr, tgt_ptr, start, count, out_ptr, best_ptr, besth_ptr)
  slots[base + 2] = found
  slots[base + 3] = 1
  found

# Search [start, start+count) across `workers` threads. Returns a hash with
# the winning nonce (or -1) and the digest words.
-> crypto_mine_parallel(pool, start, count, k)
  workers = pool[:workers]
  slots = pool[:slots]
  outs = pool[:outs]
  mid_ptr = pool[:mid_ptr]
  tail_ptr = pool[:tail_ptr]
  tgt_ptr = pool[:tgt_ptr]
  outs_ptr = pool[:outs_ptr]
  bests_ptr = pool[:bests_ptr]
  bests = pool[:bests]
  besth = pool[:besth]
  besth_ptr_base = pool[:besth_ptr]

  per = count / workers
  i = 0 ## i64
  while i < workers
    base = i * CRYPTO_SLOT_STRIDE
    slots[base] = start + i * per
    # The last worker absorbs the remainder so no nonce is skipped.
    if i == workers - 1
      slots[base + 1] = count - i * per
    else
      slots[base + 1] = per
    slots[base + 2] = -1
    slots[base + 3] = 0
    i += 1

  handles = []
  i = 0
  while i < workers
    # Each worker gets its own 32-byte digest slot inside `outs`; i32 is
    # 4 bytes, so worker i's words begin at byte offset i * 32.
    out_ptr = outs_ptr + i * 32
    best_ptr = bests_ptr + i * 4
    besth_ptr = besth_ptr_base + i * 32
    slot = i
    handles.push(Thread.new -> crypto_pool_worker(slots, slot, mid_ptr, tail_ptr, tgt_ptr, out_ptr, best_ptr, besth_ptr))
    i += 1
  # Nothing but joining happens here while the workers run.
  i = 0
  while i < handles.size
    handles[i].join
    i += 1

  nonce = -1 ## i64
  winner = 0 ## i64
  # Actual work done, so a caller can report a real hash rate. A worker that
  # found a nonce stopped there; one that did not ran its whole slice.
  # Assuming a full sweep would overstate the rate by orders of magnitude on
  # an easy target, where every worker exits early.
  scanned = 0 ## i64
  best = 0xFFFFFFFF ## i64
  best_worker = -1 ## i64
  i = 0
  while i < workers
    base = i * CRYPTO_SLOT_STRIDE
    r = slots[base + 2]
    if r >= 0
      scanned += r - slots[base] + 1
      # Lowest winning nonce wins, so the result does not depend on which
      # thread happened to finish first.
      if nonce < 0 || r < nonce
        nonce = r
        winner = i
    else
      scanned += slots[base + 1]
    wb = bests[i] & 0xFFFFFFFF
    if wb < best
      best = wb
      best_worker = i
    i += 1

  digest = i64[8]
  if nonce >= 0
    j = 0 ## i64
    while j < 8
      digest[j] = outs[winner * 8 + j] & 0xFFFFFFFF
      j += 1
  bh = i64[8]
  if best_worker >= 0
    j = 0
    while j < 8
      bh[j] = besth[best_worker * 8 + j] & 0xFFFFFFFF
      j += 1
  {nonce: nonce, digest: digest, scanned: scanned, best: best, best_hash: bh}

# ---- persistent workers ----------------------------------------------------
#
# The spawn-per-chunk design paid pthread_create/join for every display
# refresh — about 130 spawns/second, measured at 11% of throughput. Here the
# workers are spawned ONCE for the whole range and loop internally over
# sub-chunks, publishing progress into their own slot row as they go. The
# main thread reads those rows to draw, and joins only at the end.
#
# Slot row layout gains three fields:
#   [4] nonces completed so far   [5] running best value
#   [6] stop flag (set by any worker that wins, so the rest exit early)
#
# Nothing here is locked. Each worker owns its row; the main thread only
# reads. A torn read would at worst draw a stale counter for one frame, and
# the AUTHORITATIVE result is taken after join, never from a live read.

# EVERY raw pointer must be declared i64 here. Without a native signature
# the pointers arrive BOXED and ccall_nobox hands the box to C as an
# address, which segfaults immediately. This cost a long debugging detour.
-> crypto_pool_worker_loop(slots, slot, bests, besth, bestk, mid_ptr, tail_ptr, tgt_ptr, out_ptr, best_ptr, besth_ptr, sub) (i64[] i64 i32[] i32[] i32[] i64 i64 i64 i64 i64 i64 i64) i64
  base = slot * CRYPTO_SLOT_STRIDE ## i64
  start = slots[base] ## i64
  count = slots[base + 1] ## i64
  done = 0 ## i64
  found = -1 ## i64
  while done < count && found < 0 && slots[6] == 0
    n = sub ## i64
    if done + n > count
      n = count - done
    r = ccall_nobox("w_sha256_hw_mine", mid_ptr, tail_ptr, tgt_ptr, start + done, n, out_ptr, best_ptr, besth_ptr)
    done += n
    # Fold this sub-chunk's best into the worker's running best. C resets its
    # local minimum per call, so without this the published value would be
    # "best of the most recent sub-chunk", not "best so far".
    cur = bests[slot] & 0xFFFFFFFF
    if cur < slots[base + 5]
      slots[base + 5] = cur
      q = 0 ## i64
      while q < 8
        bestk[slot * 8 + q] = besth[slot * 8 + q]
        q += 1
    slots[base + 4] = done
    if r >= 0
      found = r
      slots[6] = 1
  slots[base + 2] = found
  slots[base + 3] = 1
  found

# Spawn the workers over [start, start+count) and return their handles.
# `sub` is how often each worker publishes progress.
-> crypto_pool_start(pool, start, count, sub)
  workers = pool[:workers]
  slots = pool[:slots]
  mid_ptr = pool[:mid_ptr]
  tail_ptr = pool[:tail_ptr]
  tgt_ptr = pool[:tgt_ptr]
  outs_ptr = pool[:outs_ptr]
  bests_ptr = pool[:bests_ptr]
  besth_base = pool[:besth_ptr]
  wbests = pool[:bests]
  wbesth = pool[:besth]
  wbestk = pool[:bestk]

  slots[6] = 0
  # bests[] is zero-initialized, and 0 is the BEST possible value — an
  # unstarted worker would otherwise win the minimum and report 32 leading
  # zero bits before hashing anything. Seed to the worst value instead.
  bests = pool[:bests]
  z = 0 ## i64
  while z < workers
    bests[z] = 0xFFFFFFFF
    z += 1
  per = count / workers
  i = 0 ## i64
  while i < workers
    base = i * CRYPTO_SLOT_STRIDE
    slots[base] = start + i * per
    if i == workers - 1
      slots[base + 1] = count - i * per
    else
      slots[base + 1] = per
    slots[base + 2] = -1
    slots[base + 3] = 0
    slots[base + 4] = 0
    slots[base + 5] = 0xFFFFFFFF
    i += 1

  handles = []
  i = 0
  while i < workers
    op = outs_ptr + i * 32
    bp = bests_ptr + i * 4
    hp = besth_base + i * 32
    sl = i
    handles.push(Thread.new -> crypto_pool_worker_loop(slots, sl, wbests, wbesth, wbestk, mid_ptr, tail_ptr, tgt_ptr, op, bp, hp, sub))
    i += 1
  handles

# A live snapshot for the display. Read-only; may lag by a sub-chunk.
-> crypto_pool_poll(pool)
  workers = pool[:workers]
  slots = pool[:slots]
  bestk = pool[:bestk]
  scanned = 0 ## i64
  best = 0xFFFFFFFF ## i64
  bw = -1 ## i64
  live = 0 ## i64
  i = 0 ## i64
  while i < workers
    base = i * CRYPTO_SLOT_STRIDE
    scanned += slots[base + 4]
    if slots[base + 3] == 0
      live += 1
    wb = slots[base + 5] & 0xFFFFFFFF
    if wb < best
      best = wb
      bw = i
    i += 1
  bh = nil
  if bw >= 0
    bh = i64[8]
    j = 0 ## i64
    while j < 8
      bh[j] = bestk[bw * 8 + j] & 0xFFFFFFFF
      j += 1
  {scanned: scanned, best: best, best_hash: bh, live: live}

# Join and take the authoritative result.
-> crypto_pool_finish(pool, handles)
  i = 0 ## i64
  while i < handles.size
    handles[i].join
    i += 1
  workers = pool[:workers]
  slots = pool[:slots]
  outs = pool[:outs]
  nonce = -1 ## i64
  winner = 0 ## i64
  i = 0
  while i < workers
    r = slots[i * CRYPTO_SLOT_STRIDE + 2]
    if r >= 0
      if nonce < 0 || r < nonce
        nonce = r
        winner = i
    i += 1
  digest = i64[8]
  if nonce >= 0
    j = 0 ## i64
    while j < 8
      digest[j] = outs[winner * 8 + j] & 0xFFFFFFFF
      j += 1
  snap = crypto_pool_poll(pool)
  {nonce: nonce, digest: digest, scanned: snap[:scanned],
   best: snap[:best], best_hash: snap[:best_hash]}
