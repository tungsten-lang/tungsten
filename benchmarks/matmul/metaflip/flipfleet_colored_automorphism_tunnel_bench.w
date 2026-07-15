# Offline audit for simultaneous multi-colour partial automorphisms.
#
# Usage from the repository root:
#   flipfleet_colored_automorphism_tunnel_bench
#   flipfleet_colored_automorphism_tunnel_bench N PAIRS COMBOS MAX_BITS DISTANT
#
# N=0 audits 4x4..7x7.  DISTANT=1 additionally audits three 7x7 seeds at
# maximum source distance from one another.  Pair sampling is deterministic
# and spread across the complete unordered elementary-generator pair space.
# Defaults reproduce the documented balanced audit: 0 4 4096 20 1.

use flipfleet_colored_automorphism_tunnel

-> ffcatb_expect(label, condition) (String bool) i64
  if !condition
    << "COLORED_AUTOMORPHISM_BENCH_FAIL " + label
    exit(1)
  1

-> ffcatb_gcd(a, b) (i64 i64) i64
  while b != 0
    remainder = a % b ## i64
    a = b
    b = remainder
  if a < 0
    a = 0 - a
  a

-> ffcatb_pair_count(generators) (i64) i64
  generators * (generators - 1) / 2

-> ffcatb_decode_pair(generators, flat, out) (i64 i64 i64[]) i64
  if generators < 2 || flat < 0 || flat >= ffcatb_pair_count(generators) || out.size() < 2
    return 0
  seen = 0 ## i64
  left = 0 ## i64
  while left < generators - 1
    right = left + 1 ## i64
    while right < generators
      if seen == flat
        out[0] = left
        out[1] = right
        return 1
      seen += 1
      right += 1
    left += 1
  0

-> ffcatb_generator_label(decoded) (i64[])
  operation = "swap" ## String
  if decoded[0] == 1
    operation = "shear"
  operation + ":" + decoded[1].to_s() + ":" + decoded[2].to_s() + ">" + decoded[3].to_s()

# Aggregate layout:
# pairs, same-domain, cross-domain, swap/swap, swap/shear, shear/shear,
# columns sum, nullity sum/min/max, exhaustive pairs, theoretical sum known,
# combinations, exclusive, delta gates, endpoint gates, failures,
# monochrome, multicolour, source/g/h/hg quotients, genuine, rank drops,
# density improvements, max distance, max novelty, max selected, elapsed ms,
# bounded single/pair/random, best rank/density.
-> ffcatb_run(label, path, n, requested_pairs, combination_cap, max_bits) (String String i64 i64 i64 i64) i64
  capacity = ffw_default_capacity(n) ## i64
  source = i64[ffw_state_size(capacity)]
  rank = ffw_load_scheme_cap(source, path, n, capacity, 920003 + n, 0, 1, 1, 1) ## i64
  if rank < 1 || ffw_verify_current_exact(source, n) != 1
    << "COLORED_AUTOMORPHISM_BENCH_ERROR tensor=" + label + " error=load"
    return 0 - 1
  us = i64[capacity]
  vs = i64[capacity]
  ws = i64[capacity]
  ffcatb_expect("export " + label, ffw_export_current(source, us, vs, ws) == rank)
  source_density = ffgir_density(us, vs, ws, rank) ## i64
  workspace = FFCATWorkspace.new(rank, n, capacity)
  best_u = i64[capacity]
  best_v = i64[capacity]
  best_w = i64[capacity]
  pair_meta = i64[35]
  aggregate = i64[43]
  aggregate[7] = 9223372036854775807
  aggregate[31] = rank
  aggregate[32] = source_density
  generators = ffpan_elementary_count(n) ## i64
  total_pairs = ffcatb_pair_count(generators) ## i64
  pairs = requested_pairs ## i64
  if pairs > total_pairs
    pairs = total_pairs
  if pairs < 1
    pairs = 1
  stride = total_pairs / pairs + 1 ## i64
  while ffcatb_gcd(stride, total_pairs) != 1
    stride += 1
  offset = (n * 104729 + rank * 1009) % total_pairs ## i64
  pair_ids = i64[2]
  g = i64[4]
  h = i64[4]
  started = ccall("__w_clock_ms") ## i64
  sample = 0 ## i64
  while sample < pairs
    flat = (offset + sample * stride) % total_pairs ## i64
    # Always include the lexicographically first same-domain pair as a stable
    # regression anchor, then use the spread schedule for the remaining set.
    if sample == 0
      flat = 0
    ffcatb_expect("decode pair", ffcatb_decode_pair(generators, flat, pair_ids) == 1)
    ffcatb_expect("decode g", ffpan_elementary_decode(n, pair_ids[0], g) == 1)
    ffcatb_expect("decode h", ffpan_elementary_decode(n, pair_ids[1], h) == 1)
    pair_started = ccall("__w_clock_ms") ## i64
    genuine = ffcat_audit_pair(us, vs, ws, rank, n, capacity, g, h, max_bits, combination_cap, 920071 + sample * 17 + n * 1009, workspace, best_u, best_v, best_w, pair_meta) ## i64
    pair_elapsed = ccall("__w_clock_ms") - pair_started ## i64
    ffcatb_expect("pair audit", genuine >= 0 && pair_meta[8] == 0 && pair_meta[6] == pair_meta[7])
    aggregate[0] += 1
    if g[1] == h[1]
      aggregate[1] += 1
    else
      aggregate[2] += 1
    if g[0] == 0 && h[0] == 0
      aggregate[3] += 1
    if g[0] != h[0]
      aggregate[4] += 1
    if g[0] == 1 && h[0] == 1
      aggregate[5] += 1
    aggregate[6] += pair_meta[0]
    aggregate[7] = aggregate[7]
    if pair_meta[1] < aggregate[7]
      aggregate[7] = pair_meta[1]
    if pair_meta[1] > aggregate[8]
      aggregate[8] = pair_meta[1]
    aggregate[9] += pair_meta[1]
    aggregate[10] += pair_meta[2]
    if pair_meta[3] >= 0
      aggregate[11] += pair_meta[3]
    aggregate[12] += pair_meta[4]
    aggregate[13] += pair_meta[5]
    aggregate[14] += pair_meta[6]
    aggregate[15] += pair_meta[7]
    aggregate[16] += pair_meta[8]
    aggregate[17] += pair_meta[9]
    aggregate[18] += pair_meta[10]
    aggregate[19] += pair_meta[11]
    aggregate[20] += pair_meta[12]
    aggregate[21] += pair_meta[13]
    aggregate[22] += pair_meta[14]
    aggregate[23] += pair_meta[15]
    aggregate[24] += pair_meta[16]
    aggregate[25] += pair_meta[17]
    if pair_meta[20] > aggregate[26]
      aggregate[26] = pair_meta[20]
    if pair_meta[21] > aggregate[27]
      aggregate[27] = pair_meta[21]
    if pair_meta[22] > aggregate[28]
      aggregate[28] = pair_meta[22]
    aggregate[29] += pair_elapsed
    aggregate[30] += pair_meta[23]
    aggregate[33] += pair_meta[24] + pair_meta[25]
    aggregate[34] += pair_meta[26]
    aggregate[35] += pair_meta[27]
    aggregate[36] += pair_meta[28]
    aggregate[37] += pair_meta[29]
    aggregate[38] += pair_meta[30]
    if pair_meta[31] > aggregate[39]
      aggregate[39] = pair_meta[31]
    aggregate[40] += pair_meta[32]
    aggregate[41] += pair_meta[33]
    aggregate[42] += pair_meta[34]
    if pair_meta[18] < aggregate[31] || (pair_meta[18] == aggregate[31] && pair_meta[19] < aggregate[32])
      aggregate[31] = pair_meta[18]
      aggregate[32] = pair_meta[19]
    if genuine > 0 || pair_meta[16] > 0 || pair_meta[17] > 0
      << "COLORED_AUTOMORPHISM_HIT tensor=" + label + " pair=" + pair_ids[0].to_s() + "+" + pair_ids[1].to_s() + " g=" + ffcatb_generator_label(g) + " h=" + ffcatb_generator_label(h) + " nullity=" + pair_meta[1].to_s() + " exhaustive=" + pair_meta[2].to_s() + " scanned=" + pair_meta[4].to_s() + " sparse_cross=" + pair_meta[32].to_s() + " sparse_truncated=" + pair_meta[33].to_s() + " exclusive=" + pair_meta[5].to_s() + " multicolor=" + pair_meta[10].to_s() + " quotient_genuine=" + pair_meta[15].to_s() + " staged_g=" + pair_meta[26].to_s() + " staged_h=" + pair_meta[27].to_s() + " cross_coupled=" + genuine.to_s() + " rank_drops=" + pair_meta[16].to_s() + " density_better=" + pair_meta[17].to_s() + " max_distance=" + pair_meta[20].to_s() + " max_cross_distance=" + pair_meta[31].to_s() + " max_novelty=" + pair_meta[21].to_s() + " ms=" + pair_elapsed.to_s()
    sample += 1
  elapsed = ccall("__w_clock_ms") - started ## i64
  average_columns = aggregate[6] / aggregate[0] ## i64
  average_nullity = aggregate[9] / aggregate[0] ## i64
  coverage_ppm = 0 ## i64
  if aggregate[11] > 0
    coverage_ppm = aggregate[12] * 1000000 / aggregate[11]
  << "COLORED_AUTOMORPHISM_SUMMARY tensor=" + label + " rank=" + rank.to_s() + " density=" + source_density.to_s() + " pairs=" + aggregate[0].to_s() + "/" + total_pairs.to_s() + " pair_coverage_ppm=" + (aggregate[0] * 1000000 / total_pairs).to_s() + " same_domain=" + aggregate[1].to_s() + " cross_domain=" + aggregate[2].to_s() + " type_ss=" + aggregate[3].to_s() + " type_st=" + aggregate[4].to_s() + " type_tt=" + aggregate[5].to_s() + " columns_avg=" + average_columns.to_s() + " nullity_min=" + aggregate[7].to_s() + " nullity_max=" + aggregate[8].to_s() + " nullity_avg=" + average_nullity.to_s() + " exhaustive_pairs=" + aggregate[10].to_s() + " combinations=" + aggregate[12].to_s() + " combination_coverage_ppm_known=" + coverage_ppm.to_s() + " sparse_cross=" + aggregate[40].to_s() + " sparse_truncated_pairs=" + aggregate[41].to_s() + " sparse_full_compares=" + aggregate[42].to_s() + " exclusive=" + aggregate[13].to_s() + " delta_gates=" + aggregate[14].to_s() + " full_n6_gates=" + aggregate[15].to_s() + " failures=" + aggregate[16].to_s() + " monochrome=" + aggregate[17].to_s() + " multicolor=" + aggregate[18].to_s() + " quotients=" + aggregate[19].to_s() + "/" + aggregate[20].to_s() + "/" + aggregate[21].to_s() + "/" + aggregate[22].to_s() + " quotient_genuine=" + aggregate[23].to_s() + " staged_g=" + aggregate[34].to_s() + " staged_h=" + aggregate[35].to_s() + " cross_coupled=" + aggregate[36].to_s() + " rank_drops=" + aggregate[24].to_s() + " density_better=" + aggregate[25].to_s() + " cross_rank_drops=" + aggregate[37].to_s() + " cross_density_better=" + aggregate[38].to_s() + " best_rank=" + aggregate[31].to_s() + " best_density=" + aggregate[32].to_s() + " max_distance=" + aggregate[26].to_s() + " max_cross_distance=" + aggregate[39].to_s() + " max_novelty=" + aggregate[27].to_s() + " max_selected=" + aggregate[28].to_s() + " elapsed_ms=" + elapsed.to_s() + " measured_pair_ms=" + aggregate[29].to_s() + " bounded_singles=" + aggregate[30].to_s() + " bounded_pair_or_random=" + aggregate[33].to_s()
  1

args = argv()
only_n = 0 ## i64
pairs = 4 ## i64
combinations = 4096 ## i64
max_bits = 20 ## i64
distant = 1 ## i64
if args.size() > 0
  only_n = args[0].to_i()
if args.size() > 1
  pairs = args[1].to_i()
if args.size() > 2
  combinations = args[2].to_i()
if args.size() > 3
  max_bits = args[3].to_i()
if args.size() > 4
  distant = args[4].to_i()
ffcatb_expect("arguments", (only_n == 0 || (only_n >= 4 && only_n <= 7)) && pairs >= 1 && pairs <= 20000 && combinations >= 1 && combinations <= 16777215 && max_bits >= 1 && max_bits <= 30 && (distant == 0 || distant == 1))

if only_n == 0 || only_n == 4
  z = ffcatb_run("4x4-d450", "benchmarks/matmul/metaflip/matmul_4x4_rank47_d450_gf2.txt", 4, pairs, combinations, max_bits) ## i64
if only_n == 0 || only_n == 5
  z = ffcatb_run("5x5-d968", "benchmarks/matmul/metaflip/matmul_5x5_rank93_d968_global_isotropy_gf2.txt", 5, pairs, combinations, max_bits)
if only_n == 0 || only_n == 6
  z = ffcatb_run("6x6-d1860", "benchmarks/matmul/metaflip/matmul_6x6_rank153_d1860_global_isotropy_gf2.txt", 6, pairs, combinations, max_bits)
if only_n == 0 || only_n == 7
  z = ffcatb_run("7x7-d3098", "benchmarks/matmul/metaflip/matmul_7x7_rank247_d3098_global_isotropy_gf2.txt", 7, pairs, combinations, max_bits)
  if distant == 1
    z = ffcatb_run("7x7-beam-dense-disjoint", "benchmarks/matmul/metaflip/matmul_7x7_rank247_d3098_partial_auto_beam_dense_gf2.txt", 7, pairs, combinations, max_bits)
    z = ffcatb_run("7x7-beam-far-disjoint", "benchmarks/matmul/metaflip/matmul_7x7_rank247_d3098_partial_auto_beam_far_gf2.txt", 7, pairs, combinations, max_bits)
    z = ffcatb_run("7x7-structural-d3554", "benchmarks/matmul/metaflip/matmul_7x7_rank247_d3554_outer_isotropy_gf2.txt", 7, pairs, combinations, max_bits)
