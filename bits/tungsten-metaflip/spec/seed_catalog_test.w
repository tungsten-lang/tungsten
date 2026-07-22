use core/system
use ../lib/metaflip/kernels/policy
use ../lib/metaflip/seeds/catalog
use ../lib/metaflip/scheme

failures = 0 ## i64

-> seed_expect(label, condition) (String bool) i64
  if !condition
    << "FAIL " + label
    return 1
  0

expected = "seeds/gf2/matmul_7x7_rank247_d3094_three_flip_density_gf2.txt"
frontier = ffp_frontier_seed_paths(7)
failures += seed_expect("d3094 is the 7x7 default", ffp_seed_path(7) == expected)
failures += seed_expect("d3094 is the first frontier seed", frontier.size() > 0 && frontier[0] == expected)
failures += seed_expect("d3096 parent follows the leader", frontier.size() > 1 && frontier[1].ends_with?("matmul_7x7_rank247_d3096_dynamic_syzygy_gf2.txt"))
failures += seed_expect("d3098 diversity follows the parent", frontier.size() > 2 && frontier[2].ends_with?("matmul_7x7_rank247_d3098_global_isotropy_gf2.txt"))
failures += seed_expect("7x7 frontier keeps 18 doors", frontier.size() == 18)
failures += seed_expect("beam-far CUDA child replaces its parent", frontier.size() > 7 && frontier[7].ends_with?("matmul_7x7_rank247_d3096_partial_auto_beam_far_cuda_epoch1849_gf2.txt"))
failures += seed_expect("fertile d3486 C013 continuation owns the pocket basin slot", frontier.size() > 10 && frontier[10].ends_with?("matmul_7x7_rank247_d3486_c013_runpod_epoch1965_continuation_gf2.txt"))
failures += seed_expect("autonomous pocket replay child follows promoted child", frontier.size() > 11 && frontier[11].ends_with?("matmul_7x7_rank247_d3546_autonomous_flip_pocket_gf2.txt"))
failures += seed_expect("epoch-257 affine CUDA child owns its basin slot", frontier.size() > 17 && frontier[17].ends_with?("matmul_7x7_rank247_d3094_affine_code_cuda_epoch257_gf2.txt"))
experimental = ffp_experimental_seed_paths(7)
failures += seed_expect("dominated parents remain explicit-only", experimental.size() == 4 && experimental[0].ends_with?("matmul_7x7_rank247_d3496_fixed_rank_pocket_greedy_closure_gf2.txt") && experimental[1].ends_with?("matmul_7x7_rank247_d3492_outer_isotropy_c013_cuda_epoch67_gf2.txt") && experimental[2].ends_with?("matmul_7x7_rank247_d3538_peterson_2026_runpod_cuda_epoch27_novelty_gf2.txt") && experimental[3].ends_with?("matmul_7x7_rank247_d3096_affine_code_cuda_epoch3306_gf2.txt"))
low_quota = ffp_low_quota_seed_paths(7)
failures += seed_expect("Runpod d3542 is the sole low-quota 7x7 source", low_quota.size() == 1 && low_quota[0].ends_with?("matmul_7x7_rank247_d3542_c013_runpod_cuda_epoch1965_g6417_gf2.txt"))

runtime_root = __DIR__ + "/../lib/metaflip/"
capacity = 320 ## i64
state = i64[ffw_state_size(capacity)]
rank = ffw_load_scheme_cap(state, runtime_root + expected, 7, capacity, 77007, 0, 1, 1, 1) ## i64
failures += seed_expect("d3094 seed loads at rank 247", rank == 247)
failures += seed_expect("d3094 seed reports density 3094", rank == 247 && ffw_best_bits(state) == 3094)
failures += seed_expect("d3094 seed passes the full exact gate", rank == 247 && ffw_verify_best_exact(state, 7) != 0)

manifest = read_file(runtime_root + "manifests/seeds.tsv")
failures += seed_expect("d3094 provenance is manifested", manifest != nil && manifest.include?("matmul_7x7_rank247_d3094_three_flip_density_gf2.txt\t56277df5a94ebfa161e25d34d82c0479f2a8ad07e51a224cdb772fcba7a935b5\t"))
failures += seed_expect("cloud seed provenance is manifested", manifest != nil && manifest.include?("matmul_7x7_rank247_d3096_partial_auto_beam_far_cuda_epoch1849_gf2.txt\t6b308083887f1bab57ddf476afdf4e6ec6f5fca28cc477e6e62e89b413cb3e64\t") && manifest.include?("matmul_7x7_rank247_d3094_affine_code_cuda_epoch257_gf2.txt\tddf710feced82ece388d9e368f9ad4bcf4da08d0583c4b17ab34a8a5e1accb71\t") && manifest.include?("matmul_7x7_rank247_d3096_affine_code_cuda_epoch3306_gf2.txt\tb8af658635eae896fe7111666925bbd4c6bb65ac1b64a47db8ff3bbb65387b92\t") && manifest.include?("matmul_7x7_rank247_d3486_c013_runpod_epoch1965_continuation_gf2.txt\tdfab762a6150c274b670f67f6169d3635c32974c0be106482717b94fae149b05\t") && manifest.include?("matmul_7x7_rank247_d3492_outer_isotropy_c013_cuda_epoch67_gf2.txt\t22253929088e257612f9d2d8dfda128e0ee1b3955f644d403be90858e19b7ba8\t") && manifest.include?("matmul_7x7_rank247_d3542_c013_runpod_cuda_epoch1965_g6417_gf2.txt\tbc0d913f34d0b733436059e16775bbff3c8f29e3306bd5b8e29de4f05a05b676\t"))
failures += seed_expect("autonomous pocket provenance is manifested", manifest != nil && manifest.include?("matmul_7x7_rank247_d3546_autonomous_flip_pocket_gf2.txt\tf59cac07c5497fe5ebe18f019151f8951f15b0c97ab253f915b7c0c5a66a61d3\t"))
failures += seed_expect("greedy pocket provenance is manifested", manifest != nil && manifest.include?("matmul_7x7_rank247_d3496_fixed_rank_pocket_greedy_closure_gf2.txt\t09d4242e2f15fcec835681b6ace70f1d3adfc5606f2f79304db8cb26983068c8\t"))
failures += seed_expect("Runpod epoch-27 novelty provenance is manifested", manifest != nil && manifest.include?("matmul_7x7_rank247_d3538_peterson_2026_runpod_cuda_epoch27_novelty_gf2.txt\t0fb2dc8c4d08e83e3c97af99e860d7cf716468682472767f6dbc342beb7b68db\tschemes/GF(2)/7x7x7/r247/peterson-2026-d3538-runpod-cuda-epoch27-g006725-novelty.txt"))

if failures > 0
  << "metaflip seed catalog: " + failures.to_s() + " failure(s)"
  exit(1)

<< "metaflip seed catalog: d3094 default, affine d3094 epoch257 active, d3486 pocket-basin active, four explicit parents, d3542 low-quota, exact=1"
