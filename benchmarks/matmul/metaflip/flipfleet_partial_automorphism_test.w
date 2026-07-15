use metaflip_worker
use flipfleet_partial_automorphism

-> ffpat_expect(name, condition)
  if !condition
    << "FAIL " + name
    exit(1)

-> ffpat_toggle(us, vs, ws, rank, capacity, u, v, w) (i64[] i64[] i64[] i64 i64 i64 i64 i64) i64
  found = 0 - 1 ## i64
  i = 0 ## i64
  while i < rank && found < 0
    if us[i] == u && vs[i] == v && ws[i] == w
      found = i
    i += 1
  if found >= 0
    us[found] = us[rank - 1]
    vs[found] = vs[rank - 1]
    ws[found] = ws[rank - 1]
    return rank - 1
  if rank >= capacity
    return 0 - 1
  us[rank] = u
  vs[rank] = v
  ws[rank] = w
  rank + 1

n = 3 ## i64
cap = ffw_default_capacity(n) ## i64
size = ffw_state_size(cap) ## i64
base = i64[size]
base_rank = ffw_init_naive_cap(base, n, cap, 101, 0, 1, 1, 1) ## i64
ffpat_expect("naive seed exact", base_rank == 27 && ffw_verify_current_exact(base, n) == 1)

# The elementary I-domain transposition is an involution and its global image
# is independently a matrix-multiplication decomposition.
probe = i64[3]
back = i64[3]
z = ffpa_transform_term(5, 17, 257, n, 0, 0, 1, probe) ## i64
z = ffpa_transform_term(probe[0], probe[1], probe[2], n, 0, 0, 1, back)
ffpat_expect("coordinate automorphism involution", back[0] == 5 && back[1] == 17 && back[2] == 257)

base_u = i64[cap]
base_v = i64[cap]
base_w = i64[cap]
exported = ffw_export_current(base, base_u, base_v, base_w) ## i64
image_u = i64[cap]
image_v = i64[cap]
image_w = i64[cap]
i = 0 ## i64
while i < exported
  z = ffpa_transform_term(base_u[i], base_v[i], base_w[i], n, 0, 0, 1, probe)
  image_u[i] = probe[0]
  image_v[i] = probe[1]
  image_w[i] = probe[2]
  i += 1
image = i64[size]
image_rank = ffw_init_terms_cap(image, image_u, image_v, image_w, exported, n, cap, 103, 0, 1, 1, 1) ## i64
ffpat_expect("global automorphism image exact", image_rank == 27 && ffw_verify_current_exact(image, n) == 1)

# The broader enumerator also contains ordered GL(3,2) transvections.  The
# dual occurrence receives inverse-transpose, so both involution and global
# exactness are independently checked rather than assumed.
z = ffpa_transform_term_kind(5, 17, 257, n, 1, 1, 0, 2, probe) ## i64
z = ffpa_transform_term_kind(probe[0], probe[1], probe[2], n, 1, 1, 0, 2, back)
ffpat_expect("elementary shear involution", back[0] == 5 && back[1] == 17 && back[2] == 257)
i = 0
while i < exported
  z = ffpa_transform_term_kind(base_u[i], base_v[i], base_w[i], n, 1, 1, 0, 2, probe)
  image_u[i] = probe[0]
  image_v[i] = probe[1]
  image_w[i] = probe[2]
  i += 1
shear_image = i64[size]
shear_rank = ffw_init_terms_cap(shear_image, image_u, image_v, image_w, exported, n, cap, 105, 0, 1, 1, 1) ## i64
ffpat_expect("global shear image exact", shear_rank == 27 && ffw_verify_current_exact(shear_image, n) == 1)

# Direct coordinate 3-cycles are tested in both orientations on all three
# contracted index domains.  The opposite orientation is the exact inverse,
# and transforming the complete decomposition must preserve M_3.
cycle_code = ffpa_cycle_code(n, 0, 1, 2) ## i64
ffpat_expect("cycle code accepted", cycle_code >= 0)
domain = 0 ## i64
while domain < 3
  orientation = 0 ## i64
  while orientation < 2
    z = ffpa_transform_term_kind(5, 17, 257, n, 2, domain, cycle_code, orientation, probe)
    z = ffpa_transform_term_kind(probe[0], probe[1], probe[2], n, 2, domain, cycle_code, 1 - orientation, back)
    ffpat_expect("cycle inverse domain " + domain.to_s() + " orientation " + orientation.to_s(), back[0] == 5 && back[1] == 17 && back[2] == 257)
    i = 0
    while i < exported
      z = ffpa_transform_term_kind(base_u[i], base_v[i], base_w[i], n, 2, domain, cycle_code, orientation, probe)
      image_u[i] = probe[0]
      image_v[i] = probe[1]
      image_w[i] = probe[2]
      i += 1
    cycle_image = i64[size]
    cycle_rank = ffw_init_terms_cap(cycle_image, image_u, image_v, image_w, exported, n, cap, 200 + domain * 2 + orientation, 0, 1, 1, 1) ## i64
    ffpat_expect("global cycle exact domain " + domain.to_s() + " orientation " + orientation.to_s(), cycle_rank == 27 && ffw_verify_current_exact(cycle_image, n) == 1)
    orientation += 1
  domain += 1

# Plant a three-term zero circuit with a dense shared V/W pair.  The actual
# enumerator must discover that partially transforming precisely this circuit
# is exact and is not merely an automorphism orbit/no-op.
planted_u = i64[cap]
planted_v = i64[cap]
planted_w = i64[cap]
i = 0
while i < exported
  planted_u[i] = base_u[i]
  planted_v[i] = base_v[i]
  planted_w[i] = base_w[i]
  i += 1
planted_rank = exported ## i64
planted_rank = ffpat_toggle(planted_u, planted_v, planted_w, planted_rank, cap, 3, 3, 5)
planted_rank = ffpat_toggle(planted_u, planted_v, planted_w, planted_rank, cap, 5, 3, 5)
planted_rank = ffpat_toggle(planted_u, planted_v, planted_w, planted_rank, cap, 6, 3, 5)
planted = i64[size]
loaded = ffw_init_terms_cap(planted, planted_u, planted_v, planted_w, planted_rank, n, cap, 107, 0, 1, 1, 1) ## i64
ffpat_expect("planted shoulder exact", loaded == 30 && ffw_verify_current_exact(planted, n) == 1)

# The planted three-term zero circuit remains zero under a direct cycle.  This
# exercises the cycle-specific exact delta solve and application path rather
# than accepting a random exact-gate success.
cycle_selected = i64[4]
cycle_meta = i64[11]
cycle_found = ffpa_enumerate_cycle_terms(planted_u, planted_v, planted_w, planted_rank, n, planted_rank, 0, 3, cycle_selected, cycle_meta) ## i64
ffpat_expect("cycle enumerator recovers planted relation", cycle_found == 3 && cycle_meta[0] == 2 && cycle_meta[10] == 3)
cycle_planted = i64[size]
cycle_loaded = ffw_init_terms_cap(cycle_planted, planted_u, planted_v, planted_w, planted_rank, n, cap, 211, 0, 1, 1, 1) ## i64
cycle_applied = ffpa_apply_current_cycle(cycle_planted, cycle_selected, cycle_found, cycle_meta[1], cycle_meta[2], cycle_meta[3], cycle_meta[4], cycle_meta[5]) ## i64
ffpat_expect("partial cycle splice exact", cycle_loaded == 30 && cycle_applied > 0 && cycle_applied <= 30 && ffw_verify_current_exact(cycle_planted, n) == 1)
cycle_stats = i64[8]
cycle_attempts = ffpa_audit_cycle_terms(planted_u, planted_v, planted_w, planted_rank, n, planted_rank, 0, cycle_stats) ## i64
ffpat_expect("cycle audit covers all domains and orientations", cycle_attempts == 6 && cycle_stats[2] == 6 && cycle_stats[4] > 0)

selected = i64[4]
meta = i64[9]
found = ffpa_enumerate_terms(planted_u, planted_v, planted_w, planted_rank, n, planted_rank, 0, 3, selected, meta) ## i64
ffpat_expect("enumerator recovers planted relation", found == 3)
ffpat_expect("enumerator records real automorphism", meta[0] >= 0 && meta[0] <= 1 && meta[1] >= 0 && meta[1] < 3 && meta[2] >= 0 && meta[2] < n && meta[3] >= 0 && meta[3] < n)

before_u = i64[cap]
before_v = i64[cap]
before_w = i64[cap]
z = ffw_export_current(planted, before_u, before_v, before_w)
applied = ffpa_apply_current_kind(planted, selected, found, meta[0], meta[1], meta[2], meta[3]) ## i64
ffpat_expect("partial automorphism splice exact", applied == 30 && ffw_verify_current_exact(planted, n) == 1)
after_u = i64[cap]
after_v = i64[cap]
after_w = i64[cap]
z = ffw_export_current(planted, after_u, after_v, after_w)
changed = 0 ## i64
i = 0
while i < applied
  if after_u[i] != before_u[i] || after_v[i] != before_v[i] || after_w[i] != before_w[i]
    changed = 1
  i += 1
ffpat_expect("splice changes live term set", changed == 1)

# A random non-relation is rejected before mutation; the globally exact state
# and its rank survive, exercising the rollback/precondition path.
bad = i64[4]
bad[0] = 0
bad[1] = 1
bad[2] = 2
rejected = ffpa_apply_current(planted, bad, 3, 0, 0, 1) ## i64
ffpat_expect("non-relation rejected", rejected < 0)
ffpat_expect("rejection leaves exact state", planted[6] == 30 && ffw_verify_current_exact(planted, n) == 1)

<< "flipfleet_partial_automorphism_test: all checks passed"
