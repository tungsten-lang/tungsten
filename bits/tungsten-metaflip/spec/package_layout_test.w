use core/system
use ../lib/metaflip/seeds/catalog
use ../lib/metaflip/seeds/rect
use ../lib/metaflip/rect/policy
use ../lib/metaflip/kernels/bundles/generic
use ../lib/metaflip/kernels/bundles/c3
use ../lib/metaflip/kernels/bundles/simd
use ../lib/metaflip/kernels/bundles/rect
use ../lib/metaflip/kernels/bundles/pooled_exact
use ../lib/metaflip/kernels/metallib_cache
use ../lib/metaflip/paths
use ../tools/cal2zone_generator

failures = 0 ## i64

-> package_expect(label, condition) (String bool) i64
  if !condition
    << "FAIL " + label
    return 1
  0

# Every bundled cal2zone worker must be exactly what tools/gen_cal2zone.w
# renders from tools/cal2zone.template and the runtime geometry tables, so a
# hand edit to one clone, or a geometry change without a regeneration, fails
# here instead of drifting.
-> package_expect_generated_workers(runtime_root, template_path) (String String) i64
  template = read_file(template_path)
  if template == nil
    return package_expect("cal2zone template is packaged", false)
  failures = 0 ## i64
  codes = ffgz_shapes()
  i = 0
  while i < codes.size()
    code = codes[i] ## i64
    family = ffgz_family(code)
    n = ffgz_code_n(code) ## i64
    m = ffgz_code_m(code) ## i64
    p = ffgz_code_p(code) ## i64
    rel = ffgz_rel_path(family, n, m, p)
    expected = ffgz_render(template, family, n, m, p)
    actual = read_file(runtime_root + "/kernels/" + rel)
    failures += package_expect("kernels/" + rel + " matches tools/cal2zone.template", expected != "" && actual != nil && actual == expected)
    i += 1
  failures

# Every supported rectangular profile now ships a generated GPU worker, and
# the portfolio policy must advertise exactly the shapes the bundle can build.
-> package_expect_rect_gpu_coverage() i64
  failures = 0 ## i64
  n = 2
  while n <= 9
    m = 2
    while m <= 9
      p = 2
      while p <= 9
        if ffrp_supported(n, m, p) == 1
          label = n.to_s() + "x" + m.to_s() + "x" + p.to_s()
          failures += package_expect(label + " has valid GPU geometry", ffrgb_geometry_valid(n, m, p) == 1)
          failures += package_expect(label + " policy GPU capability matches the bundle", ffrpp_default_gpu_capable(n * 100 + m * 10 + p) == ffrgb_supported(n, m, p))
        p += 1
      m += 1
    n += 1
  failures

package_root = __DIR__ + "/.."
runtime_root = package_root + "/lib/metaflip"
canonical_runtime_root = ffls_canonical_dir(runtime_root)

failures += package_expect("relative runtime root canonicalizes", canonical_runtime_root.starts_with?("/") && read_file(canonical_runtime_root + "/fleet.w") != nil)

failures += package_expect("square seed is packaged", read_file(runtime_root + "/" + ffp_seed_path(5)) != nil)
failures += package_expect("rectangular seed is packaged", read_file(runtime_root + "/" + ffrp_seed_rel(3, 4, 6)) != nil)
failures += package_expect("227 d128 is the packaged default", ffrp_seed_rel(2, 2, 7).ends_with?("matmul_2x2x7_rank25_d128_rect_portfolio_gf2.txt"))
failures += package_expect("227 preserves d132 and +1/+2 doors", ffrp_frontier_seed_count(2, 2, 7) == 4 && ffrp_frontier_seed_rel(2, 2, 7, 1).ends_with?("matmul_2x2x7_rank25_catalog_gf2.txt") && ffrp_frontier_seed_rel(2, 2, 7, 2).ends_with?("rank26_isotropy_split_plus1_gf2.txt") && ffrp_frontier_seed_rel(2, 2, 7, 3).ends_with?("rank27_isotropy_split_plus2_gf2.txt"))
failures += package_expect("227 d128 seed is packaged", read_file(runtime_root + "/" + ffrp_seed_rel(2, 2, 7)) != nil)
failures += package_expect("229 preserves R/R+1/R+2 doors", ffrp_frontier_seed_count(2, 2, 9) == 5 && ffrp_frontier_seed_rel(2, 2, 9, 3).ends_with?("rank33_d159_isotropy_split_plus1_gf2.txt") && ffrp_frontier_seed_rel(2, 2, 9, 4).ends_with?("rank34_d165_isotropy_split_plus2_gf2.txt"))
failures += package_expect("229 rank-debt doors are packaged", read_file(runtime_root + "/" + ffrp_frontier_seed_rel(2, 2, 9, 3)) != nil && read_file(runtime_root + "/" + ffrp_frontier_seed_rel(2, 2, 9, 4)) != nil)
package_sums = read_file(runtime_root + "/SHA256SUMS")
failures += package_expect("229 rank-debt doors are checksummed", package_sums != nil && package_sums.include?("matmul_2x2x9_rank33_d159_isotropy_split_plus1_gf2.txt") && package_sums.include?("matmul_2x2x9_rank34_d165_isotropy_split_plus2_gf2.txt"))
failures += package_expect("225 keeps the AWS disjoint archive door", ffrp_frontier_seed_count(2, 2, 5) == 6 && ffrp_frontier_seed_rel(2, 2, 5, 5).ends_with?("matmul_2x2x5_rank18_d141_peterson_2026_aws_disjoint_gf2.txt") && read_file(runtime_root + "/" + ffrp_frontier_seed_rel(2, 2, 5, 5)) != nil)
failures += package_expect("334 keeps the AWS disjoint archive door", ffrp_frontier_seed_count(3, 3, 4) == 4 && ffrp_frontier_seed_rel(3, 3, 4, 1).ends_with?("matmul_3x3x4_rank29_d249_peterson_2026_aws_disjoint_gf2.txt") && read_file(runtime_root + "/" + ffrp_frontier_seed_rel(3, 3, 4, 1)) != nil)
failures += package_expect("344 d280 is the packaged default", ffrp_seed_rel(3, 4, 4).ends_with?("matmul_3x4x4_rank38_d280_live_density_leader_gf2.txt"))
failures += package_expect("344 preserves R/R+1/R+2 and AWS doors", ffrp_frontier_seed_count(3, 4, 4) == 5 && ffrp_frontier_seed_rel(3, 4, 4, 1).ends_with?("matmul_3x4x4_rank38_gf2.txt") && ffrp_frontier_seed_rel(3, 4, 4, 2).ends_with?("matmul_3x4x4_rank38_d310_peterson_2026_aws_disjoint_gf2.txt") && ffrp_frontier_seed_rel(3, 4, 4, 3).include?("rank39_peterson_2026_isotropy_split_plus1") && ffrp_frontier_seed_rel(3, 4, 4, 4).include?("rank40_peterson_2026_isotropy_split_plus2"))
failures += package_expect("344 d280 seed is packaged", read_file(runtime_root + "/" + ffrp_seed_rel(3, 4, 4)) != nil)
near7 = ffp_near_seed_paths(7, 1)
failures += package_expect("7x7 +1 shoulders are packaged", near7.size() == 2 && near7[0].ends_with?("matmul_7x7_rank248_d2946_live_density_leader_gf2.txt") && near7[1].ends_with?("matmul_7x7_rank248_d3092_aws_near1_local_gf2.txt") && read_file(runtime_root + "/" + near7[0]) != nil && read_file(runtime_root + "/" + near7[1]) != nil)
failures += package_expect("AWS campaign promotions are checksummed", package_sums != nil && package_sums.include?("matmul_2x2x5_rank18_d141_peterson_2026_aws_disjoint_gf2.txt") && package_sums.include?("matmul_3x3x4_rank29_d249_peterson_2026_aws_disjoint_gf2.txt") && package_sums.include?("matmul_3x4x4_rank38_d310_peterson_2026_aws_disjoint_gf2.txt") && package_sums.include?("matmul_7x7_rank248_d2946_live_density_leader_gf2.txt") && package_sums.include?("matmul_7x7_rank248_d3092_aws_near1_local_gf2.txt"))
failures += package_expect("456 d906 is the packaged default", ffrp_seed_rel(4, 5, 6).ends_with?("matmul_4x5x6_rank90_d906_rect_portfolio_gf2.txt"))
failures += package_expect("456 preserves three doors", ffrp_frontier_seed_count(4, 5, 6) == 3 && ffrp_frontier_seed_rel(4, 5, 6, 1).ends_with?("matmul_4x5x6_rank90_d907_gl_frontier_gf2.txt") && ffrp_frontier_seed_rel(4, 5, 6, 2).ends_with?("matmul_4x5x6_rank90_catalog_gf2.txt"))
failures += package_expect("456 d906 seed is packaged", read_file(runtime_root + "/" + ffrp_seed_rel(4, 5, 6)) != nil)
failures += package_expect("rect leverage audit is current", ffrpp_default_leverage(346) == 1679 && ffrpp_default_leverage(347) == 1458 && ffrpp_default_leverage(445) == 1411 && ffrpp_default_leverage(356) == 1638)
failures += package_expect("generic GPU worker is packaged", read_file(ffb_source_path(runtime_root, 5)) != nil)
failures += package_expect("generated Metal sidecar is not packaged", read_file(runtime_root + "/kernels/generic/cal2zone_555.metal") == nil)
failures += package_expect("C3 worker is packaged", read_file(ffc3_source_path(runtime_root, 5)) != nil)
failures += package_expect("SIMD worker is packaged", read_file(ffsimd_source_path(runtime_root, 5)) != nil)
failures += package_expect("rectangular worker is packaged", read_file(ffrgb_source_path(runtime_root, 2, 2, 5)) != nil)
failures += package_expect("226 GPU geometry is packaged", ffrgb_geometry_valid(2, 2, 6) == 1 && ffrgb_cap(2, 2, 6) == 64 && ffrgb_shared_bytes(2, 2, 6) == 12288)
failures += package_expect("346 GPU geometry is packaged", ffrgb_geometry_valid(3, 4, 6) == 1 && ffrgb_cap(3, 4, 6) == 104 && ffrgb_shared_bytes(3, 4, 6) == 19968)
failures += package_expect("347 GPU geometry is packaged", ffrgb_geometry_valid(3, 4, 7) == 1 && ffrgb_cap(3, 4, 7) == 116 && ffrgb_shared_bytes(3, 4, 7) == 22272)
failures += package_expect("356 GPU geometry is packaged", ffrgb_geometry_valid(3, 5, 6) == 1 && ffrgb_cap(3, 5, 6) == 122 && ffrgb_shared_bytes(3, 5, 6) == 23424)
failures += package_expect("446 GPU geometry is packaged", ffrgb_geometry_valid(4, 4, 6) == 1 && ffrgb_cap(4, 4, 6) == 128 && ffrgb_wpg(4, 4, 6) == 16 && ffrgb_mask_bytes(4, 4, 6) == 4 && ffrgb_shared_bytes(4, 4, 6) == 24576)
failures += package_expect("456 GPU geometry is packaged", ffrgb_geometry_valid(4, 5, 6) == 1 && ffrgb_cap(4, 5, 6) == 152 && ffrgb_wpg(4, 5, 6) == 16 && ffrgb_mask_bytes(4, 5, 6) == 4 && ffrgb_shared_bytes(4, 5, 6) == 29184)
failures += package_expect("457 wide GPU geometry is packaged", ffrgb_geometry_valid(4, 5, 7) == 1 && ffrgb_cap(4, 5, 7) == 168 && ffrgb_wpg(4, 5, 7) == 8 && ffrgb_mask_bytes(4, 5, 7) == 8 && ffrgb_shared_bytes(4, 5, 7) == 32256)
failures += package_expect("467 wide GPU geometry is packaged", ffrgb_geometry_valid(4, 6, 7) == 1 && ffrgb_cap(4, 6, 7) == 168 && ffrgb_wpg(4, 6, 7) == 8 && ffrgb_mask_bytes(4, 6, 7) == 8 && ffrgb_shared_bytes(4, 6, 7) == 32256)
failures += package_expect("357 wide GPU geometry is packaged", ffrgb_geometry_valid(3, 5, 7) == 1 && ffrgb_cap(3, 5, 7) == 128 && ffrgb_wpg(3, 5, 7) == 8 && ffrgb_mask_bytes(3, 5, 7) == 8 && ffrgb_shared_bytes(3, 5, 7) == 24576)
failures += package_expect("455 GPU geometry is packaged", ffrgb_geometry_valid(4, 5, 5) == 1 && ffrgb_cap(4, 5, 5) == 128 && ffrgb_wpg(4, 5, 5) == 16 && ffrgb_mask_bytes(4, 5, 5) == 4 && ffrgb_shared_bytes(4, 5, 5) == 24576)
failures += package_expect("458 wide GPU geometry is packaged", ffrgb_geometry_valid(4, 5, 8) == 1 && ffrgb_cap(4, 5, 8) == 168 && ffrgb_wpg(4, 5, 8) == 8 && ffrgb_mask_bytes(4, 5, 8) == 8 && ffrgb_shared_bytes(4, 5, 8) == 32256)
failures += package_expect("466 wide GPU geometry is packaged", ffrgb_geometry_valid(4, 6, 6) == 1 && ffrgb_cap(4, 6, 6) == 160 && ffrgb_wpg(4, 6, 6) == 8 && ffrgb_mask_bytes(4, 6, 6) == 8 && ffrgb_shared_bytes(4, 6, 6) == 30720)
failures += package_expect("468 wide GPU geometry is packaged", ffrgb_geometry_valid(4, 6, 8) == 1 && ffrgb_cap(4, 6, 8) == 170 && ffrgb_wpg(4, 6, 8) == 8 && ffrgb_mask_bytes(4, 6, 8) == 8 && ffrgb_shared_bytes(4, 6, 8) == 32640)
failures += package_expect("567 wide GPU geometry is packaged", ffrgb_geometry_valid(5, 6, 7) == 1 && ffrgb_cap(5, 6, 7) == 200 && ffrgb_wpg(5, 6, 7) == 4 && ffrgb_mask_bytes(5, 6, 7) == 8 && ffrgb_shared_bytes(5, 6, 7) == 19200)
failures += package_expect_rect_gpu_coverage()
failures += package_expect_generated_workers(runtime_root, package_root + "/tools/cal2zone.template")
failures += package_expect("seed provenance manifest is packaged", read_file(runtime_root + "/manifests/seeds.tsv") != nil)
failures += package_expect("greedy pocket seed is packaged", read_file(runtime_root + "/seeds/gf2/matmul_7x7_rank247_d3496_fixed_rank_pocket_greedy_closure_gf2.txt") != nil && package_sums != nil && package_sums.include?("matmul_7x7_rank247_d3496_fixed_rank_pocket_greedy_closure_gf2.txt"))
failures += package_expect("Runpod epoch-1965 C013 endpoint and former active parent are packaged", read_file(runtime_root + "/seeds/gf2/matmul_7x7_rank247_d3486_c013_runpod_epoch1965_continuation_gf2.txt") != nil && read_file(runtime_root + "/seeds/gf2/matmul_7x7_rank247_d3492_outer_isotropy_c013_cuda_epoch67_gf2.txt") != nil && package_sums != nil && package_sums.include?("matmul_7x7_rank247_d3486_c013_runpod_epoch1965_continuation_gf2.txt") && package_sums.include?("matmul_7x7_rank247_d3492_outer_isotropy_c013_cuda_epoch67_gf2.txt"))
failures += package_expect("Runpod epoch-257 affine density co-leader and parent are packaged", read_file(runtime_root + "/seeds/gf2/matmul_7x7_rank247_d3094_affine_code_cuda_epoch257_gf2.txt") != nil && read_file(runtime_root + "/seeds/gf2/matmul_7x7_rank247_d3096_affine_code_cuda_epoch3306_gf2.txt") != nil && package_sums != nil && package_sums.include?("matmul_7x7_rank247_d3094_affine_code_cuda_epoch257_gf2.txt") && package_sums.include?("matmul_7x7_rank247_d3096_affine_code_cuda_epoch3306_gf2.txt"))
failures += package_expect("Runpod low-quota source and epoch-27 parent are packaged", read_file(runtime_root + "/seeds/gf2/matmul_7x7_rank247_d3542_c013_runpod_cuda_epoch1965_g6417_gf2.txt") != nil && read_file(runtime_root + "/seeds/gf2/matmul_7x7_rank247_d3538_peterson_2026_runpod_cuda_epoch27_novelty_gf2.txt") != nil && package_sums != nil && package_sums.include?("matmul_7x7_rank247_d3542_c013_runpod_cuda_epoch1965_g6417_gf2.txt") && package_sums.include?("matmul_7x7_rank247_d3538_peterson_2026_runpod_cuda_epoch27_novelty_gf2.txt"))
failures += package_expect("CLI source is packaged", read_file(package_root + "/bin/metaflip.w") != nil)
bitfile_source = read_file(package_root + "/Bitfile")
failures += package_expect("Bit executable targets CLI source", bitfile_source != nil && bitfile_source.include?("executable  \"metaflip\", source: \"bin/metaflip.w\""))
failures += package_expect("public library entry is packaged", read_file(package_root + "/lib/metaflip.w") != nil)
public_library_source = read_file(package_root + "/lib/metaflip.w")
failures += package_expect("proof facade is publicly linked", public_library_source != nil && public_library_source.include?("use metaflip/proof"))
failures += package_expect("generic search facade is publicly linked", public_library_source != nil && public_library_source.include?("use metaflip/search"))
failures += package_expect("finite-map facade is publicly linked", public_library_source != nil && public_library_source.include?("use metaflip/search/finite_map"))
failures += package_expect("pure-Tungsten proof engines are packaged", read_file(runtime_root + "/proof.w") != nil && read_file(runtime_root + "/proof/cdcl.w") != nil && read_file(runtime_root + "/proof/psi.w") != nil)
failures += package_expect("domain-neutral exact search is packaged", read_file(runtime_root + "/search.w") != nil)
failures += package_expect("finite-map search adapter is packaged", read_file(runtime_root + "/search/finite_map.w") != nil)
failures += package_expect("rank-down endpoint compiler is packaged", read_file(runtime_root + "/strategies/rect_endpoint_rankdown.w") != nil)
failures += package_expect("rank-two endpoint compiler is packaged", read_file(runtime_root + "/strategies/rect_endpoint_rankdown2.w") != nil)
failures += package_expect("four-line catalyst compiler is packaged", read_file(runtime_root + "/strategies/rect_catalyst_lift2.w") != nil)
failures += package_expect("double-annihilation macro is packaged", read_file(runtime_root + "/strategies/macro_double_annihilation.w") != nil)
failures += package_expect("block-interior selector is packaged", read_file(runtime_root + "/strategies/block_interior.w") != nil)
failures += package_expect("rectangular block-interior resident is packaged", read_file(runtime_root + "/strategies/rect_block_interior.w") != nil)
failures += package_expect("pooled exact strategies are packaged", read_file(runtime_root + "/strategies/mode_locked.w") != nil && read_file(runtime_root + "/strategies/debt_mitm.w") != nil && read_file(runtime_root + "/strategies/dynamic_syzygy.w") != nil)
failures += package_expect("pooled exact worker is packaged", read_file(runtime_root + "/kernels/workers/pooled_exact.w") != nil && read_file(runtime_root + "/kernels/pooled_exact.w") != nil && read_file(runtime_root + "/kernels/bundles/pooled_exact.w") != nil)
failures += package_expect("best provenance module is packaged", read_file(runtime_root + "/fleet/provenance.w") != nil)
fleet_source = read_file(runtime_root + "/fleet.w")
failures += package_expect("block selector participates in worker freshness", fleet_source != nil && fleet_source.include?("span_block_interior"))
rect_campaign_source = read_file(runtime_root + "/rect/campaign.w")
failures += package_expect("persistent rectangular CPU pool is packaged and linked", read_file(runtime_root + "/rect/cpu_pool.w") != nil && rect_campaign_source != nil && rect_campaign_source.include?("use cpu_pool"))
failures += package_expect("rectangular block resident is linked", rect_campaign_source != nil && rect_campaign_source.include?("use ../strategies/rect_block_interior") && rect_campaign_source.include?("ffrbi_next_period"))
failures += package_expect("generated CUDA is not packaged", read_file(runtime_root + "/kernels/generic/cal2zone_555.cu") == nil)

compiler = ffmc_tungsten(runtime_root)
failures += package_expect("compiler resolver returns a command", compiler != "")

build_command = ffb_build_command(runtime_root, 5, "/tmp/metaflip_layout_test_worker")
failures += package_expect("build command uses packaged source", build_command.include?("kernels/generic/cal2zone_555.w"))
failures += package_expect("build command has no monorepo path", !build_command.include?("benchmarks/matmul/metaflip"))
failures += package_expect("native flag removed", !build_command.include?("--native"))
failures += package_expect("runtime compile suppresses incidental dialects", build_command.include?("TUNGSTEN_GPU_DIALECTS=none"))
failures += package_expect("runtime Metal output uses worker cache", build_command.include?("/tmp/metaflip_layout_test_worker.metal"))
exact_build_command = ffpeb_build_command(runtime_root, "/tmp/metaflip_layout_test_exact")
failures += package_expect("pooled exact build is pure Tungsten CPU", exact_build_command.include?("kernels/workers/pooled_exact.w") && exact_build_command.include?("TUNGSTEN_GPU_DIALECTS=none") && !exact_build_command.include?("benchmarks/matmul/metaflip"))

if failures > 0
  << "metaflip package layout: " + failures.to_s() + " failure(s)"
  exit(1)

<< "metaflip package layout: ok"
