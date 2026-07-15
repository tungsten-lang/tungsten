# Pure-Tungsten constructor for the deliberate-symmetry-breaking control arm.
# It applies one exact fixed-cube split to a C3 x Z2 6x6 seed and refuses to
# write unless the result remains an exact matrix-multiplication scheme and
# has actually left the six-image quotient.

use metaflip_worker
use flipfleet_d3

av = argv()
if av.size() < 2
  << "usage: flipfleet_d3_break_seed <seed> <output> [ordinal] [axis]"
  exit(2)

seed_path = av[0]
output_path = av[1]
ordinal = 0 ## i64
axis = 0 ## i64
if av.size() > 2
  ordinal = av[2].to_i()
if av.size() > 3
  axis = av[3].to_i()

n = 6 ## i64
cap = ffw_default_capacity(n) ## i64
size = ffw_state_size(cap) ## i64
seed = i64[size]
rank = ffw_load_scheme_cap(seed, seed_path, n, cap, 74001, 4, 2, 1000, 250) ## i64
if rank < 1 || ffw_verify_best_exact(seed, n) != 1
  << "D3BREAK_ERROR seed_exact=0"
  exit(2)

us = i64[cap]
vs = i64[cap]
ws = i64[cap]
rank = ffw_export_best(seed, us, vs, ws)
if ffd3_is_closed(us, vs, ws, rank, n) != 1
  << "D3BREAK_ERROR seed_d3=0"
  exit(2)

meta = i64[8]
rank = ffe_break(us, vs, ws, rank, cap, n, ordinal, axis, meta)
if rank < 1 || meta[7] != 1
  << "D3BREAK_ERROR eligible=0"
  exit(2)

broken = i64[size]
loaded = ffw_init_terms_cap(broken, us, vs, ws, rank, n, cap, 74003, 4, 2, 1000, 250) ## i64
if loaded != rank || ffw_verify_best_exact(broken, n) != 1
  << "D3BREAK_ERROR output_exact=0"
  exit(2)
if ffd3_is_closed(us, vs, ws, rank, n) != 0
  << "D3BREAK_ERROR output_d3=1"
  exit(2)

written = ffw_dump_best(broken, output_path) ## i64
if written != rank
  << "D3BREAK_ERROR write=0"
  exit(2)
<< "D3BREAK_RESULT rank=" + rank.to_s() + " z2_defect=" + ffd3_z2_defect(us, vs, ws, rank, n).to_s() + " exact=1 output=" + output_path
