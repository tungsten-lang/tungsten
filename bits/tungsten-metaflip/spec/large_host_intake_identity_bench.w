# Native microbenchmark for the serial work that motivated wide-fleet intake.
# It uses the bundled exact 7x7 rank-247 frontier and measures the exhaustive
# exact gate plus the symmetry/GL basin identity seen in perf profiles.

use ../lib/metaflip/scheme
use ../lib/metaflip/fleet/basins
use ../lib/metaflip/fleet/intake

root = __DIR__ + "/../lib/metaflip/seeds/gf2/"
path = root + "matmul_7x7_rank247_d3096_dynamic_syzygy_gf2.txt"
capacity = 320 ## i64
state = i64[ffw_state_size(capacity)]
rank = ffw_load_scheme_cap(state, path, 7, capacity, 77007, 0, 1, 1, 1) ## i64
if rank != 247 || ffw_verify_best_exact(state, 7) == 0
  << "FAIL large-host intake identity benchmark: exact rank-247 seed did not load"
  exit(1)

# Fault in the identity code and its state pages before either measurement.
warm = ffbi_best_id(state) ## i64
if warm == 0
  << "FAIL large-host intake identity benchmark: zero identity"
  exit(1)

full_checksum = 0 ## i64
full_count = 0 ## i64
started = ccall_nobox("__w_clock_ns_raw") ## i64
slot = 0 ## i64
while slot < 188
  full_checksum = full_checksum ^ ffbi_best_id(state)
  full_count += ffw_verify_best_exact(state, 7)
  slot += 1
full_ns = ccall_nobox("__w_clock_ns_raw") - started ## i64

bounded_checksum = 0 ## i64
bounded_count = 0 ## i64
started = ccall_nobox("__w_clock_ns_raw")
slot = 0
while slot < 188
  if ffci_rotating_slot(slot, 188, 0) == 1
    bounded_checksum = bounded_checksum ^ ffbi_best_id(state)
    bounded_count += ffw_verify_best_exact(state, 7)
  slot += 1
bounded_ns = ccall_nobox("__w_clock_ns_raw") - started ## i64

if full_count != 188 || bounded_count != 12 || full_checksum != 0 || bounded_checksum != 0
  << "FAIL large-host intake identity benchmark: admission accounting"
  exit(1)
if full_ns < 1
  full_ns = 1
if bounded_ns < 1
  bounded_ns = 1
speedup_milli = full_ns * 1000 / bounded_ns ## i64
<< "INTAKE_IDENTITY_BENCH tensor=7x7 rank=247 full=188 full_ns=" + full_ns.to_s() + " bounded=12 bounded_ns=" + bounded_ns.to_s() + " speedup_milli=" + speedup_milli.to_s()
