use flipfleet_outer_isotropy

-> ffoist_expect(label, condition)
  if condition != 0
    return 1
  << "FAIL " + label
  exit(1)
  0

root = "benchmarks/matmul/metaflip/"
paths = ["matmul_3x3_rank23_d139_gf2.txt",
         "matmul_3x3x4_rank29_gf2.txt",
         "matmul_3x4x4_rank38_gf2.txt",
         "matmul_4x4_rank47_d450_gf2.txt"]
ns = i64[4]
ms = i64[4]
ps = i64[4]
ns[0] = 3
ms[0] = 3
ps[0] = 3
ns[1] = 3
ms[1] = 3
ps[1] = 4
ns[2] = 3
ms[2] = 4
ps[2] = 4
ns[3] = 4
ms[3] = 4
ps[3] = 4
leaves = []
i = 0 ## i64
while i < 4
  leaf = ffbc_load_exact(root + paths[i], ns[i], ms[i], ps[i], 128)
  ffoist_expect("load leaf " + i.to_s(), leaf != nil)
  leaves.push(leaf)
  i += 1

outer = ffbc_load_exact(root + "matmul_2x2_rank7_strassen_gf2.txt", 2, 2, 2, 16)
saved = ffbc_load_exact(root + "matmul_7x7_rank247_d3554_outer_isotropy_gf2.txt", 7, 7, 7, 320)
ffoist_expect("load exact inputs", outer != nil && saved != nil && saved.rank() == 247)

# Exhaust the six images on one logical axis and prove they are term-set
# distinct; the full benchmark independently exhausts their Cartesian cube.
images = []
code = 0 ## i64
while code < 6
  image = ffois_gl2_image(outer, 0, code)
  ffoist_expect("GL2 image exact " + code.to_s(), image != nil && image.rank() == 7 && ffbc_verify_exact(image) == 1)
  prior = 0 ## i64
  while prior < images.size()
    ffoist_expect("GL2 image distinct", fflc_term_set_distance(images[prior], image) > 0)
    prior += 1
  images.push(image)
  code += 1

# Exhaustive-orbit winner: I on I, A on J, B on K, with block placement mask
# 3.  Its nominal rectangular-leaf sum is 248; support-aware embedding and
# parity compaction remove one net product and leave a rank-247 decomposition.
winner_outer = ffois_image(outer, 0, 1, 2)
an = ffois_alloc(3, 0)
am = ffois_alloc(3, 1)
ap = ffois_alloc(3, 2)
ffoist_expect("winner nominal rank", ffbc_score_allocation(winner_outer, an, am, ap, leaves) == 248)
winner = ffbc_compose(winner_outer, an, am, ap, leaves)
ffoist_expect("winner exact rank", winner != nil && winner.rank() == 247 && ffbc_verify_exact(winner) == 1)
ffoist_expect("winner density", fflc_density(winner) == 3554)
ffoist_expect("winner one mapped-zero term", winner.compose_nominal() == 248 && winner.compose_zero_terms() == 1)
ffoist_expect("winner no duplicate cancellation", winner.compose_distinct_terms() == 247 && winner.compose_parity_reduction() == 0)
ffoist_expect("checked-in bytes reproduce", fflc_equal(winner, saved) == 1)

temporary = "/tmp/matmul_7x7_rank247_outer_isotropy_test.txt"
ffoist_expect("serialize", ffbc_write(temporary, winner) == 247)
reloaded = ffbc_load_exact(temporary, 7, 7, 7, 320)
ffoist_expect("reparse full gate", reloaded != nil && reloaded.rank() == 247 && ffbc_verify_exact(reloaded) == 1 && fflc_equal(reloaded, saved) == 1)

<< "flipfleet_outer_isotropy_test: all checks passed rank=247 density=3554"
