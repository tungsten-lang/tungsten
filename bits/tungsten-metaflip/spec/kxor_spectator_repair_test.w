use ../lib/metaflip/strategies/kxor_spectator_repair

-> ffkst_expect(label, condition) (String bool) i64
  if condition == false
    << "FAIL kxor spectator repair: " + label
    exit(1)
  1

-> ffkst_position(st, u, v, w) (i64[] i64 i64 i64) i64
  position = 0 ## i64
  while position < st[6]
    slot = st[st[50] + position] ## i64
    if st[st[44] + slot] == u && st[st[45] + slot] == v && st[st[46] + slot] == w
      return position
    position += 1
  0 - 1

root = __DIR__ + "/../lib/metaflip/seeds/gf2/"
n = 2 ## i64
capacity = ffw_default_capacity(n) ## i64
base = i64[ffw_state_size(capacity)]
base_rank = ffw_load_scheme_cap(base, root + "matmul_2x2_rank7_strassen_gf2.txt", n, capacity, 99101, 0, 1, 1, 1) ## i64
z = ffkst_expect("Strassen source", base_rank == 7 && ffw_verify_current_exact(base, n) == 1) ## i64
base_u = i64[capacity]
base_v = i64[capacity]
base_w = i64[capacity]
z = ffw_export_current(base, base_u, base_v, base_w)

# Tensor factorization is exact, not a fingerprint test.
words = ffks_tensor_words(n) ## i64
tensor = i64[words]
factors = i64[3]
z = ffks_xor_outer(tensor, 9, 10, 12, n)
z = ffkst_expect("rank-one factorization", ffks_factor_rank_one(tensor, n, factors) == 1 && factors[0] == 9 && factors[1] == 10 && factors[2] == 12)
z = ffks_xor_outer(tensor, 1, 1, 1, n)
z = ffkst_expect("two-box adversary rejected", ffks_factor_rank_one(tensor, n, factors) == 0)

# Positive rank-one repair.  Split Strassen term (9,9,9) along U into
# (1,9,9)+(8,9,9).  The proposed 2->1 replacement keeps an unrelated selected
# term unchanged, hence misses by (1,9,9).  Spectator (8,9,9) turns that
# residual into the original rank-one term (9,9,9), recovering rank seven.
split_u = i64[capacity]
split_v = i64[capacity]
split_w = i64[capacity]
split_rank = 0 ## i64
i = 0 ## i64
while i < base_rank
  if i != 0
    split_u[split_rank] = base_u[i]
    split_v[split_rank] = base_v[i]
    split_w[split_rank] = base_w[i]
    split_rank += 1
  i += 1
split_u[split_rank] = 1
split_v[split_rank] = 9
split_w[split_rank] = 9
split_rank += 1
split_u[split_rank] = 8
split_v[split_rank] = 9
split_w[split_rank] = 9
split_rank += 1
split = i64[ffw_state_size(capacity)]
loaded = ffw_init_terms_cap(split, split_u, split_v, split_w, split_rank, n, capacity, 99103, 0, 1, 1, 1) ## i64
z = ffkst_expect("split shoulder exact", loaded == 8 && ffw_verify_current_exact(split, n) == 1)
child1 = ffkst_position(split, 1, 9, 9) ## i64
child2 = ffkst_position(split, 8, 9, 9) ## i64
unchanged = ffkst_position(split, 12, 1, 12) ## i64
z = ffkst_expect("split positions", child1 >= 0 && child2 >= 0 && unchanged >= 0)
selected = i64[2]
selected[0] = child1
selected[1] = unchanged
replacement_u = i64[1]
replacement_v = i64[1]
replacement_w = i64[1]
replacement_u[0] = 12
replacement_v[0] = 1
replacement_w[0] = 12
repaired = i64[ffw_state_size(capacity)]
meta = i64[12]
hit = ffks_try_repair(split, selected, 2, replacement_u, replacement_v, replacement_w, 1, child2, 1, repaired, capacity, 99107, meta) ## i64
z = ffkst_expect("rank-one spectator closes split", hit == 7 && meta[3] == 1 && meta[4] == 1 && meta[5] == 1)
z = ffkst_expect("repaired scheme fully exact", ffw_verify_current_exact(repaired, n) == 1 && ffw_verify_best_exact(repaired, n) == 1)
z = ffkst_expect("source remains untouched", split[6] == 8 && ffw_verify_current_exact(split, n) == 1)

# Positive zero-residual case and parity-collision materialization.  The four
# terms below are one ordinary shared-U relation, disjoint from Strassen.  The
# candidate replacement is already live, so toggling the exact relation
# removes all four terms and returns directly to rank seven.
zero_u = i64[capacity]
zero_v = i64[capacity]
zero_w = i64[capacity]
i = 0
while i < base_rank
  zero_u[i] = base_u[i]
  zero_v[i] = base_v[i]
  zero_w[i] = base_w[i]
  i += 1
zero_u[7] = 2
zero_v[7] = 1
zero_w[7] = 1
zero_u[8] = 2
zero_v[8] = 2
zero_w[8] = 2
zero_u[9] = 2
zero_v[9] = 1
zero_w[9] = 3
zero_u[10] = 2
zero_v[10] = 3
zero_w[10] = 2
zero = i64[ffw_state_size(capacity)]
loaded = ffw_init_terms_cap(zero, zero_u, zero_v, zero_w, 11, n, capacity, 99109, 0, 1, 1, 1)
z = ffkst_expect("zero-relation shoulder exact", loaded == 11 && ffw_verify_current_exact(zero, n) == 1)
old0 = ffkst_position(zero, 2, 1, 1) ## i64
old1 = ffkst_position(zero, 2, 2, 2) ## i64
zero_spectator = ffkst_position(zero, 2, 1, 3) ## i64
selected[0] = old0
selected[1] = old1
replacement_u[0] = 2
replacement_v[0] = 3
replacement_w[0] = 2
zero_out = i64[ffw_state_size(capacity)]
zero_meta = i64[12]
hit = ffks_try_repair(zero, selected, 2, replacement_u, replacement_v, replacement_w, 1, zero_spectator, 1, zero_out, capacity, 99111, zero_meta)
z = ffkst_expect("zero spectator closes relation", hit == 7 && zero_meta[2] == 1 && zero_meta[3] == 0 && zero_meta[5] == 1)
z = ffkst_expect("zero repair full gate", ffw_verify_current_exact(zero_out, n) == 1 && zero[6] == 11 && ffw_verify_current_exact(zero, n) == 1)

# Adversarial requests cannot alias selected positions or smuggle a zero
# factor.  Both must leave the exact source unchanged and produce no gate.
bad_selected = i64[2]
bad_selected[0] = child1
bad_selected[1] = child1
bad_out = i64[ffw_state_size(capacity)]
bad_meta = i64[12]
hit = ffks_try_repair(split, bad_selected, 2, replacement_u, replacement_v, replacement_w, 1, 0, 8, bad_out, capacity, 99113, bad_meta)
z = ffkst_expect("duplicate selection rejected", hit == 0 && bad_meta[4] == 0 && split[6] == 8)
replacement_u[0] = 0
selected[0] = child1
selected[1] = unchanged
hit = ffks_try_repair(split, selected, 2, replacement_u, replacement_v, replacement_w, 1, 0, 8, bad_out, capacity, 99115, bad_meta)
z = ffkst_expect("zero-factor adversary rejected", hit == 0 && bad_meta[4] == 0 && ffw_verify_current_exact(split, n) == 1)

<< "PASS kxor one-spectator repair rankone=1 zero=1 adversarial=2"
