# Equal-compute comparison: parent-guided +1 chords versus blind +1 splits.

use metaflip_worker
use flipfleet_parent_chord
use flipfleet_frontier_escape_banks

n = 5 ## i64
cap = ffw_default_capacity(n) ## i64
size = ffw_state_size(cap) ## i64
parent_a = i64[size]
parent_b = i64[size]
arank = ffw_load_scheme_cap(parent_a, "benchmarks/matmul/metaflip/matmul_5x5_rank93_d1155_gf2.txt", n, cap, 9001, 4, 2, 20000000, 5000000) ## i64
brank = ffw_load_scheme_cap(parent_b, "benchmarks/matmul/metaflip/matmul_5x5_rank93_d1168_gf2.txt", n, cap, 9003, 4, 2, 20000000, 5000000) ## i64
if arank != 93 || brank != 93
  exit(1)
au = i64[cap]
av = i64[cap]
aw = i64[cap]
bu = i64[cap]
bv = i64[cap]
bw = i64[cap]
z = ffw_export_best(parent_a, au, av, aw) ## i64
z = ffw_export_best(parent_b, bu, bv, bw) ## i64
guided_count = ffpc_count(au, av, aw, arank, bu, bv, bw, brank) ## i64
if guided_count < 1
  exit(1)

guided_steps = 20000000 ## i64
blind_trials = guided_count * 4 ## i64
blind_steps = guided_steps / 4 ## i64
guided_returns = 0 ## i64
guided_improves = 0 ## i64
guided_bits = 0 ## i64
guided_started = ccall("__w_clock_ms") ## i64
i = 0 ## i64
while i < guided_count
  candidate = i64[size]
  loaded = ffpc_state_into(candidate, parent_a, parent_b, i, 9101 + i * 17) ## i64
  if loaded != 94
    exit(1)
  z = ffw_walk(candidate, guided_steps)
  best_rank = ffw_best_rank(candidate) ## i64
  if best_rank <= 93
    guided_returns += 1
    guided_bits += ffw_best_bits(candidate)
  if best_rank < 93 || (best_rank == 93 && ffw_best_bits(candidate) < ffw_best_bits(parent_a))
    guided_improves += 1
  i += 1
guided_ms = ccall("__w_clock_ms") - guided_started ## i64

blind_returns = 0 ## i64
blind_improves = 0 ## i64
blind_bits = 0 ## i64
blind_started = ccall("__w_clock_ms") ## i64
i = 0
while i < blind_trials
  candidate = fffeb_escape_state(parent_a, 1, i, n, cap, size, 10001 + i * 19, 4, 2, blind_steps, blind_steps / 4)
  if candidate == nil || ffw_best_rank(candidate) != 94
    exit(1)
  z = ffw_walk(candidate, blind_steps)
  best_rank = ffw_best_rank(candidate)
  if best_rank <= 93
    blind_returns += 1
    blind_bits += ffw_best_bits(candidate)
  if best_rank < 93 || (best_rank == 93 && ffw_best_bits(candidate) < ffw_best_bits(parent_a))
    blind_improves += 1
  i += 1
blind_ms = ccall("__w_clock_ms") - blind_started ## i64

guided_avg_bits = 0 ## i64
if guided_returns > 0
  guided_avg_bits = guided_bits / guided_returns
blind_avg_bits = 0 ## i64
if blind_returns > 0
  blind_avg_bits = blind_bits / blind_returns
<< "guided trials=" + guided_count.to_s() + " moves=" + (guided_count * guided_steps).to_s() + " returns=" + guided_returns.to_s() + " improvements=" + guided_improves.to_s() + " avg-return-bits=" + guided_avg_bits.to_s() + " ms=" + guided_ms.to_s()
<< "blind trials=" + blind_trials.to_s() + " moves=" + (blind_trials * blind_steps).to_s() + " returns=" + blind_returns.to_s() + " improvements=" + blind_improves.to_s() + " avg-return-bits=" + blind_avg_bits.to_s() + " ms=" + blind_ms.to_s()
