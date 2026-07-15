use flipfleet_block_leaf_pool

# Sharded exhaustive ordered 2--8 allocation scan for every balanced
# small-cross row, including balanced ties/losses and targets without a pinned
# GF(2) comparator.  Sharding bounds process-lifetime scratch retained by the
# pure-Tungsten research executable while preserving a complete deterministic
# closure when shard rows are sorted by target.
#
#   ffbc-small-cross-unbalanced-full shard-id shard-count

-> ffbscufs_parse(text, dims) (String i64[]) i64
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

-> ffbscufs_status(baseline, rank) (String i64)
  if baseline.size() == 0
    return "uncovered"
  value = baseline.to_i() ## i64
  if rank < value
    return "win"
  if rank == value
    return "tie"
  "loss"

-> ffbscufs_gain(baseline, rank) (String i64)
  if baseline.size() == 0
    return ""
  (baseline.to_i() - rank).to_s()

av = argv()
shard_id = 0 ## i64
shard_count = 1 ## i64
if av.size() == 2
  shard_id = av[0].to_i()
  shard_count = av[1].to_i()
elsif av.size() != 0
  << "usage: ffbc-small-cross-unbalanced-full shard-id shard-count"
  exit(1)
if shard_count < 1 || shard_id < 0 || shard_id >= shard_count
  << "invalid shard"
  exit(1)

root = "benchmarks/matmul/metaflip/"
outer = ffbc_load_exact(root + "matmul_4x4_rank47_d450_gf2.txt", 4, 4, 4, 128)
leaves = ffbcp_stable_2_to_8(root)
audit = read_file(root + "block_composition_small_cross_audit.tsv")
if outer == nil || leaves.size() != 84 || audit == nil
  << "invalid outer, leaf pool, or small-cross audit"
  exit(1)

header = "target\tbalanced_formula\tbounded_formula\timprovement"
header = header + "\tf2_status\tf2_baseline\tf2_gain"
header = header + "\tuniversal_status\tuniversal_baseline\tuniversal_gain"
header = header + "\tchar0_status\tchar0_baseline\tchar0_gain"
header = header + "\tany_field_status\tany_field_baseline\tany_field_gain"
header = header + "\talloc_n\talloc_m\talloc_p\tsource\ts3_code"
<< header

lines = audit.split("\n")
checked = 0 ## i64
formula_improved = 0 ## i64
f2_wins = 0 ## i64
row_index = 0 ## i64
i = 1 ## i64
while i < lines.size()
  if lines[i].size() > 0
    fields = lines[i].split("\t")
    if fields.size() != 28
      << "malformed audit row " + i.to_s()
      exit(1)
    if row_index % shard_count == shard_id
      dims = i64[3]
      if ffbscufs_parse(fields[0], dims) != 1
        << "malformed target " + fields[0]
        exit(1)
      balanced = fields[1].to_i() ## i64
      recipe = ffbc_best_oriented_bounded_recipe(outer, dims[0], dims[1], dims[2], 2, 8, leaves)
      if recipe == nil || recipe[3] > balanced
        << "bounded scan failed or regressed " + fields[0]
        exit(1)
      bounded = recipe[3] ## i64
      improvement = balanced - bounded ## i64
      if improvement > 0
        formula_improved += 1
      f2_status = ffbscufs_status(fields[4], bounded)
      if f2_status == "win"
        f2_wins += 1

      row = fields[0] + "\t" + balanced.to_s() + "\t" + bounded.to_s() + "\t" + improvement.to_s()
      row = row + "\t" + f2_status + "\t" + fields[4] + "\t" + ffbscufs_gain(fields[4], bounded)
      row = row + "\t" + ffbscufs_status(fields[9], bounded) + "\t" + fields[9] + "\t" + ffbscufs_gain(fields[9], bounded)
      row = row + "\t" + ffbscufs_status(fields[14], bounded) + "\t" + fields[14] + "\t" + ffbscufs_gain(fields[14], bounded)
      row = row + "\t" + ffbscufs_status(fields[19], bounded) + "\t" + fields[19] + "\t" + ffbscufs_gain(fields[19], bounded)
      row = row + "\t" + recipe[0].join(",") + "\t" + recipe[1].join(",") + "\t" + recipe[2].join(",")
      row = row + "\t" + recipe[4].to_s() + "x" + recipe[5].to_s() + "x" + recipe[6].to_s() + "\t" + recipe[7].to_s()
      << row
      checked += 1
    row_index += 1
  i += 1

summary = "SUMMARY shard=" + shard_id.to_s() + "/" + shard_count.to_s()
summary = summary + " checked=" + checked.to_s() + " formula_improved=" + formula_improved.to_s()
summary = summary + " f2_wins=" + f2_wins.to_s()
<< summary
