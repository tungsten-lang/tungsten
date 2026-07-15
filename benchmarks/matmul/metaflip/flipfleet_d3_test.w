use metaflip_worker
use flipfleet_d3

-> d3_expect(name, condition)
  if !condition
    << "FAIL " + name
    exit(1)
  1

n = 6 ## i64
cap = ffw_default_capacity(n) ## i64
size = ffw_state_size(cap) ## i64
state = i64[size]
rank = ffw_load_scheme_cap(state, ffd3_seed_path(n), n, cap, 73001, 4, 2, 1000, 250) ## i64
z = d3_expect("6x6 supported", ffd3_supported(6) == 1 && ffd3_supported(5) == 0) ## i64
z = d3_expect("rank-153 seed loads exactly", rank == 153 && ffw_verify_best_exact(state, n) == 1)

us = i64[cap]
vs = i64[cap]
ws = i64[cap]
exported = ffw_export_best(state, us, vs, ws) ## i64
z = d3_expect("rank-153 seed is C3 x Z2 closed", exported == rank && ffd3_is_closed(us, vs, ws, rank, n) == 1)
z = d3_expect("closed seed has zero reflection defect", ffd3_z2_defect(us, vs, ws, rank, n) == 0)

sample = us[0] ## i64
z = d3_expect("reverse is an involution", ffd3_reverse_mask(ffd3_reverse_mask(sample, n), n) == sample)
z = d3_expect("reverse commutes with transpose", ffd3_reverse_mask(ffe_transpose(sample, n), n) == ffe_transpose(ffd3_reverse_mask(sample, n), n))

# A generic term normally has six distinct images.  A diagonal cube has a
# smaller set orbit, and toggling it twice must still be the identity.
generic_u = 1 ## i64
generic_v = 2 ## i64
generic_w = 4 ## i64
z = d3_expect("generic orbit has six images", ffd3_orbit_size(generic_u, generic_v, generic_w, n) == 6)
cube = 1 << 7 ## i64
small_orbit = ffd3_orbit_size(cube, cube, ffe_transpose(cube, n), n) ## i64
z = d3_expect("set orbit deduplicates stabilizers", small_orbit >= 1 && small_orbit < 6)

before_rank = rank ## i64
toggled_rank = ffd3_toggle_orbit(us, vs, ws, rank, cap, generic_u, generic_v, generic_w, n) ## i64
z = d3_expect("orbit toggle remains closed", toggled_rank >= 0 && ffd3_is_closed(us, vs, ws, toggled_rank, n) == 1)
restored_rank = ffd3_toggle_orbit(us, vs, ws, toggled_rank, cap, generic_u, generic_v, generic_w, n) ## i64
z = d3_expect("orbit toggle is an involution", restored_rank == before_rank && ffd3_is_closed(us, vs, ws, restored_rank, n) == 1)

# An ordinary one-axis split is the deliberate symmetry-breaking control: it
# preserves the tensor exactly but must leave the six-image quotient.
meta = i64[8]
broken_rank = ffe_break(us, vs, ws, restored_rank, cap, n, 0, 0, meta) ## i64
z = d3_expect("fixed-cube split is eligible", broken_rank > 0 && meta[7] == 1)
broken = i64[size]
loaded = ffw_init_terms_cap(broken, us, vs, ws, broken_rank, n, cap, 73003, 4, 2, 1000, 250) ## i64
z = d3_expect("broken seed remains exact", loaded == broken_rank && ffw_verify_best_exact(broken, n) == 1)
z = d3_expect("broken seed leaves D3", ffd3_is_closed(us, vs, ws, broken_rank, n) == 0 && ffd3_z2_defect(us, vs, ws, broken_rank, n) > 0)

<< "flipfleet_d3_test: all checks passed"
