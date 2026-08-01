# Dispatch strategies for the same total hashing work.
#
#   A  spawn-per-chunk   spawn N OS threads, join, repeat per chunk
#   B  spawn-once        spawn N OS threads once over the whole range
#   C  goroutines        N goroutines on ONE OS thread + scheduler
#
# The question is what the pthread_create/join traffic actually costs, and
# whether goroutines are a substitute. They are not the same tool: a
# goroutine is a green thread multiplexed onto the CURRENT OS thread by
# w_scheduler_run, so N of them share one core.

use ../lib/crypto

k = sha256_k()
ZERO = "0000000000000000000000000000000000000000000000000000000000000000"
GM = "4a5e1e4baab89f3a32518a88c31bc87f618f76673e2cc77ab2127b7afdeda33b"
header = btc_header_bytes(1, ZERO, GM, 1231006505, 0x1d00ffff, 0)
hard = btc_target_from_bits(0x03000001)
cores = System.cpu_count

TOTAL = 400000000
CHUNK = 25000000

<< "total work [TOTAL] nonces, [cores] cores"
<< ""

# --- A: spawn per chunk (what the TUI does today) ---
pool = crypto_pool_prepare(header, hard, cores, k)
t0 = crypto_now_ms()
base = 0
spawns_a = 0
while base < TOTAL
  crypto_mine_parallel(pool, base, CHUNK, k)
  spawns_a += cores
  base += CHUNK
ms_a = crypto_now_ms() - t0

# --- B: spawn once over the whole range ---
pool2 = crypto_pool_prepare(header, hard, cores, k)
t0 = crypto_now_ms()
crypto_mine_parallel(pool2, 0, TOTAL, k)
ms_b = crypto_now_ms() - t0

<< "A  spawn-per-chunk  [ms_a] ms   [TOTAL / ms_a * 1000 / 1000000] MH/s   [spawns_a] thread spawns"
<< "B  spawn-once       [ms_b] ms   [TOTAL / ms_b * 1000 / 1000000] MH/s   [cores] thread spawns"
<< ""
<< "B is [ms_a * 100 / ms_b]% of A's wall time"
