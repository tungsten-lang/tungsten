use metaflip_worker

-> ffwmft_expect(label, condition) (String bool) i64
  if !condition
    << "METAFLIP_WORKER_MIXED_FORMAT_FAIL " + label
    exit(1)
  1

# Both fixtures have a numeric rank header followed by `R u v w` rows.  They
# are independently exact catalog imports and previously loaded only through
# the rectangular/composer parsers.
n5 = 5 ## i64
capacity5 = ffw_default_capacity(n5) ## i64
state5 = i64[ffw_state_size(capacity5)]
rank5 = ffw_load_scheme_cap(state5, "benchmarks/matmul/metaflip/matmul_5x5_rank93_catalog_perminov_c843_gf2.txt", n5, capacity5, 97101, 4, 2, 1000, 250) ## i64
ffwmft_expect("5x5 catalog", rank5 == 93 && ffw_verify_best_exact(state5, n5) == 1)

n6 = 6 ## i64
capacity6 = ffw_default_capacity(n6) ## i64
state6 = i64[ffw_state_size(capacity6)]
rank6 = ffw_load_scheme_cap(state6, "benchmarks/matmul/metaflip/matmul_6x6_rank153_catalog_gf2.txt", n6, capacity6, 97201, 4, 2, 1000, 250) ## i64
ffwmft_expect("6x6 catalog", rank6 == 153 && ffw_verify_best_exact(state6, n6) == 1)
<< "metaflip_worker_mixed_format_test: all checks passed"
