# Thread-count sweep. On a heterogeneous CPU the best count is not always
# "all of them" — the small cores can drag the aggregate if work is split
# evenly across unequal cores.

use ../lib/crypto

k = sha256_k()
ZERO = "0000000000000000000000000000000000000000000000000000000000000000"
GM = "4a5e1e4baab89f3a32518a88c31bc87f618f76673e2cc77ab2127b7afdeda33b"
header = btc_header_bytes(1, ZERO, GM, 1231006505, 0x1d00ffff, 0)
hard = btc_target_from_bits(0x03000001)
N = 120000000

<< "cores reported: [System.cpu_count]"
<< "sha extension : [crypto_accel_available()]"
<< ""
<< "  threads     rate        per-thread     vs 1 thread"
<< "  ───────  ───────────  ────────────  ─────────────"
base = 0
counts = [1, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 24]
i = 0
while i < counts.size
  t = counts[i]
  pool = crypto_pool_prepare(header, hard, t, k)
  t0 = crypto_now_ms()
  crypto_mine_parallel(pool, 1000000, N, k)
  ms = crypto_now_ms() - t0
  hs = N / ms * 1000
  if t == 1
    base = hs
  per = hs / t
  << "  [t]  [hs / 1000000].[(hs % 1000000) / 10000] MH/s  [per / 1000000].[(per % 1000000) / 10000] MH/s   [hs * 100 / base]%"
  i += 1
