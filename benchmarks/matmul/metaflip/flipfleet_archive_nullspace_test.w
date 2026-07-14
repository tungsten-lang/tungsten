use metaflip_worker
use flipfleet_archive_nullspace

-> ffndt_expect(name, condition)
  if !condition
    << "FAIL " + name
    exit(1)

-> ffndt_append_circuit(base_u, base_v, base_w, base_rank, capacity, circuit_u, shared_v, shared_w, out_u, out_v, out_w) (i64[] i64[] i64[] i64 i64 i64[] i64 i64 i64[] i64[] i64[]) i64
  i = 0 ## i64
  while i < base_rank
    out_u[i] = base_u[i]
    out_v[i] = base_v[i]
    out_w[i] = base_w[i]
    i += 1
  rank = base_rank ## i64
  i = 0
  while i < circuit_u.size()
    rank = ffnd_toggle_plain(out_u, out_v, out_w, rank, capacity, circuit_u[i], shared_v, shared_w)
    i += 1
  rank

n = 3 ## i64
cap = ffw_default_capacity(n) ## i64
size = ffw_state_size(cap) ## i64
base = i64[size]
base_rank = ffw_init_naive_cap(base, n, cap, 211, 0, 1, 1, 1) ## i64
ffndt_expect("naive base exact", base_rank == 27 && ffw_verify_current_exact(base, n) == 1)
base_u = i64[cap]
base_v = i64[cap]
base_w = i64[cap]
z = ffw_export_current(base, base_u, base_v, base_w) ## i64

# The parents carry independent five-term zero circuits.  Their ten-column
# archive difference has exact nullity two.  Removing A's circuit yields the
# rank-27 common core, a third state distinct from both parents.
au = i64[cap]
av = i64[cap]
aw = i64[cap]
bu = i64[cap]
bv = i64[cap]
bw = i64[cap]
circuit_a = i64[5]
circuit_a[0] = 1
circuit_a[1] = 2
circuit_a[2] = 4
circuit_a[3] = 8
circuit_a[4] = 15
circuit_b = i64[5]
circuit_b[0] = 16
circuit_b[1] = 32
circuit_b[2] = 64
circuit_b[3] = 128
circuit_b[4] = 240
arank = ffndt_append_circuit(base_u, base_v, base_w, base_rank, cap, circuit_a, 3, 5, au, av, aw) ## i64
brank = ffndt_append_circuit(base_u, base_v, base_w, base_rank, cap, circuit_b, 6, 10, bu, bv, bw) ## i64
parent_a = i64[size]
parent_b = i64[size]
loaded_a = ffw_init_terms_cap(parent_a, au, av, aw, arank, n, cap, 223, 0, 1, 1, 1) ## i64
loaded_b = ffw_init_terms_cap(parent_b, bu, bv, bw, brank, n, cap, 227, 0, 1, 1, 1) ## i64
ffndt_expect("archive parents exact", loaded_a == 32 && loaded_b == 32 && ffw_verify_current_exact(parent_a, n) == 1 && ffw_verify_current_exact(parent_b, n) == 1)

du = i64[64]
dv = i64[64]
dw = i64[64]
owners = i64[64]
dcount = ffnd_build_difference(au, av, aw, arank, bu, bv, bw, brank, du, dv, dw, owners) ## i64
ffndt_expect("symmetric difference exact size", dcount == 10)
from_a = 0 ## i64
from_b = 0 ## i64
i = 0 ## i64
while i < dcount
  if owners[i] == 0
    from_a += 1
  if owners[i] == 1
    from_b += 1
  i += 1
ffndt_expect("difference ownership", from_a == 5 && from_b == 5)

combo_words = ffnd_combo_words(dcount) ## i64
basis = i64[dcount * combo_words]
elim_meta = i64[5]
nullity = ffnd_build_nullspace(du, dv, dw, dcount, n, basis, elim_meta) ## i64
ffndt_expect("exact nullity", nullity == 2 && elim_meta[2] == 8)
i = 0
while i < nullity
  ffndt_expect("basis relation exact " + i.to_s(), ffnd_relation_exact(du, dv, dw, dcount, n, basis, i * combo_words) == 1)
  i += 1

# One combination is already enough because elimination encounters A's zero
# circuit before B's.  This explicitly exercises the bounded scorer rather
# than relying only on exhaustive enumeration.
relation = i64[combo_words]
select_meta = i64[6]
projected = ffnd_select_hybrid(basis, nullity, dcount, owners, arank, 1, relation, select_meta) ## i64
ffndt_expect("bounded scorer finds rank drop", projected == 27 && select_meta[0] == 1 && select_meta[3] == 5 && select_meta[4] == 0)
ffndt_expect("selected relation independently exact", ffnd_relation_exact(du, dv, dw, dcount, n, relation, 0) == 1)

# Corrupting one selected column is detected by the complete bitset checker.
selected_index = 0 ## i64
while selected_index < dcount && ffnd_mask_bit(relation, 0, selected_index) == 0
  selected_index += 1
saved_u = du[selected_index] ## i64
du[selected_index] = du[selected_index] ^ 256
ffndt_expect("corrupted relation rejected", ffnd_relation_exact(du, dv, dw, dcount, n, relation, 0) == 0)
du[selected_index] = saved_u

out_u = i64[cap]
out_v = i64[cap]
out_w = i64[cap]
cross_meta = i64[9]
child_rank = ffnd_crossover_states(parent_a, parent_b, n, 64, 64, out_u, out_v, out_w, cross_meta) ## i64
ffndt_expect("crossover materializes best hybrid", child_rank == 27 && cross_meta[0] == 10 && cross_meta[1] == 2 && cross_meta[8] == 1)
child = i64[size]
loaded_child = ffw_init_terms_cap(child, out_u, out_v, out_w, child_rank, n, cap, 229, 0, 1, 1, 1) ## i64
ffndt_expect("hybrid full tensor exact", loaded_child == 27 && ffw_verify_current_exact(child, n) == 1)

# Identical parents and a difference containing only one full parent circuit
# have no proper nullspace hybrid and miss cleanly.
miss_identical = ffnd_crossover_states(parent_a, parent_a, n, 64, 64, out_u, out_v, out_w, cross_meta) ## i64
ffndt_expect("identical parents clean miss", miss_identical == 0)
miss_single = ffnd_crossover_states(parent_a, base, n, 64, 64, out_u, out_v, out_w, cross_meta) ## i64
ffndt_expect("single full-difference relation rejected", miss_single == 0)

# Real archive evidence: the distance-1155 and distance-1168 rank-93 5x5
# records differ in only sixteen terms.  Their exact difference has nullity
# three, and the scorer constructs a third rank-93 decomposition by taking six
# exclusive terms from each side.  Its density is not better (1165), but it is
# a genuine new basin seed obtained from production records rather than a
# planted identity.
n5 = 5 ## i64
cap5 = ffw_default_capacity(n5) ## i64
size5 = ffw_state_size(cap5) ## i64
real_a = i64[size5]
real_b = i64[size5]
real_arank = ffw_load_scheme_cap(real_a, "benchmarks/matmul/metaflip/matmul_5x5_rank93_d1155_gf2.txt", n5, cap5, 311, 0, 1, 1, 1) ## i64
real_brank = ffw_load_scheme_cap(real_b, "benchmarks/matmul/metaflip/matmul_5x5_rank93_d1168_gf2.txt", n5, cap5, 313, 0, 1, 1, 1) ## i64
ffndt_expect("real 5x5 parents exact", real_arank == 93 && real_brank == 93)
real_u = i64[cap5]
real_v = i64[cap5]
real_w = i64[cap5]
real_meta = i64[9]
real_hit = ffnd_crossover_states(real_a, real_b, n5, 256, 20000, real_u, real_v, real_w, real_meta) ## i64
ffndt_expect("real archive nullspace hybrid", real_hit == 93 && real_meta[0] == 16 && real_meta[1] == 3 && real_meta[6] == 6 && real_meta[7] == 6 && real_meta[8] == 1)
real_child = i64[size5]
real_loaded = ffw_init_terms_cap(real_child, real_u, real_v, real_w, real_hit, n5, cap5, 317, 0, 1, 1, 1) ## i64
real_density = ffw_view_bits(real_child, real_child[47], real_child[48], real_child[49], 0 - 1, real_loaded) ## i64
ffndt_expect("real hybrid density regression", real_loaded == 93 && real_density == 1165 && ffw_verify_current_exact(real_child, n5) == 1)

<< "flipfleet_archive_nullspace_test: all checks passed"
