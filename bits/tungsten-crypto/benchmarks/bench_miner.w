# Hash rate: naive re-hash vs midstate reuse.
#
# Both loops scan a nonce range against an unreachable target so neither can
# exit early, then report hashes per second. The naive loop re-serializes
# and re-hashes all 80 bytes from the IV (three compressions per nonce); the
# midstate loop reuses everything miner_prepare could lift out (two).
#
# Run compiled. Interpreted numbers say nothing about a hash rate:
#   bin/tungsten -o /tmp/bench_miner bits/tungsten-crypto/benchmarks/bench_miner.w

use ../lib/miner

k = sha256_k()
zero = "0000000000000000000000000000000000000000000000000000000000000000"
gm = "4a5e1e4baab89f3a32518a88c31bc87f618f76673e2cc77ab2127b7afdeda33b"

# A target no candidate in the sampled range will meet, so both loops run to
# completion and measure steady-state throughput.
hard = btc_target_from_bits(0x03000001)

n = 200000
if argv().size > 1
  n = argv()[1].to_i

header = btc_header_bytes(1, zero, gm, 1231006505, 0x1d00ffff, 0)
job = miner_prepare(header, k)

<< "scanning [n] nonces per strategy"

t0 = crypto_now_ms()
r1 = miner_search_naive(header, hard, 1000000, n, k)
t1 = crypto_now_ms()
naive_ms = t1 - t0

t0 = crypto_now_ms()
r2 = miner_search(job, hard, 1000000, n, k)
t1 = crypto_now_ms()
mid_ms = t1 - t0

if r1 != -1 || r2 != -1
  << "unexpected hit: naive=[r1] midstate=[r2]"

naive_hs = n * 1000 / naive_ms
mid_hs = n * 1000 / mid_ms

<< ""
<< "naive     [naive_ms] ms   [naive_hs] H/s   (3 compressions/nonce)"
<< "midstate  [mid_ms] ms   [mid_hs] H/s   (2 compressions/nonce)"
<< "speedup   [mid_hs * 100 / naive_hs]%"
