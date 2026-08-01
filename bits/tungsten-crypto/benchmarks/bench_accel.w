# Hash rate across all three implementations.
#
#   naive     re-serialize and re-hash all 80 bytes per nonce (3 compressions)
#   midstate  pure Tungsten, block 1 hashed once (2 compressions)
#   accel     the same midstate algorithm on the ARMv8 SHA-256 extension
#
# Correctness is checked before speed: all three must re-find the Bitcoin
# genesis nonce, and the accelerator must produce the genesis hash. A fast
# wrong answer is worth nothing.
#
# Run compiled — the C accelerator only links for files inside the bit:
#   bin/tungsten -o /tmp/bench_accel bits/tungsten-crypto/benchmarks/bench_accel.w

use ../lib/crypto

k = sha256_k()
ZERO = "0000000000000000000000000000000000000000000000000000000000000000"
GM = "4a5e1e4baab89f3a32518a88c31bc87f618f76673e2cc77ab2127b7afdeda33b"
GENESIS_HASH = "000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f"

header = btc_header_bytes(1, ZERO, GM, 1231006505, 0x1d00ffff, 0)
easy = btc_target_from_bits(0x1d00ffff)
job = miner_prepare(header, k)
out = i32[8]

<< "correctness"
<< "  hardware SHA-256 available: [crypto_accel_available()]"
n1 = miner_search_naive(header, easy, 2083236880, 40, k)
n2 = miner_search(job, easy, 2083236880, 40, k)
n3 = crypto_accel_search(header, easy, 2083236880, 40, out, k)
<< "  naive    finds nonce [n1]"
<< "  midstate finds nonce [n2]"
<< "  accel    finds nonce [n3]"
ok = 1
if n1 != 2083236893 || n2 != 2083236893 || n3 != 2083236893
  ok = 0
  << "  MISMATCH — expected 2083236893"
if sha256_hex_le(crypto_accel_digest(out)) != GENESIS_HASH
  ok = 0
  << "  accel digest wrong: [sha256_hex_le(crypto_accel_digest(out))]"
if ok == 1
  << "  all three agree, and the accelerator reproduces the genesis hash"

# A target no candidate will meet, so every loop runs its full range and
# takes the reject path — the realistic steady state.
hard = btc_target_from_bits(0x03000001)

n_slow = 300000
n_fast = 8000000

<< ""
<< "throughput (single-threaded)"

t0 = crypto_now_ms()
miner_search_naive(header, hard, 1000000, n_slow, k)
ms_naive = crypto_now_ms() - t0

t0 = crypto_now_ms()
miner_search(job, hard, 1000000, n_slow, k)
ms_mid = crypto_now_ms() - t0

t0 = crypto_now_ms()
crypto_accel_search(header, hard, 1000000, n_fast, out, k)
ms_accel = crypto_now_ms() - t0

hs_naive = n_slow * 1000 / ms_naive
hs_mid = n_slow * 1000 / ms_mid
hs_accel = n_fast * 1000 / ms_accel

<< "  naive     [hs_naive] H/s"
<< "  midstate  [hs_mid] H/s   ([hs_mid * 100 / hs_naive]% of naive)"
<< "  accel     [hs_accel] H/s   ([hs_accel / hs_mid]x the pure-Tungsten midstate loop)"
