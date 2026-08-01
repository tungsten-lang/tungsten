# Correctness and hash rate for the `@gpu fn` search in lib/gpu_search.w.
#
# Correctness first, because a fast wrong answer is worth nothing:
#
#   1. the genesis search — re-find nonce 2083236893 from the real block 0
#      header and reproduce its display hash
#   2. digest parity — every one of 4096 consecutive nonces hashed on the
#      GPU must match lib/miner.w word for word
#   3. filter completeness — over a window containing the genesis nonce, the
#      candidates the GPU reports must include every nonce the CPU says wins
#
# Then throughput, against a target no candidate meets, so every dispatch
# runs its full range down the reject path — the realistic steady state.
# Medians, not best-of: this box is shared and its load average swings by
# 4x, which makes a min-of-N read pure fiction.
#
# Run compiled, from the repo root. `@gpu fn` sidecars land next to the .w
# that was compiled, so the kernel source has to be emitted from
# lib/gpu_search.w itself — that is the path lib/gpu_search.w then loads at
# runtime, and it is why there are two steps:
#
#   bin/tungsten --ll bits/tungsten-crypto/lib/gpu_search.w      # emit the .metal
#   bin/tungsten -o /tmp/bench_gpu_search bits/tungsten-crypto/benchmarks/bench_gpu_search.w
#   /tmp/bench_gpu_search

use ../lib/crypto
use ../lib/gpu_search

k = sha256_k()
ZERO = "0000000000000000000000000000000000000000000000000000000000000000"
GM = "4a5e1e4baab89f3a32518a88c31bc87f618f76673e2cc77ab2127b7afdeda33b"
GENESIS_HASH = "000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f"
GENESIS_NONCE = 2083236893

header = btc_header_bytes(1, ZERO, GM, 1231006505, 0x1d00ffff, 0)
easy = btc_target_from_bits(0x1d00ffff)
job = miner_prepare(header, k)

if !gpu_search_available()
  << "no GPU: lib/gpu_search.metal is missing, or this host has no Metal device"
  << "  (the sidecar is emitted by compiling lib/gpu_search.w; run from the repo root)"
  exit 1

g = gpu_search_open()
gpu_search_load(g, job, easy)

ok = 1

<< "correctness"

# ---- 1. the genesis search ----
n = gpu_search_run(g, job, easy, 2083236880, 4096, 1, 64, k)
<< "  genesis search finds nonce [n]"
if n != GENESIS_NONCE
  ok = 0
  << "  MISMATCH — expected [GENESIS_NONCE]"
else
  hex = sha256_hex_le(miner_hash_nonce(job, n, k))
  << "  its hash is [hex]"
  if hex != GENESIS_HASH
    ok = 0
    << "  MISMATCH — expected [GENESIS_HASH]"

# ---- 2. digest parity, GPU vs lib/miner.w ----
NP = 4096
base = 3000000
gd = gpu_search_digests(g, base, NP)
bad = 0
i = 0 ## i64
while i < NP
  cd = miner_hash_nonce(job, base + i, k)
  j = 0 ## i64
  while j < 8
    if gd[i * 8 + j] != cd[j]
      bad += 1
    j += 1
  i += 1
<< "  digest parity over [NP] nonces: [bad] mismatched words"
if bad != 0
  ok = 0

# ---- 3. the H7 filter never drops a winner ----
# The kernel reports candidates, not winners. Over a window containing the
# genesis nonce, everything the CPU calls a win must be in that report.
WIN = 20000
wbase = 2083230000
cands = gpu_search_candidates(g, wbase, WIN, 1, 64)
missed = 0
cpu_wins = 0
i = 0
while i < WIN
  nn = wbase + i
  if btc_meets_target(miner_hash_nonce(job, nn, k), easy) == 1
    cpu_wins += 1
    seen = 0
    j = 0
    while j < cands.size()
      if cands[j] == nn
        seen = 1
      j += 1
    if seen == 0
      missed += 1
  i += 1
<< "  over [WIN] nonces the CPU finds [cpu_wins] winner(s); GPU reported [cands.size()] candidate(s), missed [missed]"
if missed != 0 || cpu_wins == 0
  ok = 0

if ok == 1
  << "  all three pass"
else
  << "  FAILED"
  exit 1

# ---- throughput ----
# A target no candidate will meet, so the whole range runs the reject path.
hard = btc_target_from_bits(0x03000001)
gpu_search_load(g, job, hard)

<< ""
<< "throughput (reject path, medians of 5)"

PER = 64
THREADS = 2097152
TOTAL = THREADS * PER

-> median5(a)
  i = 0 ## i64
  while i < 5
    j = i + 1 ## i64
    while j < 5
      if a[j] < a[i]
        t = a[i]
        a[i] = a[j]
        a[j] = t
      j += 1
    i += 1
  a[2]

tgs = [32, 64, 128, 256, 512, 1024]
best = 0 ## i64
best_tg = 0 ## i64
ti = 0 ## i64
while ti < tgs.size()
  tg = tgs[ti]
  r = i64[5]
  gpu_search_candidates(g, 1000000, TOTAL, PER, tg)
  rep = 0 ## i64
  while rep < 5
    t0 = crypto_now_ms()
    gpu_search_candidates(g, 1000000 + rep * 7919, TOTAL, PER, tg)
    ms = crypto_now_ms() - t0
    if ms < 1
      ms = 1
    r[rep] = TOTAL / ms * 1000
    rep += 1
  hs = median5(r)
  << "  tg=[tg] per=[PER]  [hs / 1000000] MH/s"
  if hs > best
    best = hs
    best_tg = tg
  ti += 1

<< ""
<< "best [best / 1000000] MH/s at tg=[best_tg], per=[PER]"
