# Static partition vs dynamic work queue on a HETEROGENEOUS CPU.
#
# The M5 Max has 6 "Super" and 12 "Performance" cores. A static 1/N split
# hands every core the same amount of work, so the batch finishes when the
# SLOWEST core does — the fast cores idle at the end. A queue of many small
# chunks pulled through an atomic counter lets fast cores take more items,
# which is the real argument for many-small-tasks over few-big-ones.
#
# This is NOT about goroutines vs threads. It is about dynamic vs static
# assignment. The pullers here are OS threads because the work never blocks.

use ../lib/crypto

# `counter` is a boxed Atomic so it stays untyped; every raw pointer MUST be
# declared i64. Without a native signature the pointers arrive BOXED and
# ccall_nobox passes the box as an address — an immediate segfault.
-> queue_worker(counter, nchunks, chunk, start, mid_ptr, tail_ptr, tgt_ptr, out_ptr, best_ptr, nohash) (Object i64 i64 i64 i64 i64 i64 i64 i64 i64) i64
  n = 0 ## i64
  loop
    # ccall, not `counter.increment` — a METHOD dispatch inside a worker
    # thread goes through the global inline caches, which are not
    # thread-safe here and segfault under 18-way contention.
    idx = ccall("w_atomic_increment", counter) - 1
    if idx >= nchunks
      break
    base = start + idx * chunk
    ccall_nobox("w_sha256_hw_mine", mid_ptr, tail_ptr, tgt_ptr, base, chunk, out_ptr, best_ptr, nohash)
    n += 1
  n

k = sha256_k()
ZERO = "0000000000000000000000000000000000000000000000000000000000000000"
GM = "4a5e1e4baab89f3a32518a88c31bc87f618f76673e2cc77ab2127b7afdeda33b"
header = btc_header_bytes(1, ZERO, GM, 1231006505, 0x1d00ffff, 0)
hard = btc_target_from_bits(0x03000001)
cores = System.cpu_count
TOTAL = 400000000

<< "[cores] cores, [TOTAL] nonces"
<< ""

pool = crypto_pool_prepare(header, hard, cores, k)
t0 = crypto_now_ms()
crypto_mine_parallel(pool, 0, TOTAL, k)
ms_static = crypto_now_ms() - t0
<< "static  1/[cores] partition        [ms_static] ms   [TOTAL / ms_static * 1000 / 1000000] MH/s"

# Dynamic: many small chunks, pulled by an atomic counter.
sizes = [50, 200, 800]
si = 0
while si < sizes.size
  nchunks = sizes[si]
  chunk = TOTAL / nchunks
  counter = Atomic.new(0)
  zero = 0 ## i64
  nohash = 0 ## i64
  mid_ptr = pool[:mid_ptr]
  tail_ptr = pool[:tail_ptr]
  tgt_ptr = pool[:tgt_ptr]
  outs_ptr = pool[:outs_ptr]
  bests_ptr = pool[:bests_ptr]
  handles = []
  t0 = crypto_now_ms()
  i = 0
  while i < cores
    op = outs_ptr + i * 32
    bp = bests_ptr + i * 4
    handles.push(Thread.new -> queue_worker(counter, nchunks, chunk, zero, mid_ptr, tail_ptr, tgt_ptr, op, bp, nohash))
    i += 1
  i = 0
  while i < handles.size
    handles[i].join
    i += 1
  ms = crypto_now_ms() - t0
  << "dynamic [nchunks] chunks of [chunk / 1000000]M   [ms] ms   [TOTAL / ms * 1000 / 1000000] MH/s   ([ms_static * 100 / ms]% of static)"
  si += 1
