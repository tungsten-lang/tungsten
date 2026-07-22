use flipfleet_rect_archive_nullspace

-> ffranct_expect(label, condition) i64
  if condition == false || condition == 0
    << "FAIL " + label
    exit(1)
  1

root = "benchmarks/matmul/metaflip/"
d655 = ffbc_load_exact(root + "matmul_4x4x5_rank60_d655_global_isotropy_gf2.txt", 4, 4, 5, 128)
d628 = ffbc_load_exact(root + "matmul_4x4x5_rank60_d628_gl_frontier_gf2.txt", 4, 4, 5, 128)
z = ffranct_expect("parents exact", d655 != nil && d628 != nil && ffbc_verify_exact(d655) == 1 && ffbc_verify_exact(d628) == 1) ## i64

# Nullity six has 63 nonzero relations.  Exactly one is the full parent
# difference, leaving 62 proper children.  This is a compact regression for
# exhaustive enumeration, complementary-child retention, independent exact
# gates, and full term-set deduplication.
archive = []
archive.push(d655)
archive.push(d628)
meta = i64[16]
made = ffran_enumerate_children(d655, d628, 6, 63, 100, archive, meta) ## i64
z = ffranct_expect("complete nullity-six hull", meta[0] == 24 && meta[1] == 6 && meta[2] == 18 && meta[3] == 63 && meta[4] == 63)
z = ffranct_expect("all proper children retained", made == 62 && meta[5] == 62 && meta[6] == 62 && meta[7] == 62 && meta[8] == 62 && archive.size() == 64)
z = ffranct_expect("no pair failures or caps", meta[9] == 0 && meta[10] == 60 && meta[11] == 0 && meta[12] == 0 && meta[13] == 0 && meta[14] == 0 && meta[15] == 0)

i = 0 ## i64
while i < archive.size()
  z = ffranct_expect("archive exact", archive[i] != nil && archive[i].rank() == 60 && ffbc_verify_exact(archive[i]) == 1)
  j = i + 1 ## i64
  while j < archive.size()
    z = ffranct_expect("archive term sets distinct", fflc_term_set_distance(archive[i], archive[j]) > 0)
    j += 1
  i += 1

# Re-enumerating into the complete archive must append nothing and account for
# all 62 proper children as full-term-set duplicates.
repeat_meta = i64[16]
repeat = ffran_enumerate_children(d655, d628, 6, 63, 100, archive, repeat_meta) ## i64
z = ffranct_expect("repeat dedupes complete hull", repeat == 0 && archive.size() == 64 && repeat_meta[4] == 63 && repeat_meta[5] == 62 && repeat_meta[9] == 62)

# A small child cap terminates safely after three additions and reports that
# this was not a complete hull audit.
capped = []
capped.push(d655)
capped.push(d628)
capped_meta = i64[16]
capped_made = ffran_enumerate_children(d655, d628, 6, 63, 3, capped, capped_meta) ## i64
z = ffranct_expect("child cap", capped_made == 3 && capped.size() == 5 && capped_meta[12] == 1 && capped_meta[11] == 0)

relation_capped = []
relation_capped.push(d655)
relation_capped.push(d628)
relation_capped_meta = i64[16]
relation_capped_made = ffran_enumerate_children(d655, d628, 6, 1, 100, relation_capped, relation_capped_meta) ## i64
z = ffranct_expect("relation cap", relation_capped_made == 1 && relation_capped.size() == 3 && relation_capped_meta[4] == 1 && relation_capped_meta[11] == 1 && relation_capped_meta[12] == 0)

# One closure pass is equivalent to the complete pair hull for a two-parent
# archive; the breadth-first wrapper must preserve the same exact archive.
closure = []
closure.push(d655)
closure.push(d628)
closure_meta = i64[19]
closure_made = ffran_archive_closure(closure, 1, 1, 6, 63, 100, closure_meta) ## i64
z = ffranct_expect("one-pass closure", closure_made == 62 && closure.size() == 64 && closure_meta[0] == 2 && closure_meta[1] == 64 && closure_meta[2] == 62 && closure_meta[3] == 1 && closure_meta[4] == 1 && closure_meta[5] == 1)
z = ffranct_expect("closure exact accounting", closure_meta[6] == 63 && closure_meta[7] == 62 && closure_meta[8] == 62 && closure_meta[9] == 0 && closure_meta[10] == 60 && closure_meta[11] == 0 && closure_meta[16] == 0)

# The actual five-door 2x2x5 archive saturates after two layers.  Two new
# rank-18 term sets survive full deduplication; their later pairings create no
# third layer and, importantly, no false rank-17 candidate.
paths225 = []
paths225.push(root + "matmul_2x2x5_rank18_d84_gf2.txt")
paths225.push(root + "matmul_2x2x5_rank18_d88_gf2.txt")
paths225.push(root + "matmul_2x2x5_rank18_d92_block_local_gl_gf2.txt")
paths225.push(root + "matmul_2x2x5_rank18_d84_block_splice_gf2.txt")
paths225.push(root + "matmul_2x2x5_rank18_d84_gpu_block_tunnel_gf2.txt")
closure225 = []
i = 0
while i < paths225.size()
  door225 = ffbc_load_exact(paths225[i], 2, 2, 5, 32)
  z = ffranct_expect("225 door exact", door225 != nil && door225.rank() == 18 && ffbc_verify_exact(door225) == 1)
  closure225.push(door225)
  i += 1
meta225 = i64[19]
made225 = ffran_archive_closure(closure225, 8, 1000, 16, 65535, 100, meta225) ## i64
z = ffranct_expect("225 closure saturates", made225 == 2 && closure225.size() == 7 && meta225[3] == 2 && meta225[4] == 21 && meta225[5] == 2)
z = ffranct_expect("225 closure exact and rank stable", meta225[6] == 18 && meta225[7] == 12 && meta225[8] == 12 && meta225[9] == 10 && meta225[10] == 18 && meta225[11] == 0 && meta225[16] == 0)
i = 0
while i < closure225.size()
  z = ffranct_expect("225 closure child exact", closure225[i].rank() == 18 && ffbc_verify_exact(closure225[i]) == 1)
  j = i + 1
  while j < closure225.size()
    z = ffranct_expect("225 closure term sets distinct", fflc_term_set_distance(closure225[i], closure225[j]) > 0)
    j += 1
  i += 1

pair_capped225 = []
i = 0
while i < 5
  pair_capped225.push(closure225[i])
  i += 1
pair_capped225_meta = i64[19]
z = ffran_archive_closure(pair_capped225, 8, 1, 16, 65535, 100, pair_capped225_meta)
z = ffranct_expect("global pair cap", pair_capped225_meta[4] == 1 && pair_capped225_meta[14] == 1 && pair_capped225_meta[15] == 0)

archive_capped225 = []
i = 0
while i < 5
  archive_capped225.push(closure225[i])
  i += 1
archive_capped225_meta = i64[19]
z = ffran_archive_closure(archive_capped225, 8, 1000, 16, 65535, 6, archive_capped225_meta)
z = ffranct_expect("global archive cap", archive_capped225.size() == 6 && archive_capped225_meta[15] == 1 && archive_capped225_meta[14] == 0)

<< "PASS flipfleet rectangular archive nullspace closure children=" + made.to_s() + " exact=" + meta[7].to_s() + " duplicates=" + repeat_meta[9].to_s() + " closure225=" + made225.to_s()
