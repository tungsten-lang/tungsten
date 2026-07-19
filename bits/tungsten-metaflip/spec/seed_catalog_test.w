use core/system
use ../lib/metaflip/kernels/policy
use ../lib/metaflip/seeds/catalog
use ../lib/metaflip/scheme

failures = 0 ## i64

-> seed_expect(label, condition) (String bool) i64
  if condition == 0
    << "FAIL " + label
    return 1
  0

expected = "seeds/gf2/matmul_7x7_rank247_d3094_three_flip_density_gf2.txt"
frontier = ffp_frontier_seed_paths(7)
failures += seed_expect("d3094 is the 7x7 default", ffp_seed_path(7) == expected)
failures += seed_expect("d3094 is the first frontier seed", frontier.size() > 0 && frontier[0] == expected)
failures += seed_expect("d3096 parent follows the leader", frontier.size() > 1 && frontier[1].ends_with?("matmul_7x7_rank247_d3096_dynamic_syzygy_gf2.txt"))
failures += seed_expect("d3098 diversity follows the parent", frontier.size() > 2 && frontier[2].ends_with?("matmul_7x7_rank247_d3098_global_isotropy_gf2.txt"))
failures += seed_expect("7x7 frontier keeps 16 doors", frontier.size() == 16)
failures += seed_expect("beam-far CUDA child replaces its parent", frontier.size() > 7 && frontier[7].ends_with?("matmul_7x7_rank247_d3096_partial_auto_beam_far_cuda_epoch1849_gf2.txt"))
failures += seed_expect("affine CUDA child replaces its parent", frontier.size() > 15 && frontier[15].ends_with?("matmul_7x7_rank247_d3096_affine_code_cuda_epoch3306_gf2.txt"))
experimental = ffp_experimental_seed_paths(7)
failures += seed_expect("c013 CUDA child remains explicit-only", experimental.size() == 1 && experimental[0].ends_with?("matmul_7x7_rank247_d3492_outer_isotropy_c013_cuda_epoch67_experimental_gf2.txt"))

runtime_root = __DIR__ + "/../lib/metaflip/"
capacity = 320 ## i64
state = i64[ffw_state_size(capacity)]
rank = ffw_load_scheme_cap(state, runtime_root + expected, 7, capacity, 77007, 0, 1, 1, 1) ## i64
failures += seed_expect("d3094 seed loads at rank 247", rank == 247)
failures += seed_expect("d3094 seed reports density 3094", rank == 247 && ffw_best_bits(state) == 3094)
failures += seed_expect("d3094 seed passes the full exact gate", rank == 247 && ffw_verify_best_exact(state, 7) != 0)

manifest = read_file(runtime_root + "manifests/seeds.tsv")
failures += seed_expect("d3094 provenance is manifested", manifest != nil && manifest.include?("matmul_7x7_rank247_d3094_three_flip_density_gf2.txt\t56277df5a94ebfa161e25d34d82c0479f2a8ad07e51a224cdb772fcba7a935b5\t"))
failures += seed_expect("cloud seed provenance is manifested", manifest != nil && manifest.include?("matmul_7x7_rank247_d3096_partial_auto_beam_far_cuda_epoch1849_gf2.txt\t6b308083887f1bab57ddf476afdf4e6ec6f5fca28cc477e6e62e89b413cb3e64\t") && manifest.include?("matmul_7x7_rank247_d3096_affine_code_cuda_epoch3306_gf2.txt\tb8af658635eae896fe7111666925bbd4c6bb65ac1b64a47db8ff3bbb65387b92\t") && manifest.include?("matmul_7x7_rank247_d3492_outer_isotropy_c013_cuda_epoch67_experimental_gf2.txt\t22253929088e257612f9d2d8dfda128e0ee1b3955f644d403be90858e19b7ba8\t"))

if failures > 0
  << "metaflip seed catalog: " + failures.to_s() + " failure(s)"
  exit(1)

<< "metaflip seed catalog: d3094 default, dual d3096 cloud children active, d3492 explicit, exact=1"
