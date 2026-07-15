use flipfleet_block_leaf_pool

# Authoritative exact-gated materialiser for one balanced small-cross recipe
# under either checked-in rank-47 outer.
#
#   flipfleet-block-outer47-small-cross-compose d450|d450-tie|d677 NxMxP OUTPUT

-> ffbo47c_parse_target(text, dims) (String i64[]) i64
  fields = text.split("x")
  if fields.size() != 3
    return 0
  i = 0 ## i64
  while i < 3
    dims[i] = fields[i].to_i()
    if dims[i] < 8 || dims[i] > 32
      return 0
    i += 1
  if dims[0] > dims[1] || dims[1] > dims[2] || dims[0] > 11
    return 0
  1

av = argv()
if av.size() != 3 || (av[0] != "d450" && av[0] != "d450-tie" && av[0] != "d677")
  << "usage: flipfleet-block-outer47-small-cross-compose d450|d450-tie|d677 NxMxP OUTPUT"
  exit(1)
dims = i64[3]
if ffbo47c_parse_target(av[1], dims) != 1
  << "target must be sorted with 8 <= n <= 11 and p <= 32"
  exit(1)

root = "benchmarks/matmul/metaflip/"
outer_path = "matmul_4x4_rank47_d450_gf2.txt"
if av[0] == "d677"
  outer_path = "matmul_4x4_rank47_d677_flips_gf2.txt"
outer = ffbc_load_exact(root + outer_path, 4, 4, 4, 128)
leaves = ffbcp_stable_2_to_8(root)
if outer == nil || leaves.size() != 84
  << "invalid outer or incomplete exact leaf pool"
  exit(1)
recipe = ffbc_best_oriented_balanced_recipe(outer, dims[0], dims[1], dims[2], leaves)
if av[0] == "d450-tie"
  recipe = ffbc_best_exact_oriented_balanced_recipe(outer, dims[0], dims[1], dims[2], leaves)
if recipe == nil
  << "no balanced recipe"
  exit(1)
source = ffbc_compose(outer, recipe[0], recipe[1], recipe[2], leaves)
if source == nil
  << "exact source composition failed"
  exit(1)
result = source
if recipe[7] != 0
  result = ffbc_orient_scheme(source, recipe[7])
if result == nil || result.n() != dims[0] || result.m() != dims[1] || result.p() != dims[2] || ffbc_verify_exact(result) != 1
  << "exact composition failed"
  exit(1)
if ffbc_write(av[2], result) != result.rank()
  << "write failed: " + av[2]
  exit(1)
row = av[0] + " " + av[1] + " formula=" + recipe[3].to_s() + " exact=" + result.rank().to_s()
row = row + " zero=" + source.compose_zero_terms().to_s() + " parity=" + source.compose_parity_reduction().to_s()
row = row + " source=" + recipe[4].to_s() + "x" + recipe[5].to_s() + "x" + recipe[6].to_s() + " s3=" + recipe[7].to_s()
<< row
<< "allocation " + recipe[0].join(",") + " | " + recipe[1].join(",") + " | " + recipe[2].join(",")
<< "wrote " + av[2]
