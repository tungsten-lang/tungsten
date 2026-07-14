use metaflip_worker
use flipfleet_escape
use flipfleet_kxor_pool_lib

-> ffx_test_expect(name, condition)
  if !condition
    << "FAIL " + name
    exit(1)

epoch_command = ffx_epoch_command("/repo", "/tmp/kxor", "/tmp/seed", "/tmp/out", 7, 6, 2, 32, 2, 9)
ffx_test_expect("cached epoch command", epoch_command.ends_with?(" '/tmp/kxor.metallib'"))

-> ffx_test_primitive_fixture(composite, n) (i64 i64) i64
  count = 5 ## i64
  if composite != 0
    count = 6
  us = i64[count]
  vs = i64[count]
  ws = i64[count]
  indices = i64[count]
  i = 0 ## i64
  while i < count
    indices[i] = i
    vs[i] = 7
    ws[i] = 9
    i += 1
  us[0] = 1
  us[1] = 2
  us[2] = 4
  us[3] = 8
  us[4] = 15
  if composite != 0
    # Replace the primitive five set by two three-term splits.
    us[0] = 1
    us[1] = 2
    us[2] = 3
    us[3] = 4
    us[4] = 8
    us[5] = 12
  ffx_primitive_zero(us, vs, ws, indices, count, n)

n = 3 ## i64
cap = ffw_default_capacity(n) ## i64
size = ffw_state_size(cap) ## i64
base = i64[size]
rank = ffw_init_naive_cap(base, n, cap, 17, 0, 1, 1, 1) ## i64
ffx_test_expect("naive", rank == 27 && ffw_verify_best_exact(base, n) == 1)
us = i64[cap]
vs = i64[cap]
ws = i64[cap]
z = ffw_export_best(base, us, vs, ws) ## i64
meta = i64[8]
escaped_rank = ffe_split_with_part(us, vs, ws, rank, cap, 0, 0, 3, meta) ## i64
escaped = i64[size]
loaded = ffw_init_terms_cap(escaped, us, vs, ws, escaped_rank, n, cap, 19, 0, 1, 1, 1) ## i64
ffx_test_expect("escaped", loaded == 28 && ffw_verify_best_exact(escaped, n) == 1)
seed_path = "/tmp/ffx_planted_seed.txt"
z = ffw_dump_best(escaped, seed_path)

out6 = "/tmp/ffx_planted_6to5.txt"
hit6 = ffx_search(seed_path, out6, n, 6, 28, 32, 2, 0, "benchmarks/matmul/metaflip/flipfleet_kxor_pool_test.metal") ## i64
ffx_test_expect("6to5 hit", hit6 == 27)
check6 = i64[size]
z = ffw_load_scheme_cap(check6, out6, n, cap, 23, 0, 1, 1, 1)
ffx_test_expect("6to5 exact", ffw_best_rank(check6) == 27 && ffw_verify_best_exact(check6, n) == 1)

out7 = "/tmp/ffx_planted_7to6.txt"
hit7 = ffx_search(seed_path, out7, n, 7, 28, 32, 2, 0, "benchmarks/matmul/metaflip/flipfleet_kxor_pool_test.metal") ## i64
ffx_test_expect("7to6 hit", hit7 == 27)
check7 = i64[size]
z = ffw_load_scheme_cap(check7, out7, n, cap, 29, 0, 1, 1, 1)
ffx_test_expect("7to6 exact", ffw_best_rank(check7) == 27 && ffw_verify_best_exact(check7, n) == 1)

# The large-k lane is enabled only after both halves of the staged extension
# pass planted end-to-end Metal regressions.  The rank-28 seed contains one
# split identity; an 8- or 9-term local piece can therefore be replaced by the
# merged parent plus its untouched terms.
out8 = "/tmp/ffx_planted_8to7.txt"
hit8 = ffx_search(seed_path, out8, n, 8, 40, 16, 2, 0, "benchmarks/matmul/metaflip/flipfleet_kxor_pool_test.metal") ## i64
ffx_test_expect("8to7 hit", hit8 == 27)
check8 = i64[size]
z = ffw_load_scheme_cap(check8, out8, n, cap, 31, 0, 1, 1, 1)
ffx_test_expect("8to7 exact", ffw_best_rank(check8) == 27 && ffw_verify_best_exact(check8, n) == 1)

out9 = "/tmp/ffx_planted_9to8.txt"
hit9 = ffx_search(seed_path, out9, n, 9, 40, 16, 2, 0, "benchmarks/matmul/metaflip/flipfleet_kxor_pool_test.metal") ## i64
ffx_test_expect("9to8 hit", hit9 == 27)
check9 = i64[size]
z = ffw_load_scheme_cap(check9, out9, n, cap, 37, 0, 1, 1, 1)
ffx_test_expect("9to8 exact", ffw_best_rank(check9) == 27 && ffw_verify_best_exact(check9, n) == 1)

# Plant a genuine five-element tensor circuit: the U masks XOR to zero while
# V and W are fixed.  No proper subset of 1,2,4,8,15 XORs to zero.
circuit_u = i64[cap]
circuit_v = i64[cap]
circuit_w = i64[cap]
circuit_rank = ffw_export_best(base, circuit_u, circuit_v, circuit_w) ## i64
identity_u = [1, 2, 4, 8, 15]
i = 0 ## i64
while i < 5
  circuit_rank = ffm_toggle_plain(circuit_u, circuit_v, circuit_w, circuit_rank, cap, identity_u[i], 3, 5)
  i += 1
ffx_test_expect("planted five rank", circuit_rank == 32)
ffx_test_expect("planted five primitive", ffx_test_primitive_fixture(0, n) == 1)
ffx_test_expect("composite six rejected", ffx_test_primitive_fixture(1, n) == 0)
circuit_state = i64[size]
loaded = ffw_init_terms_cap(circuit_state, circuit_u, circuit_v, circuit_w, circuit_rank, n, cap, 41, 0, 1, 1, 1)
ffx_test_expect("planted five exact seed", loaded == 32 && ffw_verify_best_exact(circuit_state, n) == 1)
circuit_seed = "/tmp/ffx_planted_primitive5_seed.txt"
z = ffw_dump_best(circuit_state, circuit_seed)
circuit_out = "/tmp/ffx_planted_primitive5_out.txt"
circuit_hit = ffx_search(circuit_seed, circuit_out, n, 5, 2, 16, 1, 28, "benchmarks/matmul/metaflip/flipfleet_kxor_pool_test.metal") ## i64
ffx_test_expect("primitive five GPU hit", circuit_hit == 27)
circuit_check = i64[size]
z = ffw_load_scheme_cap(circuit_check, circuit_out, n, cap, 43, 0, 1, 1, 1)
ffx_test_expect("primitive five output exact", ffw_best_rank(circuit_check) == 27 && ffw_verify_best_exact(circuit_check, n) == 1)

<< "flipfleet_kxor_pool_test: all planted checks passed"
