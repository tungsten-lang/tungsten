# Parallel scaling: one thread vs all cores.

use ../lib/crypto

k = sha256_k()
ZERO = "0000000000000000000000000000000000000000000000000000000000000000"
GM = "4a5e1e4baab89f3a32518a88c31bc87f618f76673e2cc77ab2127b7afdeda33b"
header = btc_header_bytes(1, ZERO, GM, 1231006505, 0x1d00ffff, 0)
easy = btc_target_from_bits(0x1d00ffff)

cores = System.cpu_count
<< "cores: [cores]"

# Correctness: the parallel search must find the genesis nonce, whichever
# worker's slice it lands in.
pool = crypto_pool_prepare(header, easy, cores, k)
r = crypto_mine_parallel(pool, 2083236000, 2000, k)
<< "parallel finds nonce [r[:nonce]] (want 2083236893)"
<< "digest [sha256_hex_le(r[:digest])]"
<< "want   000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f"

hard = btc_target_from_bits(0x03000001)
N = 40000000

p1 = crypto_pool_prepare(header, hard, 1, k)
t0 = crypto_now_ms()
crypto_mine_parallel(p1, 1000000, N, k)
ms1 = crypto_now_ms() - t0

pn = crypto_pool_prepare(header, hard, cores, k)
t0 = crypto_now_ms()
crypto_mine_parallel(pn, 1000000, N, k)
msn = crypto_now_ms() - t0

<< ""
<< "1 thread      [N * 1000 / ms1] H/s ([ms1] ms)"
<< "[cores] threads  [N * 1000 / msn] H/s ([msn] ms)"
<< "scaling       [ms1 * 100 / msn]% of single-threaded"
