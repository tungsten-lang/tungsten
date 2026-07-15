use flipfleet_zero_relation_image
use flipfleet_escape

-> ffzrit_expect(label, condition) (String bool) i64
  if !condition
    << "ZERO_RELATION_IMAGE_FAIL " + label
    exit(1)
  1

n = 2 ## i64
capacity = 64 ## i64
state = i64[ffw_state_size(capacity)]
rank = ffw_load_scheme_cap(state, "benchmarks/matmul/metaflip/matmul_2x2_rank7_strassen_gf2.txt", n, capacity, 981001, 0, 1, 1, 1) ## i64
z = ffzrit_expect("Strassen exact", rank == 7 && ffw_verify_current_exact(state, n) == 1) ## i64
base_u = i64[capacity]
base_v = i64[capacity]
base_w = i64[capacity]
z = ffzrit_expect("Strassen export", ffw_export_current(state, base_u, base_v, base_w) == rank)

# A split shoulder supplies an explicit archive relation Z=A XOR B=0.
shoulder_u = i64[capacity]
shoulder_v = i64[capacity]
shoulder_w = i64[capacity]
ffzri_copy(base_u, base_v, base_w, shoulder_u, shoulder_v, shoulder_w, 0, rank)
part = 1 ## i64
if part == shoulder_u[0]
  part = 2
split_meta = i64[8]
shoulder_rank = ffe_split_with_part(shoulder_u, shoulder_v, shoulder_w, rank, capacity, 0, 0, part, split_meta) ## i64
shoulder = i64[ffw_state_size(capacity)]
loaded = ffw_init_terms_cap(shoulder, shoulder_u, shoulder_v, shoulder_w, shoulder_rank, n, capacity, 981003, 0, 1, 1, 1) ## i64
z = ffzrit_expect("split shoulder exact", shoulder_rank == 8 && loaded == 8 && ffw_verify_current_exact(shoulder, n) == 1)

raw_u = i64[capacity * 2]
raw_v = i64[capacity * 2]
raw_w = i64[capacity * 2]
relation_u = i64[capacity * 2]
relation_v = i64[capacity * 2]
relation_w = i64[capacity * 2]
compact_meta = i64[2]
relation_rank = ffzri_relation(base_u, base_v, base_w, rank, shoulder_u, shoulder_v, shoulder_w, shoulder_rank, raw_u, raw_v, raw_w, relation_u, relation_v, relation_w, compact_meta) ## i64
z = ffzrit_expect("split zero relation", relation_rank == 3 && compact_meta[1] == 6)

# Find the first nonidentity raw factor shear whose image relation opens a
# genuine shoulder around Strassen.  The mapped relation is still zero by
# linearity, and toggling the identical image a second time must close it.
image_u = i64[capacity * 2]
image_v = i64[capacity * 2]
image_w = i64[capacity * 2]
leader_u = i64[capacity * 2]
leader_v = i64[capacity * 2]
leader_w = i64[capacity * 2]
chosen_source = 0 - 1 ## i64
chosen_target = 0 - 1 ## i64
leader_rank = 0 ## i64
source = 0 ## i64
while source < n * n && chosen_source < 0
  target = 0 ## i64
  while target < n * n && chosen_source < 0
    if target != source
      image_rank = ffzri_map_relation(relation_u, relation_v, relation_w, relation_rank, 0, 1, source, target, raw_u, raw_v, raw_w, image_u, image_v, image_w, compact_meta) ## i64
      if image_rank > 0
        leader_rank = ffzri_toggle_image(base_u, base_v, base_w, rank, image_u, image_v, image_w, image_rank, raw_u, raw_v, raw_w, leader_u, leader_v, leader_w, compact_meta)
        if leader_rank > rank
          chosen_source = source
          chosen_target = target
    target += 1
  source += 1
z = ffzrit_expect("nonidentity image shoulder found", chosen_source >= 0 && chosen_target >= 0 && leader_rank > rank)
leader = i64[ffw_state_size(capacity)]
loaded = ffw_init_terms_cap(leader, leader_u, leader_v, leader_w, leader_rank, n, capacity, 981007, 0, 1, 1, 1) ## i64
z = ffzrit_expect("image-opened leader exact", loaded == leader_rank && ffw_verify_current_exact(leader, n) == 1)

recovered_u = i64[capacity * 2]
recovered_v = i64[capacity * 2]
recovered_w = i64[capacity * 2]
recovered_rank = ffzri_toggle_image(leader_u, leader_v, leader_w, leader_rank, image_u, image_v, image_w, image_rank, raw_u, raw_v, raw_w, recovered_u, recovered_v, recovered_w, compact_meta) ## i64
recovered = i64[ffw_state_size(capacity)]
loaded = ffw_init_terms_cap(recovered, recovered_u, recovered_v, recovered_w, recovered_rank, n, capacity, 981011, 0, 1, 1, 1) ## i64
z = ffzrit_expect("mapped relation closes rank", recovered_rank == 7 && loaded == 7)
z = ffzrit_expect("mapped relation full gate", ffw_verify_current_exact(recovered, n) == 1)
z = ffzrit_expect("recovered original set", ffpan_term_set_distance_unique(base_u, base_v, base_w, rank, recovered_u, recovered_v, recovered_w, recovered_rank) == 0)

# Finite derivative control: Delta_g Z = Z XOR g(Z) is another, usually much
# smaller zero relation because every g-stable term cancels.  Plant it into a
# second exact shoulder and prove the same derivative closes the shoulder.
derivative_u = i64[capacity * 2]
derivative_v = i64[capacity * 2]
derivative_w = i64[capacity * 2]
derivative_rank = ffzri_relation(relation_u, relation_v, relation_w, relation_rank, image_u, image_v, image_w, image_rank, raw_u, raw_v, raw_w, derivative_u, derivative_v, derivative_w, compact_meta) ## i64
z = ffzrit_expect("nonzero finite derivative", derivative_rank > 0)
z = ffzrit_expect("finite derivative zero tensor", ffzri_zero_tensor(derivative_u, derivative_v, derivative_w, derivative_rank, n) == 1)
derivative_leader_u = i64[capacity * 2]
derivative_leader_v = i64[capacity * 2]
derivative_leader_w = i64[capacity * 2]
derivative_leader_rank = ffzri_toggle_image(base_u, base_v, base_w, rank, derivative_u, derivative_v, derivative_w, derivative_rank, raw_u, raw_v, raw_w, derivative_leader_u, derivative_leader_v, derivative_leader_w, compact_meta) ## i64
z = ffzrit_expect("derivative opens shoulder", derivative_leader_rank > rank)
derivative_leader = i64[ffw_state_size(capacity)]
loaded = ffw_init_terms_cap(derivative_leader, derivative_leader_u, derivative_leader_v, derivative_leader_w, derivative_leader_rank, n, capacity, 981013, 0, 1, 1, 1)
z = ffzrit_expect("derivative shoulder exact", loaded == derivative_leader_rank && ffw_verify_current_exact(derivative_leader, n) == 1)
derivative_recovered_rank = ffzri_toggle_image(derivative_leader_u, derivative_leader_v, derivative_leader_w, derivative_leader_rank, derivative_u, derivative_v, derivative_w, derivative_rank, raw_u, raw_v, raw_w, recovered_u, recovered_v, recovered_w, compact_meta) ## i64
loaded = ffw_init_terms_cap(recovered, recovered_u, recovered_v, recovered_w, derivative_recovered_rank, n, capacity, 981017, 0, 1, 1, 1)
z = ffzrit_expect("derivative closes and gates", derivative_recovered_rank == 7 && loaded == 7 && ffw_verify_current_exact(recovered, n) == 1)

<< "flipfleet_zero_relation_image_test: pass relation=" + relation_rank.to_s() + " image=" + image_rank.to_s() + " derivative=" + derivative_rank.to_s() + " shoulders=" + leader_rank.to_s() + "/" + derivative_leader_rank.to_s() + "->" + recovered_rank.to_s() + " map=U:shear:" + chosen_source.to_s() + ">" + chosen_target.to_s()
