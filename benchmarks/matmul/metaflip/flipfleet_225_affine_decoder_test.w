use flipfleet_225_affine_decoder_lib

-> ff225adt_expect(label, condition) (String bool) i64
  if !condition
    << "FAIL " + label
    exit(1)
  1

us = i64[700]
vs = i64[700]
ws = i64[700]
build_meta = i64[4]
count = ff225ad_build_archive32(us, vs, ws, build_meta) ## i64
z = ff225adt_expect("archive32 dictionary", count == 625 && build_meta[0] == 55 && build_meta[2] == 32) ## i64
words = (count + 63) / 64 ## i64
base = i64[words]
z = ff225adt_expect("rank18 anchor mask", ff225ad_anchor_mask(us, vs, ws, count, base) == 1 && ff225ad_weight(base, 0, words) == 18)
basis = i64[count * words]
elimination = i64[5]
dimension = ffran_build_nullspace(us, vs, ws, count, 2, 2, 5, basis, elimination) ## i64
z = ff225adt_expect("full tensor-column kernel", elimination[2] == 212 && dimension == 413 && elimination[2] + dimension == count)
row = 0 ## i64
while row < dimension
  z = ff225adt_expect("natural basis relation " + row.to_s(), ffran_relation_exact(us, vs, ws, count, 2, 2, 5, basis, row * words) == 1)
  row += 1
pair_meta = i64[8]
pair_best = ff225ad_scan_pairs(base, basis, dimension, words, pair_meta) ## i64
z = ff225adt_expect("radius two baseline", pair_best == 18 && pair_meta[0] == 85491 && pair_meta[7] == 184)
pool = i64[8192 * words]
pool_meta = i64[4]
pool_count = ff225ad_build_sparse_pool(basis, dimension, words, 16, pool, 8192, pool_meta) ## i64
z = ff225adt_expect("sparse relation pool", pool_count == 2746 && pool_meta[0] == 413 && pool_meta[1] == 2333 && pool_meta[3] == 0)
origins = i64[37 * words]
origin_count = ff225ad_build_origins(us, vs, ws, count, origins, words) ## i64
z = ff225adt_expect("rank18 origins", origin_count == 37)
origin = 0 ## i64
while origin < origin_count
  z = ff225adt_expect("origin weight " + origin.to_s(), ff225ad_weight(origins, origin * words, words) == 18)
  scheme = ff225ad_materialize(us, vs, ws, count, origins, 18)
  if origin > 0
    copy = i64[words]
    zz = ffnd_copy(origins, origin * words, copy, 0, words) ## i64
    scheme = ff225ad_materialize(us, vs, ws, count, copy, 18)
  z = ff225adt_expect("origin exact " + origin.to_s(), scheme != nil && scheme.rank() == 18)
  origin += 1

random_basis = i64[count * words]
free_coordinates = i64[count]
random_meta = i64[5]
random_dimension = ff225ad_random_systematic_basis(us, vs, ws, count, 771225, random_basis, free_coordinates, random_meta) ## i64
z = ff225adt_expect("random systematic basis", random_dimension == 413 && random_meta[0] == 212 && random_meta[4] == 0)
seen_free = i32[count]
row = 0
while row < random_dimension
  coordinate = free_coordinates[row] ## i64
  z = ff225adt_expect("free coordinate bounds", coordinate >= 0 && coordinate < count)
  z = ff225adt_expect("free coordinate unique", seen_free[coordinate] == 0)
  seen_free[coordinate] = 1
  if row % 31 == 0
    z = ff225adt_expect("random exact relation " + row.to_s(), ffran_relation_exact(us, vs, ws, count, 2, 2, 5, random_basis, row * words) == 1)
  row += 1
systematic = i64[words]
systematic_weight = ff225ad_systematic_origin(base, random_basis, free_coordinates, random_dimension, words, systematic) ## i64
z = ff225adt_expect("Prange origin weight", systematic_weight > 0 && systematic_weight <= 212)
systematic_scheme = ff225ad_materialize(us, vs, ws, count, systematic, count)
z = ff225adt_expect("Prange origin exact", systematic_scheme != nil && systematic_scheme.rank() == systematic_weight)

args = argv()
if args.size() > 0
  metal_source = read_file(args[0])
  z = ff225adt_expect("Metal source", metal_source != nil && metal_source.include?("kernel void ff225ad_triple_weight") && metal_source.include?("kernel void ff225ad_band_walk"))
  device = metal_device()
  library = metal_compile_source(device, metal_source)
  queue = metal_queue(device)
  z = ff225adt_expect("Metal library", library != nil && queue != nil)

  # Planted [3,2] affine code. Columns zero and one have the same syndrome,
  # so relation 011 preserves syndrome while 111 descends to the planted 100.
  planted_origins = i64[1]
  planted_origins[0] = 7
  planted_generators = i64[1]
  planted_generators[0] = 3
  planted_out = i64[1]
  planted_meta = i64[8]
  planted_best = ff225ad_band_gpu(device, library, queue, planted_origins, 1, planted_generators, 1, 1, 32, 4, 3, 17, 16, planted_out, planted_meta) ## i64
  z = ff225adt_expect("planted band decode", planted_best == 1 && planted_out[0] == 4 && planted_meta[7] == 1)

  # A planted triple-only improvement also validates the GPU SWAR popcount
  # and deterministic two-pass winner protocol.
  triple_base = i64[1]
  triple_base[0] = 23
  triple_basis = i64[3]
  triple_basis[0] = 9
  triple_basis[1] = 10
  triple_basis[2] = 12
  triple_indices = i64[3]
  triple_meta = i64[6]
  triple_best = ff225ad_scan_triples_gpu(device, library, queue, triple_base, triple_basis, 3, 1, triple_indices, triple_meta) ## i64
  z = ff225adt_expect("planted triple decode", triple_best == 2 && triple_indices[0] == 0 && triple_indices[1] == 1 && triple_indices[2] == 2 && triple_meta[1] == 1)

<< "PASS flipfleet 225 affine decoder union=" + count.to_s() + " rank=" + elimination[2].to_s() + " dimension=" + dimension.to_s() + " pool=" + pool_count.to_s() + " systematic_weight=" + systematic_weight.to_s()
