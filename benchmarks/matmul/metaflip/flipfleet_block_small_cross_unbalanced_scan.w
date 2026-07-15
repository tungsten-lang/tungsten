use flipfleet_block_leaf_pool

# Exhaustive ordered 2--8 allocation follow-up for the 129 balanced formulas
# that already beat a pinned explicit/reducible GF(2) baseline.  Reading the
# audited candidate list keeps this expensive pass focused on claims that can
# improve, while retaining every S3 source orientation.

-> ffbscus_parse(text, dims) (String i64[]) i64
  fields = text.split("x")
  if fields.size() != 3
    return 0
  i = 0 ## i64
  while i < 3
    dims[i] = fields[i].to_i()
    if dims[i] < 8 || dims[i] > 32
      return 0
    i += 1
  1

root = "benchmarks/matmul/metaflip/"
outer = ffbc_load_exact(root + "matmul_4x4_rank47_d450_gf2.txt", 4, 4, 4, 128)
leaves = ffbcp_stable_2_to_8(root)
audit = read_file(root + "block_composition_small_cross_audit.tsv")
if outer == nil || leaves.size() != 84 || audit == nil
  << "invalid outer, leaf pool, or small-cross audit"
  exit(1)

<< "target\tbalanced_formula\tbounded_formula\timprovement\talloc_n\talloc_m\talloc_p\tsource\ts3_code"
lines = audit.split("\n")
checked = 0 ## i64
improved = 0 ## i64
i = 1 ## i64
while i < lines.size()
  if lines[i].size() > 0
    fields = lines[i].split("\t")
    if fields.size() != 28
      << "malformed audit row " + i.to_s()
      exit(1)
    if fields[3] == "win"
      dims = i64[3]
      if ffbscus_parse(fields[0], dims) != 1
        << "malformed target " + fields[0]
        exit(1)
      balanced = fields[1].to_i() ## i64
      recipe = ffbc_best_oriented_bounded_recipe(outer, dims[0], dims[1], dims[2], 2, 8, leaves)
      if recipe == nil || recipe[3] > balanced
        << "bounded scan failed or regressed " + fields[0]
        exit(1)
      gain = balanced - recipe[3] ## i64
      if gain > 0
        improved += 1
      row = fields[0] + "\t" + balanced.to_s() + "\t" + recipe[3].to_s() + "\t" + gain.to_s()
      row = row + "\t" + recipe[0].join(",") + "\t" + recipe[1].join(",") + "\t" + recipe[2].join(",")
      row = row + "\t" + recipe[4].to_s() + "x" + recipe[5].to_s() + "x" + recipe[6].to_s() + "\t" + recipe[7].to_s()
      << row
      checked += 1
  i += 1
if checked != 129
  << "expected 129 F2 wins, got " + checked.to_s()
  exit(1)
<< "SUMMARY checked=" + checked.to_s() + " improved=" + improved.to_s()
