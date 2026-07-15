use flipfleet_block_leaf_pool

# Support-pattern comparison for the two exact rank-47 <4,4,4> outers over
# the complete exact 2--8 leaf pool.  The checked-in d450 small-cross table is
# replayed row-for-row before the alternate d677 result is accepted.
#
#   flipfleet-block-outer47-small-cross-scan > /tmp/outer47-small-cross.tsv

root = "benchmarks/matmul/metaflip/"
baseline_body = read_file(root + "block_composition_small_cross_scan.tsv")
outer450 = ffbc_load_exact(root + "matmul_4x4_rank47_d450_gf2.txt", 4, 4, 4, 128)
outer677 = ffbc_load_exact(root + "matmul_4x4_rank47_d677_flips_gf2.txt", 4, 4, 4, 128)
leaves = ffbcp_stable_2_to_8(root)
if baseline_body == nil || outer450 == nil || outer677 == nil || leaves.size() != 84
  << "invalid baseline, outer, or incomplete 2--8 leaf pool"
  exit(1)
if outer450.rank() != 47 || outer677.rank() != 47
  << "rank-47 outer check failed"
  exit(1)

baseline_lines = baseline_body.split("\n")
line = 1 ## i64
checked = 0 ## i64
wins = 0 ## i64
ties = 0 ## i64
losses = 0 ## i64
largest_gain = 0 ## i64
largest_loss = 0 ## i64

<< "target\td450_formula\td677_formula\td677_gain\td677_alloc_n\td677_alloc_m\td677_alloc_p\td677_source\td677_s3_code"
n = 8 ## i64
while n <= 11
  m = n ## i64
  while m <= 32
    p = m ## i64
    while p <= 32
      target = n.to_s() + "x" + m.to_s() + "x" + p.to_s()
      if line >= baseline_lines.size()
        << "baseline ended before " + target
        exit(1)
      fields = baseline_lines[line].split("\t")
      if fields.size() != 7 || fields[0] != target
        << "baseline row mismatch at " + target
        exit(1)
      pinned = fields[1].to_i() ## i64
      recipe450 = ffbc_best_oriented_balanced_recipe(outer450, n, m, p, leaves)
      recipe677 = ffbc_best_oriented_balanced_recipe(outer677, n, m, p, leaves)
      if recipe450 == nil || recipe677 == nil || recipe450[3] != pinned
        << "authoritative replay mismatch at " + target
        exit(1)
      gain = pinned - recipe677[3] ## i64
      if gain > 0
        wins += 1
        if gain > largest_gain
          largest_gain = gain
      elsif gain == 0
        ties += 1
      else
        losses += 1
        if 0 - gain > largest_loss
          largest_loss = 0 - gain
      row = target + "\t" + pinned.to_s() + "\t" + recipe677[3].to_s() + "\t" + gain.to_s()
      row = row + "\t" + recipe677[0].join(",") + "\t" + recipe677[1].join(",") + "\t" + recipe677[2].join(",")
      row = row + "\t" + recipe677[4].to_s() + "x" + recipe677[5].to_s() + "x" + recipe677[6].to_s()
      << row + "\t" + recipe677[7].to_s()
      checked += 1
      line += 1
      p += 1
    m += 1
  n += 1

while line < baseline_lines.size() && baseline_lines[line].size() == 0
  line += 1
if checked != 1154 || line != baseline_lines.size()
  << "expected exactly 1154 baseline rows, got " + checked.to_s()
  exit(1)
<< "SUMMARY\tchecked=" + checked.to_s() + "\twins=" + wins.to_s() + "\tties=" + ties.to_s() + "\tlosses=" + losses.to_s() + "\tlargest_gain=" + largest_gain.to_s() + "\tlargest_loss=" + largest_loss.to_s()
