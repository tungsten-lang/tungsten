use flipfleet_global_isotropy

-> ffgirt_expect(name, condition)
  if condition == false || condition == 0
    << "FAIL " + name
    exit(1)

n = 4 ## i64
capacity = ffw_default_capacity(n) ## i64
size = ffw_state_size(capacity) ## i64
source = i64[size]
rank = ffw_load_scheme_cap(source, "benchmarks/matmul/metaflip/matmul_4x4_rank47_d450_gf2.txt", n, capacity, 111, 6, 4, 100000, 25000) ## i64
ffgirt_expect("load exact 4x4 source", rank == 47 && ffw_verify_best_exact(source, n) == 1)

su = i64[capacity]
sv = i64[capacity]
sw = i64[capacity]
z = ffw_export_best(source, su, sv, sw) ## i64
tu = i64[capacity]
tv = i64[capacity]
tw = i64[capacity]
z = ffgir_copy_terms(su, sv, sw, tu, tv, tw, rank)

length = 11 ## i64
operations = i64[length]
domains = i64[length]
sources = i64[length]
targets = i64[length]
ffgirt_expect("build isotropy word", ffgir_make_word(n, 91731, length, operations, domains, sources, targets) == length)
ffgirt_expect("apply isotropy word", ffgir_apply_word(tu, tv, tw, rank, n, operations, domains, sources, targets, length, 0) == rank)
ffgirt_expect("nontrivial term-set image", ffgir_term_set_distance(su, sv, sw, rank, tu, tv, tw, rank) > 0)
ffgirt_expect("factor equality support invariant", ffgir_distinct_factor_support(su, sv, sw, rank) == ffgir_distinct_factor_support(tu, tv, tw, rank))

image = i64[size]
loaded = ffw_init_terms_cap(image, tu, tv, tw, rank, n, capacity, 111, 6, 4, 100000, 25000) ## i64
ffgirt_expect("whole-scheme image full-gates", loaded == rank && ffw_verify_best_exact(image, n) == 1)
ffgirt_expect("GL rank histogram invariant", ffbi_gl_invariant_view(source, 0) == ffbi_gl_invariant_view(image, 0))

ffgirt_expect("apply inverse word", ffgir_apply_word(tu, tv, tw, rank, n, operations, domains, sources, targets, length, 1) == rank)
ffgirt_expect("inverse recovers source set", ffgir_terms_equal(su, sv, sw, rank, tu, tv, tw, rank) == 1)

# With no moves, the helper must recognize the image as exactly conjugate.
ffgirt_expect("initial image is exact conjugate", ffgir_conjugate_current_distance(source, image, n, capacity, operations, domains, sources, targets, length) == 0)
ffgirt_expect("coarse orbit signature agrees", ffgir_orbit_signature(source) == ffgir_orbit_signature(image))

# The bounded production strategy must improve a known non-normalized 5x5
# frontier, own its output, and independently full-gate it.
n5 = 5 ## i64
capacity5 = ffw_default_capacity(n5) ## i64
size5 = ffw_state_size(capacity5) ## i64
source5 = i64[size5]
loaded5 = ffw_load_scheme_cap(source5, "benchmarks/matmul/metaflip/matmul_5x5_rank93_d1155_gf2.txt", n5, capacity5, 313, 6, 4, 100000, 25000) ## i64
ffgirt_expect("load 5x5 directed fixture", loaded5 == 93)
descent5 = i64[size5]
stats5 = i64[4]
result5 = ffgir_density_descent_state_into(source5, descent5, n5, capacity5, 317, 6, 4, 100000, 25000, 32, stats5) ## i64
ffgirt_expect("bounded descent improves", result5 == 93 && stats5[0] == 1155 && stats5[1] == 1025 && stats5[2] == 12)
ffgirt_expect("bounded descent full-gates", ffw_best_bits(descent5) == 1025 && ffw_verify_best_exact(descent5, n5) == 1)
ffgirt_expect("directed image keeps orbit signature", ffgir_orbit_signature(source5) == ffgir_orbit_signature(descent5))

<< "flipfleet_global_isotropy_test: all checks passed"
