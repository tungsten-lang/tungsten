use metaflip_worker
use flipfleet_escape
use flipfleet_basin_identity

-> ffbi_test_expect(name, condition)
  if condition == false || condition == 0
    << "FAIL " + name
    exit(1)

-> ffbi_reference_matrix_rank(mask, dimension) (i64 i64) i64
  rows = i64[7]
  row_mask = (1 << dimension) - 1 ## i64
  r = 0 ## i64
  while r < dimension
    rows[r] = (mask >> (r * dimension)) & row_mask
    r += 1
  result = 0 ## i64
  col = 0 ## i64
  while col < dimension
    pivot = result ## i64
    while pivot < dimension && ((rows[pivot] >> col) & 1) == 0
      pivot += 1
    if pivot < dimension
      swap = rows[result] ## i64
      rows[result] = rows[pivot]
      rows[pivot] = swap
      r = 0
      while r < dimension
        if r != result && ((rows[r] >> col) & 1) == 1
          rows[r] = rows[r] ^ rows[result]
        r += 1
      result += 1
    col += 1
  result

-> ffbi_reference_transform(u, v, w, dimension, code, reverse, output) (i64 i64 i64 i64 i64 i64 i64[]) i64
  transformed_u = u ## i64
  transformed_v = v ## i64
  transformed_w = w ## i64
  rotations = code % 3 ## i64
  if code >= 3
    transformed_u = ffe_transpose(v, dimension)
    transformed_v = ffe_transpose(u, dimension)
    transformed_w = ffe_transpose(w, dimension)
  r = 0 ## i64
  while r < rotations
    next_u = transformed_v ## i64
    next_v = ffe_transpose(transformed_w, dimension) ## i64
    next_w = ffe_transpose(transformed_u, dimension) ## i64
    transformed_u = next_u
    transformed_v = next_v
    transformed_w = next_w
    r += 1
  if reverse != 0
    transformed_u = ffbi_reverse_factor(transformed_u, dimension)
    transformed_v = ffbi_reverse_factor(transformed_v, dimension)
    transformed_w = ffbi_reverse_factor(transformed_w, dimension)
  output[0] = transformed_u
  output[1] = transformed_v
  output[2] = transformed_w
  1

mask = 0 ## i64
while mask < 512
  ffbi_test_expect("packed 3x3 matrix rank", ffbi_matrix_rank(mask, 3) == ffbi_reference_matrix_rank(mask, 3))
  mask += 1
mask = 0
while mask < 65536
  ffbi_test_expect("packed 4x4 matrix rank", ffbi_matrix_rank(mask, 4) == ffbi_reference_matrix_rank(mask, 4))
  # A stride coprime to 2^16 samples every bit position and rank stratum while
  # keeping the interpreter-mode unit test comfortably short.
  mask += 17
ffbi_test_expect("packed 4x4 full mask", ffbi_matrix_rank(65535, 4) == ffbi_reference_matrix_rank(65535, 4))

n = 3 ## i64
capacity = ffw_default_capacity(n) ## i64
size = ffw_state_size(capacity) ## i64
base = i64[size]
loaded = ffw_load_scheme_cap(base, "benchmarks/matmul/metaflip/matmul_3x3_rank23_d139_gf2.txt", n, capacity, 17, 6, 4, 1000, 250) ## i64
ffbi_test_expect("load exact seed", loaded == 23 && ffw_verify_best_exact(base, n) == 1)

us = i64[capacity]
vs = i64[capacity]
ws = i64[capacity]
rank = ffw_export_best(base, us, vs, ws) ## i64
tu = i64[capacity]
tv = i64[capacity]
tw = i64[capacity]
term = i64[3]
reference_term = i64[3]
i = 0 ## i64
while i < rank
  z = ffbi_transform_term(us[i], vs[i], ws[i], n, 4, 1, term) ## i64
  tu[i] = term[0]
  tv[i] = term[1]
  tw[i] = term[2]
  i += 1

code = 0 ## i64
while code < 6
  reverse = 0 ## i64
  while reverse < 2
    z = ffbi_transform_term(us[0], vs[0], ws[0], n, code, reverse, term) ## i64
    z = ffbi_reference_transform(us[0], vs[0], ws[0], n, code, reverse, reference_term)
    ffbi_test_expect("scalar transform U", reference_term[0] == term[0] && term[0] == ffbi_transform_factor(us[0], vs[0], ws[0], n, code, reverse, 0))
    ffbi_test_expect("scalar transform V", reference_term[1] == term[1] && term[1] == ffbi_transform_factor(us[0], vs[0], ws[0], n, code, reverse, 1))
    ffbi_test_expect("scalar transform W", reference_term[2] == term[2] && term[2] == ffbi_transform_factor(us[0], vs[0], ws[0], n, code, reverse, 2))
    reverse += 1
  code += 1
image = i64[size]
image_rank = ffw_init_terms_cap(image, tu, tv, tw, rank, n, capacity, 19, 6, 4, 1000, 250) ## i64
ffbi_test_expect("D3 reversal image exact", image_rank == rank && ffw_verify_best_exact(image, n) == 1)
ffbi_test_expect("canonical identity agrees", ffbi_best_id(base) == ffbi_best_id(image))
ffbi_test_expect("GL histogram agrees", ffbi_gl_invariant_view(base, 0) == ffbi_gl_invariant_view(image, 0))
ffbi_test_expect("allocation-free C3 agrees", ffbi_state_is_c3(base, n, 0) == ffe_is_c3(us, vs, ws, rank, n))

meta = i64[8]
split_rank = ffe_split(us, vs, ws, rank, capacity, 0, 0, meta) ## i64
split = i64[size]
split_loaded = ffw_init_terms_cap(split, us, vs, ws, split_rank, n, capacity, 23, 6, 4, 1000, 250) ## i64
ffbi_test_expect("split remains exact", split_loaded == split_rank && ffw_verify_best_exact(split, n) == 1)
ffbi_test_expect("different shoulder identity", ffbi_best_id(base) != ffbi_best_id(split))
ffbi_test_expect("current and best initially agree", ffbi_current_id(base) == ffbi_best_id(base))

<< "flipfleet_basin_identity_test: all checks passed"
