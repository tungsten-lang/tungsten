use flipfleet_partial_automorphism_nullspace

-> ffpant_expect(label, condition) (String bool) i64
  if !condition
    << "PARTIAL_AUTOMORPHISM_NULLSPACE_FAIL " + label
    exit(1)
  1

# Two independent planted relations: r2=r0+r1 and r5=r3+r4.
count = 6 ## i64
words = 1 ## i64
deltas = i64[count]
deltas[0] = 1
deltas[1] = 2
deltas[2] = 3
deltas[3] = 4
deltas[4] = 8
deltas[5] = 12
dependencies = i64[count * ffpan_coeff_words(count)]
meta = i64[4]
nullity = ffpan_nullspace(deltas, count, words, dependencies, meta) ## i64
ffpant_expect("rank/nullity", nullity == 2 && meta[0] == 4 && meta[1] == 2)
ids = i64[count]
dependency = 0 ## i64
while dependency < nullity
  weight = ffpan_dependency_weight(dependencies, dependency, count) ## i64
  made = ffpan_dependency_ids(dependencies, dependency, count, ids) ## i64
  ffpant_expect("weight", weight == 3 && made == weight)
  ffpant_expect("exact relation", ffpa_relation_exact(deltas, ids, made, words) == 1)
  dependency += 1

# The d968 5x5 frontier has one apparent weight-55 dependency, but its
# materialized endpoint is exactly the whole-scheme swap image.  Keep this as
# a regression for the global-orbit quotient: it must never enter the fleet as
# independent basin evidence.
n5 = 5 ## i64
cap5 = ffw_default_capacity(n5) ## i64
state5 = i64[ffw_state_size(cap5)]
rank5 = ffw_load_scheme_cap(state5, "benchmarks/matmul/metaflip/matmul_5x5_rank93_d968_global_isotropy_gf2.txt", n5, cap5, 77101, 0, 1, 1, 1) ## i64
ffpant_expect("5x5 quotient source", rank5 == 93 && ffw_verify_current_exact(state5, n5) == 1)
u5 = i64[cap5]
v5 = i64[cap5]
w5 = i64[cap5]
ffpant_expect("5x5 export", ffw_export_current(state5, u5, v5, w5) == rank5)
out5u = i64[cap5]
out5v = i64[cap5]
out5w = i64[cap5]
meta5 = i64[18]
workspace5 = FFPANWorkspace.new(rank5, n5, cap5)
hit5 = ffpan_find_elementary_escape(u5, v5, w5, rank5, n5, cap5, 0, 5, workspace5, out5u, out5v, out5w, meta5) ## i64
ffpant_expect("5x5 apparent endpoint quotiented", hit5 == 0 && meta5[3] >= 1 && meta5[5] >= 1 && meta5[6] == 0 && meta5[15] == 0)

# The block-composed 7x7 frontier really does split under elementary
# automorphisms.  With the canonical scan order, I-domain swap 0<->2 exposes
# a weight-28 exact endpoint that differs from both source and global image.
n7 = 7 ## i64
cap7 = ffw_default_capacity(n7) ## i64
state7 = i64[ffw_state_size(cap7)]
rank7 = ffw_load_scheme_cap(state7, "benchmarks/matmul/metaflip/matmul_7x7_rank247_d3098_global_isotropy_gf2.txt", n7, cap7, 77201, 0, 1, 1, 1) ## i64
ffpant_expect("7x7 tunnel source", rank7 == 247 && ffw_verify_current_exact(state7, n7) == 1)
u7 = i64[cap7]
v7 = i64[cap7]
w7 = i64[cap7]
ffpant_expect("7x7 export", ffw_export_current(state7, u7, v7, w7) == rank7)
out7u = i64[cap7]
out7v = i64[cap7]
out7w = i64[cap7]
meta7 = i64[18]
workspace7 = FFPANWorkspace.new(rank7, n7, cap7)
hit7 = ffpan_find_elementary_escape(u7, v7, w7, rank7, n7, cap7, 0, 5, workspace7, out7u, out7v, out7w, meta7) ## i64
ffpant_expect("7x7 genuine tunnel found", hit7 == 247 && meta7[6] == 1 && meta7[7] == 28 && meta7[8] == 0 && meta7[9] == 0 && meta7[10] == 0 && meta7[11] == 2)
ffpant_expect("7x7 exact quotient distances", meta7[12] == 56 && meta7[13] > 0 && meta7[14] == 1 && meta7[15] == 0)
check7 = i64[ffw_state_size(cap7)]
loaded7 = ffw_init_terms_cap(check7, out7u, out7v, out7w, hit7, n7, cap7, 77301, 0, 1, 1, 1) ## i64
ffpant_expect("7x7 tunnel exhaustive gate", loaded7 == hit7 && ffw_verify_current_exact(check7, n7) == 1)

<< "flipfleet_partial_automorphism_nullspace_test: all checks passed nullity=" + nullity.to_s() + " 5x5_global_quotients=" + meta5[5].to_s() + " 7x7_weight=" + meta7[7].to_s() + " distance=" + meta7[12].to_s()
