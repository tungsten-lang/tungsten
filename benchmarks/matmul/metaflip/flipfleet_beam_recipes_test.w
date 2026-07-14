use flipfleet_beam_recipes

-> ffbr_test_expect(name, condition)
  if !condition
    << "FAIL " + name
    exit(1)
  1

-> ffbr_test_naive(us, vs, ws, n) (i64[] i64[] i64[] i64) i64
  rank = 0 ## i64
  i = 0 ## i64
  while i < n
    j = 0 ## i64
    while j < n
      k = 0 ## i64
      while k < n
        us[rank] = 1 << (i * n + j)
        vs[rank] = 1 << (j * n + k)
        ws[rank] = 1 << (i * n + k)
        rank += 1
        k += 1
      j += 1
    i += 1
  rank

n = 3 ## i64
capacity = 64 ## i64
base_u = i64[capacity]
base_v = i64[capacity]
base_w = i64[capacity]
base_rank = ffbr_test_naive(base_u, base_v, base_w, n) ## i64
base_state = i64[ffw_state_size(capacity)]
base_loaded = ffw_init_terms_cap(base_state, base_u, base_v, base_w, base_rank, n, capacity, 44001, 4, 2, 1000, 250) ## i64
z = ffbr_test_expect("naive seed exact", base_loaded == 27 && ffw_verify_current_exact(base_state, n) == 1)

# Hide an orbit-split + generic-split endpoint, then require the actual mixed
# branch enumerator to recover it.
target_u = i64[capacity]
target_v = i64[capacity]
target_w = i64[capacity]
z = ffbr_copy(base_u, base_v, base_w, base_rank, target_u, target_v, target_w) ## i64
first_meta = i64[8]
target_rank = ffe_apply(target_u, target_v, target_w, base_rank, capacity, n, 3, 44018, first_meta) ## i64
second_meta = i64[8]
target_rank = ffe_apply(target_u, target_v, target_w, target_rank, capacity, n, 1, 45027, second_meta)
z = ffbr_test_expect("mixed planted recipe constructed", first_meta[7] == 1 && second_meta[7] == 1 && target_rank > base_rank)
hidden_recipe = i64[2]
recovered = ffbr_find_target2(base_u, base_v, base_w, base_rank, capacity, n, 44001, target_u, target_v, target_w, target_rank, hidden_recipe) ## i64
z = ffbr_test_expect("mixed recipe enumerator recovers endpoint", recovered == target_rank)
z = ffbr_test_expect("recovered recipe is mixed", hidden_recipe[0] != hidden_recipe[1])
target_state = i64[ffw_state_size(capacity)]
target_loaded = ffw_init_terms_cap(target_state, target_u, target_v, target_w, target_rank, n, capacity, 44003, 4, 2, 1000, 250) ## i64
z = ffbr_test_expect("mixed planted endpoint exact", target_loaded == target_rank && ffw_verify_current_exact(target_state, n) == 1)

# Run the actual diversity beam.  It must return a changed exact endpoint and
# a replayable three-kind recipe.
beam_u = i64[capacity]
beam_v = i64[capacity]
beam_w = i64[capacity]
beam_recipe = i64[3]
beam_meta = i64[8]
beam_rank = ffbr_beam_search(base_u, base_v, base_w, base_rank, capacity, n, 3, 8, 55001, beam_u, beam_v, beam_w, beam_recipe, beam_meta) ## i64
z = ffbr_test_expect("beam emits endpoint", beam_rank > 0 && beam_meta[2] > 0)
beam_state = i64[ffw_state_size(capacity)]
beam_loaded = ffw_init_terms_cap(beam_state, beam_u, beam_v, beam_w, beam_rank, n, capacity, 55003, 4, 2, 1000, 250) ## i64
z = ffbr_test_expect("beam endpoint full exact", beam_loaded == beam_rank && ffw_verify_current_exact(beam_state, n) == 1)
z = ffbr_test_expect("beam recipe populated", beam_recipe[0] >= 1 && beam_recipe[0] <= 5 && beam_recipe[2] >= 1 && beam_recipe[2] <= 5)

z = ffbr_test_expect("capacity guard", ffbr_beam_search(base_u, base_v, base_w, base_rank, base_rank, n, 2, 4, 1, beam_u, beam_v, beam_w, beam_recipe, beam_meta) == 0)

<< "flipfleet_beam_recipes_test: all checks passed"
