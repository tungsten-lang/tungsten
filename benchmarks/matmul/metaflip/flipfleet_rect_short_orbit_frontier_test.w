use flipfleet_rect_archive_nullspace

-> ffrsoft_expect(label, condition) i64
  if condition == false || condition == 0
    << "FAIL " + label
    exit(1)
  1

root = "benchmarks/matmul/metaflip/"
d628 = ffbc_load_exact(root + "matmul_4x4x5_rank60_d628_gl_frontier_gf2.txt", 4, 4, 5, 128)
d655 = ffbc_load_exact(root + "matmul_4x4x5_rank60_d655_global_isotropy_gf2.txt", 4, 4, 5, 128)
d662 = ffbc_load_exact(root + "matmul_4x4x5_rank60_d662_short_orbit_splice_gf2.txt", 4, 4, 5, 128)
d919 = ffbc_load_exact(root + "matmul_4x4x5_rank60_d919_gf2.txt", 4, 4, 5, 128)
z = ffrsoft_expect("frontiers load exact", d628 != nil && d655 != nil && d662 != nil && d919 != nil && ffbc_verify_exact(d628) == 1 && ffbc_verify_exact(d655) == 1 && ffbc_verify_exact(d662) == 1 && ffbc_verify_exact(d919) == 1)

# Replay the exact short-word tunnel selected by the bounded scout.  The scout
# enumerates logical seed 683 with two generators by feeding this mixed seed
# to the deterministic sparse-image constructor.
image_seed = 683 * 104729 + 2 * 65537 ## i64
image = fflc_sparse_leaf_image(d655, image_seed, 2)
z = ffrsoft_expect("two-generator image", image != nil && image.rank() == 60 && fflc_density(image) == 685 && ffbc_verify_exact(image) == 1)
if image != nil
  z = ffrsoft_expect("image distances", fflc_term_set_distance(image, d628) == 118 && fflc_term_set_distance(image, d919) == 120)

splice_meta = i64[9]
splice = ffran_crossover(d628, image, 4096, splice_meta)
z = ffrsoft_expect("nullity-three splice", splice != nil && splice_meta[0] == 118 && splice_meta[1] == 3 && splice_meta[2] == 115 && splice_meta[6] == 57 && splice_meta[7] == 57 && splice_meta[8] == 1)
if splice != nil
  z = ffrsoft_expect("splice endpoint", splice.rank() == 60 && fflc_density(splice) == 679 && fflc_term_set_distance(splice, d628) == 114 && fflc_term_set_distance(splice, d919) == 120 && ffbc_verify_exact(splice) == 1)
  continuation_meta = i64[9]
  continuation_child = ffran_crossover(splice, d662, 4096, continuation_meta)
  z = ffrsoft_expect("walk endpoint relation audit", continuation_child != nil && continuation_meta[0] == 20 && continuation_meta[1] == 5 && continuation_meta[2] == 15)

z = ffrsoft_expect("d662 checked-in endpoint", d662.rank() == 60 && fflc_density(d662) == 662 && fflc_equal_factor_pairs(d662) == 12 && ffbc_verify_exact(d662) == 1)
z = ffrsoft_expect("d662 basin distances", fflc_term_set_distance(d662, d628) == 106 && fflc_term_set_distance(d662, d919) == 120)

audit_628 = i64[9]
audit_919 = i64[9]
miss_628 = ffran_crossover(d662, d628, 4096, audit_628)
miss_919 = ffran_crossover(d662, d919, 4096, audit_919)
z = ffrsoft_expect("d662 independent from d628", miss_628 == nil && audit_628[0] == 106 && audit_628[1] == 1 && audit_628[2] == 105)
z = ffrsoft_expect("d662 independent from d919", miss_919 == nil && audit_919[0] == 120 && audit_919[1] == 1 && audit_919[2] == 119)

<< "PASS flipfleet rectangular short-orbit frontier"
