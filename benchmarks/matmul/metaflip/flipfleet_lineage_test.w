use metaflip_worker
use flipfleet_basin_identity
use flipfleet_lineage

-> ffl_test_expect(name, condition)
  if condition == false || condition == 0
    << "FAIL " + name
    exit(1)

ffl_test_expect("direct role source", ffl_source_role(ffl_gpu_source(4, 0 - 1)) == 4)
ffl_test_expect("pool role source", ffl_source_role(ffl_gpu_source(10, 7)) == 10)
ffl_test_expect("pool mode source", ffl_source_pool_mode(ffl_gpu_source(10, 7)) == 7)
ffl_test_expect("rect source", ffl_source_role(ffl_rect_source(1)) == 10)
ffl_test_expect("cpu source ignored", ffl_source_role(103) < 0)
ffl_test_expect("rank reward", ffl_delayed_reward(94, 1200, 93, 1190, 0) == 10000)
ffl_test_expect("novel reward", ffl_delayed_reward(93, 1200, 93, 1200, 1) == 250)

n = 3 ## i64
capacity = ffw_default_capacity(n) ## i64
size = ffw_state_size(capacity) ## i64
base = i64[size]
z = ffw_load_scheme_cap(base, "benchmarks/matmul/metaflip/matmul_3x3_rank23_d139_gf2.txt", n, capacity, 17, 6, 4, 1000, 250) ## i64
map_states = []
map_sources = []
map_states.push(base)
map_sources.push(ffl_gpu_source(10, 4))
ffl_test_expect("canonical source lookup", ffl_find_source(base, map_states, map_sources) == 1004)
registry_ids = []
registry_sources = []
ffl_test_expect("registry add", ffl_registry_add(registry_ids, registry_sources, base, 1004, 4) == 1)
ffl_test_expect("registry lookup", ffl_registry_find(base, registry_ids, registry_sources) == 1004)
ffl_test_expect("origin return", ffl_returned_to_origin(base, ffbi_best_id(base)) == 1)

<< "flipfleet_lineage_test: all checks passed"
