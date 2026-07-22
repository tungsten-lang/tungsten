# Exact leaf-local GL(2,2) orbit bank for the rank-7 Strassen ⟨2,2,2⟩ scheme.
#
# Block composition benefits from multiple exact rank-7 presentations even
# though the bilinear rank is optimal: support, density, and equal-factor
# connectivity change under leaf-local automorphisms and alter composed
# certificates.  This tool enumerates the closure of elementary leaf
# transvections (I/J/K), exact-gates every member, writes distinct dumps, and
# is the single source of relative paths for leaf-pool / FlipFleet registration.
#
# Build:
#   bin/tungsten-compiler compile benchmarks/matmul/metaflip/flipfleet_2x2_gl_leaf_bank.w \
#     --out /tmp/ff22-gl-bank --release
# Enumerate to /tmp (default), write the curated subset into the repo, or dump
# the full orbit into the repo (heavy; usually not what you want):
#   /tmp/ff22-gl-bank
#   /tmp/ff22-gl-bank curate
#   /tmp/ff22-gl-bank publish

use flipfleet_block_composer
use flipfleet_leaf_conjugation

-> ff22_expect(label, condition) (String bool) i64
  if condition
    return 1
  << "FF22_GL_BANK_FAIL " + label
  exit(1)
  0

# True when `candidate` matches some already retained bank member.
-> ff22_already(bank, candidate) i64
  i = 0 ## i64
  while i < bank.size()
    if fflc_equal(bank[i], candidate) == 1
      return 1
    i += 1
  0

# One elementary leaf-local generator: axis ∈ {0,1,2}, ordered pair (dst,src)
# of distinct coordinates in {0,1}.  Six generators total for 2x2x2.
-> ff22_apply_gen(leaf, gen) (FFBCScheme i64)
  axis = gen / 2 ## i64
  ordered = gen % 2 ## i64
  dst = ordered ## i64
  src = 1 - ordered ## i64
  fflc_transvection(leaf, axis, dst, src)

# BFS closure under the six generators, starting from an exact seed.
# Returns the bank in discovery order (seed first).
-> ff22_enumerate(seed) (FFBCScheme)
  bank = []
  if seed == nil || ffbc_verify_exact(seed) != 1 || seed.rank() != 7
    return bank
  bank.push(seed)
  frontier = 0 ## i64
  while frontier < bank.size()
    base = bank[frontier]
    gen = 0 ## i64
    while gen < 6
      image = ff22_apply_gen(base, gen)
      if image != nil && ffbc_verify_exact(image) == 1 && image.rank() == 7
        if ff22_already(bank, image) == 0
          bank.push(image)
      gen += 1
    frontier += 1
  bank

# Deterministic sparse ensemble members (same machinery as leaf conjugation
# tests).  These can leave the pure BFS orbit and still remain exact rank 7.
-> ff22_add_sparse(bank, seed, nonce, moves)
  image = fflc_sparse_leaf_image(seed, nonce, moves)
  if image != nil && ffbc_verify_exact(image) == 1 && image.rank() == 7
    if ff22_already(bank, image) == 0
      bank.push(image)
  1

-> ff22_pad2(i) (i64)
  if i < 10
    return "0" + i.to_s()
  i.to_s()

# Relative paths under benchmarks/matmul/metaflip/.  Index 0 is always the
# historical Strassen seed name so existing callers keep a stable default.
-> ff22_path_for(index, density) (i64 i64)
  if index == 0
    return "matmul_2x2_rank7_strassen_gf2.txt"
  "matmul_2x2_rank7_d" + density.to_s() + "_gl" + ff22_pad2(index) + "_gf2.txt"

# Write bank members under `output_root` (must end with /).  When `curated_only`
# is 1, only the registered subset is written and the historical Strassen seed
# file is left untouched (its checked-in decimal format is preserved).  Returns
# the number of files successfully written and re-parsed.
-> ff22_publish(bank, output_root, curated_only) i64
  written = 0 ## i64
  i = 0 ## i64
  while i < bank.size()
    density = fflc_density(bank[i]) ## i64
    pairs = fflc_equal_factor_pairs(bank[i]) ## i64
    rel = ff22_path_for(i, density)
    skip = 0 ## i64
    if curated_only != 0
      if ff22_is_registered(rel) == 0
        skip = 1
      if i == 0
        # Keep the historical seed presentation; it is already checked in.
        skip = 1
    if skip == 0
      path = output_root + rel
      rank = ffbc_write(path, bank[i]) ## i64
      ff22_expect("write " + rel, rank == 7)
      reloaded = ffbc_load_exact(path, 2, 2, 2, 16)
      ff22_expect("reload " + rel, reloaded != nil && reloaded.rank() == 7 && ffbc_verify_exact(reloaded) == 1)
      ff22_expect("round-trip equal " + rel, fflc_equal(reloaded, bank[i]) == 1)
      distance = fflc_term_set_distance(bank[0], bank[i]) ## i64
      << "FF22_GL_BANK member=" + i.to_s() + " density=" + density.to_s() + " pairs=" + pairs.to_s() + " distance_from_seed=" + distance.to_s() + " path=" + path
      written += 1
    i += 1
  written

# Curated checked-in bank: historical Strassen seed plus density-spaced GL
# orbit representatives (densities 36/40/42, BFS extremes).  Full orbit is 216
# members; only this subset is published into the repo for FlipFleet doors and
# composition leaf experiments.  Keep in lockstep with files on disk.
-> ff22_registered_paths()
  paths = []
  paths.push("matmul_2x2_rank7_strassen_gf2.txt")
  paths.push("matmul_2x2_rank7_d36_gl120_gf2.txt")
  paths.push("matmul_2x2_rank7_d36_gl190_gf2.txt")
  paths.push("matmul_2x2_rank7_d40_gl01_gf2.txt")
  paths.push("matmul_2x2_rank7_d40_gl108_gf2.txt")
  paths.push("matmul_2x2_rank7_d40_gl214_gf2.txt")
  paths.push("matmul_2x2_rank7_d42_gl08_gf2.txt")
  paths.push("matmul_2x2_rank7_d42_gl110_gf2.txt")
  paths.push("matmul_2x2_rank7_d42_gl207_gf2.txt")
  paths

# True when `rel` is in the curated registration list.
-> ff22_is_registered(rel) (String) i64
  paths = ff22_registered_paths()
  i = 0 ## i64
  while i < paths.size()
    if paths[i] == rel
      return 1
    i += 1
  0

-> ff22_register_into(root, leaves)
  paths = ff22_registered_paths()
  i = 0 ## i64
  while i < paths.size()
    leaf = ffbc_load_exact(root + paths[i], 2, 2, 2, 16)
    if leaf == nil
      << "invalid or missing 2x2 GL leaf: " + root + paths[i]
      exit(1)
    leaves.push(leaf)
    i += 1
  paths.size()

# ---- entry ----
av = argv()
# mode: 0 = dump full orbit to /tmp, 1 = publish full orbit into repo (heavy),
# 2 = curate (write only registered non-seed members into the repo root).
mode = 0 ## i64
if av.size() > 1
  << "usage: ff22-gl-bank [publish|curate]"
  exit(1)
if av.size() == 1
  if av[0] == "publish"
    mode = 1
  else
    if av[0] == "curate"
      mode = 2
    else
      << "usage: ff22-gl-bank [publish|curate]"
      exit(1)

root = "benchmarks/matmul/metaflip/"
seed = ffbc_load_exact(root + "matmul_2x2_rank7_strassen_gf2.txt", 2, 2, 2, 16)
ff22_expect("load Strassen seed", seed != nil && seed.rank() == 7 && ffbc_verify_exact(seed) == 1)

bank = ff22_enumerate(seed)
ff22_expect("nonempty orbit", bank.size() >= 1)
# Sparse ensemble for extra composition diversity beyond pure BFS.
ff22_add_sparse(bank, seed, 22001, 4)
ff22_add_sparse(bank, seed, 22002, 6)
ff22_add_sparse(bank, seed, 22003, 8)
ff22_add_sparse(bank, seed, 33107, 5)
default_image = fflc_default_leaf_image(seed)
if default_image != nil && ffbc_verify_exact(default_image) == 1 && default_image.rank() == 7
  if ff22_already(bank, default_image) == 0
    bank.push(default_image)

output_root = "/tmp/ff22_gl_bank/"
curated_only = 0 ## i64
if mode == 1
  output_root = root
if mode == 2
  output_root = root
  curated_only = 1
z = system("mkdir -p " + "'" + output_root + "'")
written = ff22_publish(bank, output_root, curated_only) ## i64
if curated_only == 0
  ff22_expect("published all members", written == bank.size())
else
  # Seed is registered but not rewritten; expect |registered| - 1 files.
  ff22_expect("published curated non-seed members", written == ff22_registered_paths().size() - 1)

# Density / distance summary against the seed.
# Note: Tungsten string concat after a "[" literal can drop subsequent pieces,
# so build the range with ".." instead of bracketed notation.
i = 0 ## i64
min_d = 999999 ## i64
max_d = 0 ## i64
while i < bank.size()
  density = fflc_density(bank[i]) ## i64
  distance = fflc_term_set_distance(bank[0], bank[i]) ## i64
  if distance < min_d
    min_d = distance
  if distance > max_d
    max_d = distance
  i += 1

range_s = min_d.to_s() + ".." + max_d.to_s()
seed_density_s = fflc_density(bank[0]).to_s()
<< "FF22_GL_BANK done members=" + bank.size().to_s() + " written=" + written.to_s() + " output_root=" + output_root + " termset_distance_range=" + range_s + " seed_density=" + seed_density_s
if mode == 0
  << "FF22_GL_BANK note: re-run with 'curate' to write the registered subset into " + root
  << "FF22_GL_BANK note: 'publish' writes the full orbit (216 files) into " + root
