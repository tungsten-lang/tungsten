use metaflip_worker
use flipfleet_span_refactor
use flipfleet_span_refactor_pool_lib

-> ffsrp_test_expect(name, condition)
  if !condition
    << "FAIL " + name
    exit(1)
  1

-> ffsrp_test_move(name, su, sv, sw, k, want, device, library, queue) i64
  capacity = ffsr_max_candidates(k) ## i64
  cu = i64[capacity]
  cv = i64[capacity]
  cw = i64[capacity]
  signatures = i64[capacity]
  originals = i64[4]
  meta = i64[12]
  count = ffsr_build_candidates(su, sv, sw, k, cu, cv, cw, signatures, originals, meta) ## i64
  z = ffsrp_test_expect(name + " candidates", count > 0) ## i64
  ids = i64[4]
  stats = i64[6]
  found = ffsrp_find_ids_gpu(device, library, queue, signatures, count, meta[5], originals, k, want, ids, stats) ## i64
  z = ffsrp_test_expect(name + " GPU exact join", found == want && stats[5] == want)
  out_u = i64[4]
  out_v = i64[4]
  out_w = i64[4]
  made = ffsr_materialize_ids(cu, cv, cw, count, ids, found, out_u, out_v, out_w) ## i64
  z = ffsrp_test_expect(name + " materialized", made == want)
  z = ffsrp_test_expect(name + " exact identity", ffsr_verify_local_replacement(su, sv, sw, k, out_u, out_v, out_w, made) == 1)
  if k == want
    z = ffsrp_test_expect(name + " unchanged set rejected", ffsr_terms_same_set(su, sv, sw, k, out_u, out_v, out_w, made) == 0)
  found

args = argv()
metal_path = "benchmarks/matmul/metaflip/flipfleet_span_refactor_pool_test.metal"
metallib_path = ""
if args.size() > 0
  metal_path = args[0]
if args.size() > 1
  metallib_path = args[1]
device = metal_device()
library = nil
if metallib_path != ""
  library = metal_load_library(device, metallib_path)
if library == nil
  source = read_file(metal_path)
  z = ffsrp_test_expect("generated Metal source", source != nil)
  library = metal_compile_source(device, source)
queue = metal_queue(device)

# 3 -> 2: merge a planted U split while retaining a third term.
su32 = [1, 2, 4, 0]
sv32 = [4, 4, 2, 0]
sw32 = [8, 8, 1, 0]
z = ffsrp_test_expect("3->2 planted", ffsrp_test_move("3->2", su32, sv32, sw32, 3, 2, device, library, queue) == 2)

# 3 <-> 3: shared-U flip plus an unrelated third term.
su33 = [1, 1, 4, 0]
sv33 = [1, 2, 4, 0]
sw33 = [1, 2, 4, 0]
z = ffsrp_test_expect("3<->3 planted", ffsrp_test_move("3<->3", su33, sv33, sw33, 3, 3, device, library, queue) == 3)

# 3 -> 4: split a selected term inside its complete U span.
su34 = [3, 1, 4, 0]
sv34 = [4, 2, 1, 0]
sw34 = [8, 1, 2, 0]
z = ffsrp_test_expect("3->4 planted", ffsrp_test_move("3->4", su34, sv34, sw34, 3, 4, device, library, queue) == 4)

# 4 -> 3: reverse a planted U split with two retained terms.
su43 = [1, 2, 4, 8]
sv43 = [4, 4, 2, 1]
sw43 = [8, 8, 1, 2]
z = ffsrp_test_expect("4->3 planted", ffsrp_test_move("4->3", su43, sv43, sw43, 4, 3, device, library, queue) == 3)

# 4 <-> 4: same-rank exact pair/pair join, not an original permutation.
su44 = [1, 1, 2, 4]
sv44 = [1, 2, 4, 1]
sw44 = [1, 2, 4, 8]
z = ffsrp_test_expect("4<->4 planted", ffsrp_test_move("4<->4", su44, sv44, sw44, 4, 4, device, library, queue) == 4)

# Real 5x5 distance-six triangle shear from the rank-93 scheme.  All three
# old terms change; no compatible two-term flip can explain this refactor.
n5 = 5 ## i64
cap5 = ffw_default_capacity(n5) ## i64
state5 = i64[ffw_state_size(cap5)]
rank5 = ffw_load_scheme_cap(state5, "benchmarks/matmul/metaflip/matmul_5x5_rank93_d1155_gf2.txt", n5, cap5, 424243, 0, 1, 1, 1) ## i64
z = ffsrp_test_expect("real 5x5 seed", rank5 == 93 && ffw_verify_current_exact(state5, n5) == 1)
all5_u = i64[cap5]
all5_v = i64[cap5]
all5_w = i64[cap5]
count5 = ffw_export_current(state5, all5_u, all5_v, all5_w) ## i64
old5_u = i64[3]
old5_v = i64[3]
old5_w = i64[3]
old5_u[0] = 524288
old5_v[0] = 5406720
old5_w[0] = 32768
old5_u[1] = 11337728
old5_v[1] = 168965
old5_w[1] = 32768
old5_u[2] = 16777216
old5_v[2] = 5248005
old5_w[2] = 1048577
selected5 = i64[4]
i = 0
while i < 3
  selected5[i] = ffsr_find_candidate_term(all5_u, all5_v, all5_w, count5, old5_u[i], old5_v[i], old5_w[i])
  i += 1
z = ffsrp_test_expect("real 5x5 triangle terms located", selected5[0] >= 0 && selected5[1] >= 0 && selected5[2] >= 0)
stats5 = i64[6]
out5 = "/tmp/flipfleet_span_refactor_pool_test_5x5.txt"
hit5 = ffsrp_search_current_subset(device, library, queue, state5, selected5, n5, 3, 3, out5, stats5) ## i64
z = ffsrp_test_expect("real 5x5 GPU triangle shear", hit5 == 93 && ffw_verify_current_exact(state5, n5) == 1)

# The pair table retains duplicate signatures rather than coalescing them.
dup_sigs = metal_array(64, 16)
dup_codes = metal_array(32, 16) ## u32[]
z = ffsrp_test_expect("duplicate insert one", ffsrp_insert(dup_sigs, dup_codes, 16, 123456789, 7) == 1)
z = ffsrp_test_expect("duplicate insert two", ffsrp_insert(dup_sigs, dup_codes, 16, 123456789, 9) == 1)
seen7 = 0 ## i64
seen9 = 0 ## i64
i = 0 ## i64
while i < 16
  if dup_codes[i] == 8
    seen7 = 1
  if dup_codes[i] == 10
    seen9 = 1
  i += 1
z = ffsrp_test_expect("duplicate signatures preserved", seen7 == 1 && seen9 == 1)
z = ffsrp_test_expect("worst table memory bound", ffsrp_open_capacity(5693625) == 8388608)

# Cheap selector for the real distance-six family: terms 0 and 1 share W and
# their V factors XOR to term 2's V.  The GPU still proves the replacement.
motif_u = i64[3]
motif_v = i64[3]
motif_w = i64[3]
motif_u[0] = 1
motif_u[1] = 2
motif_u[2] = 4
motif_v[0] = 1
motif_v[1] = 2
motif_v[2] = 3
motif_w[0] = 8
motif_w[1] = 8
motif_w[2] = 16
motif_selected = i64[4]
motif_found = ffsrp_choose_shear_triple(motif_u, motif_v, motif_w, 3, 0, motif_selected) ## i64
z = ffsrp_test_expect("triangle-shear selector", motif_found == 3 && motif_selected[0] == 0 && motif_selected[1] == 1 && motif_selected[2] == 2)

# End-to-end full-tensor gate: split one term of the exact rank-23 3x3 scheme,
# select both children plus one live term, and let the GPU recover rank 23.
n = 3 ## i64
cap = ffw_default_capacity(n) ## i64
state_size = ffw_state_size(cap) ## i64
base = i64[state_size]
base_rank = ffw_load_scheme_cap(base, "benchmarks/matmul/metaflip/matmul_3x3_rank23_d139_gf2.txt", n, cap, 101, 0, 1, 1, 1) ## i64
z = ffsrp_test_expect("rank-23 exact base", base_rank == 23 && ffw_verify_current_exact(base, n) == 1)
base_u = i64[cap]
base_v = i64[cap]
base_w = i64[cap]
exported = ffw_export_current(base, base_u, base_v, base_w) ## i64
split_index = 0 - 1 ## i64
i = 0
while i < exported && split_index < 0
  if ffw_popcount(base_u[i]) >= 2
    split_index = i
  i += 1
z = ffsrp_test_expect("base has splittable term", split_index >= 0)
shoulder_u = i64[cap]
shoulder_v = i64[cap]
shoulder_w = i64[cap]
shoulder_rank = 0 ## i64
i = 0
while i < exported
  if i != split_index
    shoulder_u[shoulder_rank] = base_u[i]
    shoulder_v[shoulder_rank] = base_v[i]
    shoulder_w[shoulder_rank] = base_w[i]
    shoulder_rank += 1
  i += 1
part = base_u[split_index] & (0 - base_u[split_index]) ## i64
rest = base_u[split_index] ^ part ## i64
shoulder_u[shoulder_rank] = part
shoulder_v[shoulder_rank] = base_v[split_index]
shoulder_w[shoulder_rank] = base_w[split_index]
shoulder_rank += 1
shoulder_u[shoulder_rank] = rest
shoulder_v[shoulder_rank] = base_v[split_index]
shoulder_w[shoulder_rank] = base_w[split_index]
shoulder_rank += 1
shoulder = i64[state_size]
loaded = ffw_init_terms_cap(shoulder, shoulder_u, shoulder_v, shoulder_w, shoulder_rank, n, cap, 103, 0, 1, 1, 1) ## i64
z = ffsrp_test_expect("rank-24 planted shoulder", loaded == 24 && ffw_verify_current_exact(shoulder, n) == 1)
live_u = i64[cap]
live_v = i64[cap]
live_w = i64[cap]
live_rank = ffw_export_current(shoulder, live_u, live_v, live_w) ## i64
child_one = ffsr_find_candidate_term(live_u, live_v, live_w, live_rank, part, base_v[split_index], base_w[split_index]) ## i64
child_two = ffsr_find_candidate_term(live_u, live_v, live_w, live_rank, rest, base_v[split_index], base_w[split_index]) ## i64
retained = 0 ## i64
if retained == child_one || retained == child_two
  retained = 1
z = ffsrp_test_expect("planted children located", child_one >= 0 && child_two >= 0 && child_one != child_two && retained != child_one && retained != child_two)
selected = i64[4]
selected[0] = child_one
selected[1] = child_two
selected[2] = retained
output_path = "/tmp/flipfleet_span_refactor_pool_test_out.txt"
stats = i64[6]
hit = ffsrp_search_current_subset(device, library, queue, shoulder, selected, n, 3, 2, output_path, stats) ## i64
z = ffsrp_test_expect("GPU splice reaches rank 23", hit == 23 && ffw_verify_current_exact(shoulder, n) == 1)
check = i64[state_size]
reloaded = ffw_load_scheme_cap(check, output_path, n, cap, 107, 0, 1, 1, 1) ## i64
z = ffsrp_test_expect("serialized output full-tensor exact", reloaded == 23 && ffw_verify_current_exact(check, n) == 1)

<< "flipfleet_span_refactor_pool_test: all planted GPU checks passed"
