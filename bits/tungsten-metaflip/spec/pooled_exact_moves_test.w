use ../lib/metaflip/kernels/pooled_exact
use ../lib/metaflip/kernels/bundles/pooled_exact

-> ffpemt_expect(name, condition) (String bool) i64
  if !condition
    << "FAIL " + name
    exit(1)
  1

z = ffpemt_expect("mode-locked planted control", ffml_selftest() == 1) ## i64
z = ffpemt_expect("mode-locked wide equations", ffml_wide_selftest() == 1)
z = ffpemt_expect("debt MITM local control", ffdm_debt_mitm_selftest() == 1)
z = ffpemt_expect("worker kinds", ffpem_kind_supported(1) == 1 && ffpem_kind_supported(5) == 1 && ffpem_kind_supported(10) == 1 && ffpem_kind_supported(7) == 0)
z = ffpemt_expect("bundle validation", ffpeb_plan_valid(7, 10, 50, 0) == 1 && ffpeb_plan_valid(7, 9, 50, 0) == 0 && ffpeb_plan_valid(8, 10, 50, 0) == 0)

root = __DIR__ + "/../lib/metaflip/seeds/gf2/"
n = 2 ## i64
capacity = ffw_default_capacity(n) ## i64
base = i64[ffw_state_size(capacity)]
base_rank = ffw_load_scheme_cap(base, root + "matmul_2x2_rank7_strassen_gf2.txt", n, capacity, 88101, 0, 1, 1, 1) ## i64
z = ffpemt_expect("2x2 base exact", base_rank == 7 && ffw_verify_best_exact(base, n) == 1)
base_u = i64[capacity]
base_v = i64[capacity]
base_w = i64[capacity]
z = ffw_export_best(base, base_u, base_v, base_w)
shoulder_u = i64[capacity]
shoulder_v = i64[capacity]
shoulder_w = i64[capacity]
shoulder_rank = ffpe_plant_split(base_u, base_v, base_w, base_rank, shoulder_u, shoulder_v, shoulder_w, 0) ## i64
z = ffpemt_expect("split shoulder made", shoulder_rank == 8 && ffpe_verify(shoulder_u, shoulder_v, shoulder_w, shoulder_rank, n, n, n) == 1)
shoulder = i64[ffw_state_size(capacity)]
loaded = ffw_init_terms_cap(shoulder, shoulder_u, shoulder_v, shoulder_w, shoulder_rank, n, capacity, 88103, 0, 1, 1, 1) ## i64
shoulder_path = "/tmp/metaflip_pooled_exact_test_shoulder.txt"
z = ffpemt_expect("split shoulder serialized", loaded == shoulder_rank && ffw_dump_current(shoulder, shoulder_path) == shoulder_rank)

mode_output = "/tmp/metaflip_pooled_exact_test_mode.txt"
mode_meta = i64[20]
mode_rank = ffpem_run(shoulder_path, mode_output, n, 1, 3, 97, mode_meta) ## i64
z = ffpemt_expect("mode worker recovers debt", mode_rank == 7 && mode_meta[15] == 1)

debt_output = "/tmp/metaflip_pooled_exact_test_debt.txt"
debt_meta = i64[20]
debt_rank = ffpem_run(shoulder_path, debt_output, n, 5, 200, 0, debt_meta) ## i64
z = ffpemt_expect("debt worker recovers debt", debt_rank == 7 && debt_meta[15] == 1)

n7 = 7 ## i64
cap7 = ffw_default_capacity(n7) ## i64
source7 = i64[ffw_state_size(cap7)]
source7_rank = ffw_load_scheme_cap(source7, root + "matmul_7x7_rank247_d3098_global_isotropy_gf2.txt", n7, cap7, 88107, 0, 1, 1, 1) ## i64
z = ffpemt_expect("7x7 source exact", source7_rank == 247 && ffw_verify_best_exact(source7, n7) == 1)
source7_u = i64[cap7]
source7_v = i64[cap7]
source7_w = i64[cap7]
z = ffw_export_best(source7, source7_u, source7_v, source7_w)
window0 = i64[8]
window1 = i64[8]
z = ffpemt_expect("syzygy base window", ffds_window(source7_u, source7_v, source7_w, source7_rank, 8, 1, window0) == 8)
z = ffpemt_expect("syzygy nonce-offset window", ffds_window(source7_u, source7_v, source7_w, source7_rank, 8, 20, window1) == 8 && window0[0] != window1[0])

syzygy_output = "/tmp/metaflip_pooled_exact_test_syzygy.txt"
syzygy_meta = i64[20]
syzygy_rank = ffpem_run(root + "matmul_7x7_rank247_d3098_global_isotropy_gf2.txt", syzygy_output, n7, 10, 50, 0, syzygy_meta) ## i64
z = ffpemt_expect("dynamic syzygy exact density win", syzygy_rank == 247 && syzygy_meta[4] == 3098 && syzygy_meta[13] == 3096 && syzygy_meta[15] == 1)

<< "PASS pooled exact moves"
