use flipfleet_overlapping_block_frontier

-> ffobpft_expect(name, condition)
  if condition
    << "PASS " + name
    return 0
  << "FAIL " + name
  exit(1)
  1

root = "benchmarks/matmul/metaflip/"
strassen = ffbc_load_exact(root + "matmul_2x2_rank7_strassen_gf2.txt", 2, 2, 2, 16)
ffobpft_expect("Strassen leaf exact", strassen != nil && strassen.rank() == 7)
leaves = [strassen]

# The checked-in direct min-two leaves do not cover every 2xa xb shape.  The
# DP completion builds those missing leaves by exact disjoint tensor splits.
min2 = [strassen]
min2.push(ffbc_load_exact(root + "matmul_2x2x3_rank11_catalog_gf2.txt", 2, 2, 3, 32))
min2.push(ffbc_load_exact(root + "matmul_2x3x3_rank15_catalog_gf2.txt", 2, 3, 3, 32))
min2.push(ffbc_load_exact(root + "matmul_2x3x4_rank20_catalog_gf2.txt", 2, 3, 4, 40))
min2.push(ffbc_load_exact(root + "matmul_2x4x4_rank26_catalog_gf2.txt", 2, 4, 4, 48))
min2.push(ffbc_load_exact(root + "matmul_2x4x5_rank33_catalog_gf2.txt", 2, 4, 5, 64))
generated = ffobpf_complete_min2(min2, 7) ## i64
choice = i64[2]
found277 = ffbc_find_leaf(min2, 2, 7, 7, choice) ## i64
leaf277 = nil
if found277 == 1
  leaf277 = ffbc_orient_scheme(min2[choice[0]], choice[1])
ffobpft_expect("exact min-two pool completion", generated > 0 && leaf277 != nil && leaf277.rank() == 81 && ffbc_verify_exact(leaf277) == 1)

# Trusted hot embedding is independently checked against the scalar block.
embedded = ffobpf_embed_choice(strassen, 0, 4, 4, 4, 5, 10, 12)
reference = ffobp_naive_block(4, 4, 4, 5, 10, 12)
ffobpft_expect("trusted noncontiguous embedding exact", embedded != nil && ffobp_same_tensor(embedded, reference) == 1)

# The entire singleton catalogue is a proven boundary: the fixed width-one
# axis prevents every 2--8 leaf substitution, hence every compact macro is the
# empty term set rather than an escape.
singleton_cache = FFOBPBlockCache.new(3, 3, 3, 512)
singleton_count = ffobp_bounded_count(3, 3, 3, 1024) ## i64
singleton_noops = 0 ## i64
i = 0 ## i64
while i < singleton_count
  identity = ffobp_bounded_at(3, 3, 3, i)
  macro = ffobpf_identity_macro(identity, singleton_cache, leaves)
  if macro != nil && macro.rank() == 0
    singleton_noops += 1
  i += 1
ffobpft_expect("complete singleton catalogue compacts to no-op", singleton_count == 81 && singleton_noops == singleton_count)

# A true overlapping-mask identity activates non-schoolbook leaves and yields
# a nonempty exact zero macro.
identity = ffobp_four_cycle(4, 4, 4, 0, 3, 3, 12, 5, 10)
ffobpft_expect("overlapping support identity exact", identity != nil && ffobp_identity_zero(identity) == 1)
cache = FFOBPBlockCache.new(4, 4, 4, 128)
macro = ffobpf_identity_macro(identity, cache, leaves)
ffobpft_expect("leaf-substituted macro nonempty and zero", macro != nil && macro.rank() > 0 && ffobp_verify_scheme_zero(macro) == 1)

# Exact term-set scoring precedes endpoint allocation.  Planting the macro and
# applying it a second time must return the original exact schoolbook scheme.
baseline = ffbc_load_exact(root + "matmul_4x4_rank47_d450_gf2.txt", 4, 4, 4, 64)
planted = ffobpf_parity2(baseline, macro)
estimated = ffobpf_xor_rank(planted, macro) ## i64
recovered = ffobpf_apply_gated(planted, macro, planted.rank())
ffobpft_expect("planted macro remains exact", planted != nil && ffbc_verify_exact(planted) == 1)
ffobpft_expect("rank estimate matches materialized recovery", recovered != nil && estimated == 47 && recovered.rank() == estimated && ffobp_same_tensor(recovered, baseline) == 1)

# The bounded sampler is tested with a one-element fixed bank and complete
# two-mask pair banks, so its sole axis-0 sample is the planted identity.
ibank = i64[2]
jbank = i64[2]
kbank = i64[2]
ibank[0] = 3
jbank[0] = 3
jbank[1] = 12
kbank[0] = 5
kbank[1] = 10
sampled = ffobpf_support_identity_at(4, 4, 4, 0, ibank, 1, jbank, 2, kbank, 2, 0, 1)
ffobpft_expect("complete bounded support sampler hits plant", sampled != nil && sampled.imask(0) == identity.imask(0) && sampled.jmask(3) == identity.jmask(3) && sampled.kmask(3) == identity.kmask(3))

scan_cache = FFOBPBlockCache.new(4, 4, 4, 128)
scan_result = i64[8]
useful = ffobpf_scan_support(planted, leaves, ibank, 1, jbank, 2, kbank, 2, 1, 4, scan_cache, scan_result) ## i64
ffobpft_expect("bounded real-frontier scan recovers planted endpoint", scan_result[0] == 1 && scan_result[1] == 1 && useful >= 1 && scan_result[2] == 47)

# Live-support banks always retain coordinates/full plus the minimal mask of a
# term and its nonempty complement, then close under bounded overlaps/XORs.
support_bank = i64[24]
support_count = ffobpf_support_bank(planted, 0, support_bank) ## i64
wanted = ffobpf_term_axis_mask(planted, 0, 0) ## i64
seen = 0 ## i64
i = 0
while i < support_count
  if support_bank[i] == wanted
    seen = 1
  i += 1
ffobpft_expect("live support enters bounded mask bank", support_count >= 5 && seen == 1)

# Full-block mode is the global replacement branch.  For 2x2 it correctly
# reconstructs schoolbook rank 8, which cannot beat rank-7 Strassen.
full_identity = ffobpf_full_identity(2, 2, 2, 0, 3, 1, 1)
full_index = ffobpf_full_block_index(full_identity) ## i64
full_cache = FFOBPBlockCache.new(2, 2, 2, 32)
full_other = ffobpf_without_block(full_identity, full_index, full_cache, leaves)
ffobpft_expect("full-block complement exactly reconstructs MMT", full_index >= 0 && full_other != nil && full_other.rank() == 8 && ffbc_verify_exact(full_other) == 1)

<< "overlap frontier: singleton=" + singleton_count.to_s() + " noops=" + singleton_noops.to_s() + " planted_macro=" + macro.rank().to_s() + " planted=" + planted.rank().to_s() + " recovered=" + recovered.rank().to_s()
<< "flipfleet_overlapping_block_frontier_test: all checks passed"
