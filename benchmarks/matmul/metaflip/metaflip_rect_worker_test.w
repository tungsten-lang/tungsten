use metaflip_rect_worker

-> ffr_expect(name, condition)
  if !condition
    << "FAIL " + name
    exit(1)
  1

# The original composition leaves initialize and exhaustively verify.
cap334 = ffr_default_capacity(3, 3, 4) ## i64
st334 = i64[ffr_state_size(cap334)]
r334 = ffr_init_naive_cap(st334, 3, 3, 4, cap334, 17, 4, 3, 1000, 250) ## i64
z = ffr_expect("334 naive rank", r334 == 36)
z = ffr_expect("334 shape", ffr_shape_n(st334) == 3 && ffr_shape_m(st334) == 3 && ffr_shape_p(st334) == 4)
z = ffr_expect("334 best exact", ffr_verify_best_exact(st334, 3, 3, 4) == 1)

cap344 = ffr_default_capacity(3, 4, 4) ## i64
st344 = i64[ffr_state_size(cap344)]
r344 = ffr_init_naive_cap(st344, 3, 4, 4, cap344, 23, 4, 3, 1000, 250) ## i64
z = ffr_expect("344 naive rank", r344 == 48)
z = ffr_expect("344 widths", ffr_u_width(st344) == 12 && ffr_v_width(st344) == 16 && ffr_w_width(st344) == 12)
z = ffr_expect("344 best exact", ffr_verify_best_exact(st344, 3, 4, 4) == 1)

# The small characteristic-sensitive campaign uses n=2 in the shared state
# envelope while retaining independent rectangular widths and exact gates.
cap234 = ffr_default_capacity(2, 3, 4) ## i64
st234 = i64[ffr_state_size(cap234)]
r234 = ffr_init_naive_cap(st234, 2, 3, 4, cap234, 27, 4, 3, 1000, 250) ## i64
z = ffr_expect("234 naive rank", r234 == 24)
z = ffr_expect("234 widths", ffr_u_width(st234) == 6 && ffr_v_width(st234) == 12 && ffr_w_width(st234) == 8)
z = ffr_expect("234 naive exact", ffr_verify_best_exact(st234, 2, 3, 4) == 1)
record234 = i64[ffr_state_size(cap234)]
rr234 = ffr_load_scheme_cap(record234, ffrp_seed_rel(2, 3, 4), 2, 3, 4, cap234, 28, 4, 3, 1000, 250) ## i64
z = ffr_expect("234 record rank", rr234 == 20)
z = ffr_expect("234 record density", ffr_best_bits(record234) == 130)
z = ffr_expect("234 record exact", ffr_verify_best_exact(record234, 2, 3, 4) == 1)
z = ffr_walk(record234, 2000)
z = ffr_expect("234 walk current exact", ffr_verify_current_exact(record234, 2, 3, 4) == 1)
z = ffr_expect("234 walk best exact", ffr_verify_best_exact(record234, 2, 3, 4) == 1)

cap245 = ffr_default_capacity(2, 4, 5) ## i64
st245 = i64[ffr_state_size(cap245)]
r245 = ffr_init_naive_cap(st245, 2, 4, 5, cap245, 29, 4, 3, 1000, 250) ## i64
z = ffr_expect("245 naive rank", r245 == 40)
z = ffr_expect("245 widths", ffr_u_width(st245) == 8 && ffr_v_width(st245) == 20 && ffr_w_width(st245) == 10)
z = ffr_expect("245 naive exact", ffr_verify_best_exact(st245, 2, 4, 5) == 1)
record245 = i64[ffr_state_size(cap245)]
rr245 = ffr_load_scheme_cap(record245, ffrp_seed_rel(2, 4, 5), 2, 4, 5, cap245, 31, 4, 3, 1000, 250) ## i64
z = ffr_expect("245 record rank", rr245 == 33)
z = ffr_expect("245 record density", ffr_best_bits(record245) == 222)
z = ffr_expect("245 record exact", ffr_verify_best_exact(record245, 2, 4, 5) == 1)
z = ffr_walk(record245, 2000)
z = ffr_expect("245 walk current exact", ffr_verify_current_exact(record245, 2, 4, 5) == 1)
z = ffr_expect("245 walk best exact", ffr_verify_best_exact(record245, 2, 4, 5) == 1)

cap256 = ffr_default_capacity(2, 5, 6) ## i64
st256 = i64[ffr_state_size(cap256)]
r256 = ffr_init_naive_cap(st256, 2, 5, 6, cap256, 33, 4, 3, 1000, 250) ## i64
z = ffr_expect("256 naive rank", r256 == 60)
z = ffr_expect("256 widths", ffr_u_width(st256) == 10 && ffr_v_width(st256) == 30 && ffr_w_width(st256) == 12)
z = ffr_expect("256 naive exact", ffr_verify_best_exact(st256, 2, 5, 6) == 1)
record256 = i64[ffr_state_size(cap256)]
rr256 = ffr_load_scheme_cap(record256, ffrp_seed_rel(2, 5, 6), 2, 5, 6, cap256, 35, 4, 3, 1000, 250) ## i64
z = ffr_expect("256 record rank", rr256 == 47)
z = ffr_expect("256 record density", ffr_best_bits(record256) == 438)
z = ffr_expect("256 record exact", ffr_verify_best_exact(record256, 2, 5, 6) == 1)
z = ffr_walk(record256, 2000)
z = ffr_expect("256 walk current exact", ffr_verify_current_exact(record256, 2, 5, 6) == 1)
z = ffr_expect("256 walk best exact", ffr_verify_best_exact(record256, 2, 5, 6) == 1)

# Axis-specific splits never leak bits outside nm/mp/np.
i = 0 ## i64
while i < 200
  z = ffr_try_split(st334)
  i += 1
z = ffr_expect("334 split current exact", ffr_verify_current_exact(st334, 3, 3, 4) == 1)

# A short mixed walk preserves both the live tensor and the gated best.
z = ffr_walk(st344, 5000)
z = ffr_expect("344 walk current exact", ffr_verify_current_exact(st344, 3, 4, 4) == 1)
z = ffr_expect("344 walk best exact", ffr_verify_best_exact(st344, 3, 4, 4) == 1)

# The two record components consumed by a 7x7 campaign are checked through
# the same exhaustive import path used for returned GPU candidates.
record334 = i64[ffr_state_size(cap334)]
rr334 = ffr_load_scheme_cap(record334, "benchmarks/matmul/metaflip/matmul_3x3x4_rank29_gf2.txt", 3, 3, 4, cap334, 51, 4, 3, 1000, 250) ## i64
z = ffr_expect("334 record rank", rr334 == 29)
z = ffr_expect("334 record density", ffr_best_bits(record334) == 204)
z = ffr_expect("334 record exact", ffr_verify_best_exact(record334, 3, 3, 4) == 1)
record344 = i64[ffr_state_size(cap344)]
rr344 = ffr_load_scheme_cap(record344, "benchmarks/matmul/metaflip/matmul_3x4x4_rank38_gf2.txt", 3, 4, 4, cap344, 57, 4, 3, 1000, 250) ## i64
z = ffr_expect("344 record rank", rr344 == 38)
z = ffr_expect("344 record density", ffr_best_bits(record344) == 282)
z = ffr_expect("344 record exact", ffr_verify_best_exact(record344, 3, 4, 4) == 1)

cap335 = ffr_default_capacity(3, 3, 5) ## i64
record335 = i64[ffr_state_size(cap335)]
rr335 = ffr_load_scheme_cap(record335, ffrp_seed_rel(3, 3, 5), 3, 3, 5, cap335, 59, 4, 3, 1000, 250) ## i64
z = ffr_expect("335 record rank", rr335 == 36)
z = ffr_expect("335 widths", ffr_u_width(record335) == 9 && ffr_v_width(record335) == 15 && ffr_w_width(record335) == 15)
z = ffr_expect("335 record density", ffr_best_bits(record335) == 287)
z = ffr_expect("335 record exact", ffr_verify_best_exact(record335, 3, 3, 5) == 1)
prior335 = i64[ffr_state_size(cap335)]
prior335_rank = ffr_load_scheme_cap(prior335, "benchmarks/matmul/metaflip/matmul_3x3x5_rank36_d304_gf2.txt", 3, 3, 5, cap335, 6001, 4, 3, 1000, 250) ## i64
z = ffr_expect("335 prior rank", prior335_rank == 36)
z = ffr_expect("335 prior density", ffr_best_bits(prior335) == 304)
z = ffr_expect("335 prior exact", ffr_verify_best_exact(prior335, 3, 3, 5) == 1)
imported335 = i64[ffr_state_size(cap335)]
imported335_rank = ffr_load_scheme_cap(imported335, "benchmarks/matmul/metaflip/matmul_3x3x5_rank36_gf2.txt", 3, 3, 5, cap335, 60, 4, 3, 1000, 250) ## i64
z = ffr_expect("335 imported rank", imported335_rank == 36)
z = ffr_expect("335 imported density", ffr_best_bits(imported335) == 317)
z = ffr_expect("335 imported exact", ffr_verify_best_exact(imported335, 3, 3, 5) == 1)

cap345 = ffr_default_capacity(3, 4, 5) ## i64
record345 = i64[ffr_state_size(cap345)]
rr345 = ffr_load_scheme_cap(record345, ffrp_seed_rel(3, 4, 5), 3, 4, 5, cap345, 63, 4, 3, 1000, 250) ## i64
z = ffr_expect("345 record rank", rr345 == 47)
z = ffr_expect("345 widths", ffr_u_width(record345) == 12 && ffr_v_width(record345) == 20 && ffr_w_width(record345) == 15)
z = ffr_expect("345 record density", ffr_best_bits(record345) == 386)
z = ffr_expect("345 record exact", ffr_verify_best_exact(record345, 3, 4, 5) == 1)
imported345 = i64[ffr_state_size(cap345)]
imported345_rank = ffr_load_scheme_cap(imported345, "benchmarks/matmul/metaflip/matmul_3x4x5_rank47_gf2.txt", 3, 4, 5, cap345, 64, 4, 3, 1000, 250) ## i64
z = ffr_expect("345 imported rank", imported345_rank == 47)
z = ffr_expect("345 imported density", ffr_best_bits(imported345) == 396)
z = ffr_expect("345 imported exact", ffr_verify_best_exact(imported345, 3, 4, 5) == 1)

cap346 = ffr_default_capacity(3, 4, 6) ## i64
record346 = i64[ffr_state_size(cap346)]
rr346 = ffr_load_scheme_cap(record346, ffrp_seed_rel(3, 4, 6), 3, 4, 6, cap346, 641, 4, 3, 1000, 250) ## i64
z = ffr_expect("346 record rank", rr346 == 54)
z = ffr_expect("346 widths", ffr_u_width(record346) == 12 && ffr_v_width(record346) == 24 && ffr_w_width(record346) == 18)
z = ffr_expect("346 record density", ffr_best_bits(record346) == 488)
z = ffr_expect("346 record exact", ffr_verify_best_exact(record346, 3, 4, 6) == 1)

cap355 = ffr_default_capacity(3, 5, 5) ## i64
record355 = i64[ffr_state_size(cap355)]
rr355 = ffr_load_scheme_cap(record355, ffrp_seed_rel(3, 5, 5), 3, 5, 5, cap355, 65, 4, 3, 1000, 250) ## i64
z = ffr_expect("355 record rank", rr355 == 58)
z = ffr_expect("355 widths", ffr_u_width(record355) == 15 && ffr_v_width(record355) == 25 && ffr_w_width(record355) == 15)
z = ffr_expect("355 record density", ffr_best_bits(record355) == 518)
z = ffr_expect("355 record exact", ffr_verify_best_exact(record355, 3, 5, 5) == 1)
imported355 = i64[ffr_state_size(cap355)]
imported355_rank = ffr_load_scheme_cap(imported355, "benchmarks/matmul/metaflip/matmul_3x5x5_rank58_gf2.txt", 3, 5, 5, cap355, 66, 4, 3, 1000, 250) ## i64
z = ffr_expect("355 imported rank", imported355_rank == 58)
z = ffr_expect("355 imported density", ffr_best_bits(imported355) == 544)
z = ffr_expect("355 imported exact", ffr_verify_best_exact(imported355, 3, 5, 5) == 1)

# High-leverage rectangular campaign frontiers use the same generic loader,
# independent factor widths, and exhaustive tensor gate.
cap445 = ffr_default_capacity(4, 4, 5) ## i64
record445 = i64[ffr_state_size(cap445)]
rr445 = ffr_load_scheme_cap(record445, ffrp_seed_rel(4, 4, 5), 4, 4, 5, cap445, 61, 4, 3, 1000, 250) ## i64
z = ffr_expect("445 record rank", rr445 == 60)
z = ffr_expect("445 widths", ffr_u_width(record445) == 16 && ffr_v_width(record445) == 20 && ffr_w_width(record445) == 20)
z = ffr_expect("445 record density", ffr_best_bits(record445) == 628)
z = ffr_expect("445 record exact", ffr_verify_best_exact(record445, 4, 4, 5) == 1)

cap455 = ffr_default_capacity(4, 5, 5) ## i64
record455 = i64[ffr_state_size(cap455)]
rr455 = ffr_load_scheme_cap(record455, "benchmarks/matmul/metaflip/matmul_4x5x5_rank76_gf2.txt", 4, 5, 5, cap455, 67, 4, 3, 1000, 250) ## i64
z = ffr_expect("455 record rank", rr455 == 76)
z = ffr_expect("455 record density", ffr_best_bits(record455) == 700)
z = ffr_expect("455 record exact", ffr_verify_best_exact(record455, 4, 5, 5) == 1)

cap446 = ffr_default_capacity(4, 4, 6) ## i64
record446 = i64[ffr_state_size(cap446)]
rr446 = ffr_load_scheme_cap(record446, "benchmarks/matmul/metaflip/matmul_4x4x6_rank73_gf2.txt", 4, 4, 6, cap446, 71, 4, 3, 1000, 250) ## i64
z = ffr_expect("446 record rank", rr446 == 73)
z = ffr_expect("446 widths", ffr_u_width(record446) == 16 && ffr_v_width(record446) == 24 && ffr_w_width(record446) == 24)
z = ffr_expect("446 record density", ffr_best_bits(record446) == 704)
z = ffr_expect("446 record exact", ffr_verify_best_exact(record446, 4, 4, 6) == 1)

cap456 = ffr_default_capacity(4, 5, 6) ## i64
record456 = i64[ffr_state_size(cap456)]
rr456 = ffr_load_scheme_cap(record456, ffrp_seed_rel(4, 5, 6), 4, 5, 6, cap456, 72, 4, 3, 1000, 250) ## i64
z = ffr_expect("456 record rank", rr456 == 90)
z = ffr_expect("456 widths", ffr_u_width(record456) == 20 && ffr_v_width(record456) == 30 && ffr_w_width(record456) == 24)
z = ffr_expect("456 record density", ffr_best_bits(record456) == 907)
z = ffr_expect("456 record exact", ffr_verify_best_exact(record456, 4, 5, 6) == 1)

# The highest-leverage audited leaf remains inside the shared-i64 envelope.
# Exercise exact catalog import and a real mixed CPU walk; no GPU geometry is
# implied by admitting the profile.
cap457 = ffr_default_capacity(4, 5, 7) ## i64
record457 = i64[ffr_state_size(cap457)]
rr457 = ffr_load_scheme_cap(record457, ffrp_seed_rel(4, 5, 7), 4, 5, 7, cap457, 73, 4, 3, 1000, 250) ## i64
z = ffr_expect("457 record rank", rr457 == 104)
z = ffr_expect("457 widths", ffr_u_width(record457) == 20 && ffr_v_width(record457) == 35 && ffr_w_width(record457) == 28)
z = ffr_expect("457 record density", ffr_best_bits(record457) == 1089)
z = ffr_expect("457 record exact", ffr_verify_best_exact(record457, 4, 5, 7) == 1)
catalog457 = i64[ffr_state_size(cap457)]
catalog457_rank = ffr_load_scheme_cap(catalog457, "benchmarks/matmul/metaflip/matmul_4x5x7_rank104_catalog_gf2.txt", 4, 5, 7, cap457, 74, 4, 3, 1000, 250) ## i64
z = ffr_expect("457 catalog rank", catalog457_rank == 104)
z = ffr_expect("457 catalog density", ffr_best_bits(catalog457) == 1163)
z = ffr_expect("457 catalog exact", ffr_verify_best_exact(catalog457, 4, 5, 7) == 1)
z = ffr_walk(record457, 2000)
z = ffr_expect("457 walk current exact", ffr_verify_current_exact(record457, 4, 5, 7) == 1)
z = ffr_expect("457 walk best exact", ffr_verify_best_exact(record457, 4, 5, 7) == 1)

# The next two audited composition leaves fit the same packed-i64 worker.
# Admission is CPU-only until a dimension-specialized Metal source exists.
cap467 = ffr_default_capacity(4, 6, 7) ## i64
record467 = i64[ffr_state_size(cap467)]
rr467 = ffr_load_scheme_cap(record467, ffrp_seed_rel(4, 6, 7), 4, 6, 7, cap467, 75, 4, 3, 1000, 250) ## i64
z = ffr_expect("467 record rank got=" + rr467.to_s(), rr467 == 123)
z = ffr_expect("467 widths", ffr_u_width(record467) == 24 && ffr_v_width(record467) == 42 && ffr_w_width(record467) == 28)
z = ffr_expect("467 record density", ffr_best_bits(record467) == 1406)
z = ffr_expect("467 record exact", ffr_verify_best_exact(record467, 4, 6, 7) == 1)

cap567 = ffr_default_capacity(5, 6, 7) ## i64
record567 = i64[ffr_state_size(cap567)]
rr567 = ffr_load_scheme_cap(record567, ffrp_seed_rel(5, 6, 7), 5, 6, 7, cap567, 76, 4, 3, 1000, 250) ## i64
z = ffr_expect("567 record rank got=" + rr567.to_s(), rr567 == 150)
z = ffr_expect("567 widths", ffr_u_width(record567) == 30 && ffr_v_width(record567) == 42 && ffr_w_width(record567) == 35)
z = ffr_expect("567 record density", ffr_best_bits(record567) == 1875)
z = ffr_expect("567 record exact", ffr_verify_best_exact(record567, 5, 6, 7) == 1)

# The next sensitivity tranche remains within the signed-i64 factor envelope.
# Each seed is independently reconstructed here; GPU capability stays zero.
cap347 = ffr_default_capacity(3, 4, 7) ## i64
record347 = i64[ffr_state_size(cap347)]
rr347 = ffr_load_scheme_cap(record347, ffrp_seed_rel(3, 4, 7), 3, 4, 7, cap347, 77, 4, 3, 1000, 250) ## i64
z = ffr_expect("347 record rank", rr347 == 64)
z = ffr_expect("347 widths", ffr_u_width(record347) == 12 && ffr_v_width(record347) == 28 && ffr_w_width(record347) == 21)
z = ffr_expect("347 record density leader", ffr_best_bits(record347) == 519)
z = ffr_expect("347 record exact", ffr_verify_best_exact(record347, 3, 4, 7) == 1)

cap356 = ffr_default_capacity(3, 5, 6) ## i64
record356 = i64[ffr_state_size(cap356)]
rr356 = ffr_load_scheme_cap(record356, ffrp_seed_rel(3, 5, 6), 3, 5, 6, cap356, 78, 4, 3, 1000, 250) ## i64
z = ffr_expect("356 record rank", rr356 == 68)
z = ffr_expect("356 widths", ffr_u_width(record356) == 15 && ffr_v_width(record356) == 30 && ffr_w_width(record356) == 18)
z = ffr_expect("356 record density", ffr_best_bits(record356) == 634)
z = ffr_expect("356 record exact", ffr_verify_best_exact(record356, 3, 5, 6) == 1)

cap357 = ffr_default_capacity(3, 5, 7) ## i64
record357 = i64[ffr_state_size(cap357)]
rr357 = ffr_load_scheme_cap(record357, ffrp_seed_rel(3, 5, 7), 3, 5, 7, cap357, 79, 4, 3, 1000, 250) ## i64
z = ffr_expect("357 record rank", rr357 == 79)
z = ffr_expect("357 widths", ffr_u_width(record357) == 15 && ffr_v_width(record357) == 35 && ffr_w_width(record357) == 21)
z = ffr_expect("357 record density leader", ffr_best_bits(record357) == 699)
z = ffr_expect("357 record exact", ffr_verify_best_exact(record357, 3, 5, 7) == 1)

cap458 = ffr_default_capacity(4, 5, 8) ## i64
record458 = i64[ffr_state_size(cap458)]
rr458 = ffr_load_scheme_cap(record458, ffrp_seed_rel(4, 5, 8), 4, 5, 8, cap458, 80, 4, 3, 1000, 250) ## i64
z = ffr_expect("458 record rank", rr458 == 118)
z = ffr_expect("458 widths", ffr_u_width(record458) == 20 && ffr_v_width(record458) == 40 && ffr_w_width(record458) == 32)
z = ffr_expect("458 record density leader", ffr_best_bits(record458) == 1283)
z = ffr_expect("458 record exact", ffr_verify_best_exact(record458, 4, 5, 8) == 1)

cap466 = ffr_default_capacity(4, 6, 6) ## i64
record466 = i64[ffr_state_size(cap466)]
rr466 = ffr_load_scheme_cap(record466, ffrp_seed_rel(4, 6, 6), 4, 6, 6, cap466, 81, 4, 3, 1000, 250) ## i64
z = ffr_expect("466 record rank", rr466 == 105)
z = ffr_expect("466 widths", ffr_u_width(record466) == 24 && ffr_v_width(record466) == 36 && ffr_w_width(record466) == 24)
z = ffr_expect("466 record density leader", ffr_best_bits(record466) == 1197)
z = ffr_expect("466 record exact", ffr_verify_best_exact(record466, 4, 6, 6) == 1)

cap468 = ffr_default_capacity(4, 6, 8) ## i64
record468 = i64[ffr_state_size(cap468)]
rr468 = ffr_load_scheme_cap(record468, ffrp_seed_rel(4, 6, 8), 4, 6, 8, cap468, 82, 4, 3, 1000, 250) ## i64
z = ffr_expect("468 record rank", rr468 == 140)
z = ffr_expect("468 widths", ffr_u_width(record468) == 24 && ffr_v_width(record468) == 48 && ffr_w_width(record468) == 32)
z = ffr_expect("468 record density leader", ffr_best_bits(record468) == 1560)
z = ffr_expect("468 record exact", ffr_verify_best_exact(record468, 4, 6, 8) == 1)

# The finite campaign policy guarantees a real work phase and a real
# wander/split phase for every possible RNG-selected starting band.  This is
# deliberately an engine-level test rather than a CLI-output assertion.
campaign_moves = 10000 ## i64
phase_moves = i64[3]
z = ffrp_campaign_budgets(campaign_moves, phase_moves)
band_seed = 100 ## i64
while band_seed < 104
  campaign445 = i64[ffr_state_size(cap445)]
  cr445 = ffr_load_scheme_cap(campaign445, ffrp_seed_rel(4, 4, 5), 4, 4, 5, cap445, band_seed, 4, 3, ffrp_work_quota(campaign_moves), ffrp_wander_quota(campaign_moves)) ## i64
  z = ffr_expect("445 campaign seed", cr445 == 60)
  z = ffr_work(campaign445, phase_moves[0])
  z = ffr_walk(campaign445, phase_moves[1])
  z = ffr_wander(campaign445, phase_moves[2])
  z = ffr_expect("445 campaign move budget", ffw_moves(campaign445) == campaign_moves)
  z = ffr_expect("445 campaign work phase", ffw_work_moves(campaign445) > 0)
  z = ffr_expect("445 campaign wander phase", ffw_wander_moves(campaign445) > 0)
  z = ffr_expect("445 campaign split attempts", ffw_split_attempts(campaign445) > 0)
  z = ffr_expect("445 campaign split acceptance", ffw_split_accepted(campaign445) > 0)
  z = ffr_expect("445 campaign current exact", ffr_verify_current_exact(campaign445, 4, 4, 5) == 1)
  z = ffr_expect("445 campaign best exact", ffr_verify_best_exact(campaign445, 4, 4, 5) == 1)
  band_seed += 1

# Standard seed files round-trip through the exhaustive import gate.
tmp = "/tmp/metaflip_rect_worker_334.txt"
z = ffr_expect("334 dump", ffr_dump_best(st334, tmp) == ffw_best_rank(st334))
loaded = i64[ffr_state_size(cap334)]
lr = ffr_load_scheme_cap(loaded, tmp, 3, 3, 4, cap334, 31, 4, 3, 1000, 250) ## i64
z = ffr_expect("334 reload rank", lr == ffw_best_rank(st334))
z = ffr_expect("334 reload exact", ffr_verify_best_exact(loaded, 3, 3, 4) == 1)

# Structural masks and tensor shape are independently checked.
us = i64[36]
vs = i64[36]
ws = i64[36]
z = ffw_export_best(st334, us, vs, ws)
us[0] = us[0] | (1 << 9)
bad = i64[ffr_state_size(cap334)]
br = ffr_init_terms_cap(bad, us, vs, ws, 36, 3, 3, 4, cap334, 41, 4, 3, 1000, 250) ## i64
z = ffr_expect("334 rejects high u bit", br < 0)
z = ffr_expect("only profiled formats", ffr_supported(4, 3, 4) == 0 && ffr_supported(3, 3, 3) == 0 && ffr_supported(2, 3, 4) == 1 && ffr_supported(2, 4, 5) == 1 && ffr_supported(3, 4, 6) == 1 && ffr_supported(3, 4, 7) == 1 && ffr_supported(3, 5, 6) == 1 && ffr_supported(3, 5, 7) == 1 && ffr_supported(4, 5, 6) == 1 && ffr_supported(4, 5, 7) == 1 && ffr_supported(4, 5, 8) == 1 && ffr_supported(4, 6, 6) == 1 && ffr_supported(4, 6, 7) == 1 && ffr_supported(4, 6, 8) == 1 && ffr_supported(5, 6, 7) == 1)

<< "PASS metaflip rectangular worker"
