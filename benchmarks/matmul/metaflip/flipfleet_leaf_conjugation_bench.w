use flipfleet_leaf_conjugation

-> fflcb_expect(name, condition)
  if condition
    return 0
  << "FAIL " + name
  exit(1)

-> fflcb_record(reference, archive1, archive2, candidate, id, densities, pairs, novelties) (FFBCScheme FFBCScheme FFBCScheme FFBCScheme i64 i64[] i64[] i64[]) i64
  if candidate == nil || candidate.rank() != 248 || ffbc_verify_exact(candidate) != 1
    return 0
  descriptor = i64[3]
  if fflc_descriptor(reference, candidate, descriptor) != 1
    return 0
  densities[id] = descriptor[0]
  pairs[id] = descriptor[1]
  novelty = descriptor[2] ## i64
  candidate_novelty = fflc_term_set_distance(archive1, candidate) ## i64
  if candidate_novelty < novelty
    novelty = candidate_novelty
  candidate_novelty = fflc_term_set_distance(archive2, candidate)
  if candidate_novelty < novelty
    novelty = candidate_novelty
  novelties[id] = novelty
  1

root = "benchmarks/matmul/metaflip/"
samples = 48 ## i64
arguments = argv()
if arguments.size() > 0
  samples = arguments[0].to_i()
if samples < 1
  samples = 1
if samples > 256
  samples = 256

paths = ["matmul_3x3_rank23_d139_gf2.txt",
         "matmul_3x3x4_rank29_gf2.txt",
         "matmul_3x4x4_rank38_gf2.txt",
         "matmul_4x4_rank47_d450_gf2.txt"]
ns = i64[4]
ms = i64[4]
ps = i64[4]
ns[0] = 3
ms[0] = 3
ps[0] = 3
ns[1] = 3
ms[1] = 3
ps[1] = 4
ns[2] = 3
ms[2] = 4
ps[2] = 4
ns[3] = 4
ms[3] = 4
ps[3] = 4

leaves = []
slot = 0 ## i64
while slot < 4
  leaf = ffbc_load_exact(root + paths[slot], ns[slot], ms[slot], ps[slot], 128)
  fflcb_expect("load leaf", leaf != nil)
  leaves.push(leaf)
  slot += 1

outer = ffbc_load_exact(root + "matmul_2x2_rank7_strassen_gf2.txt", 2, 2, 2, 16)
leader = ffbc_load_exact(root + "matmul_7x7_rank248_d2952_sedoglavic_gf2.txt", 7, 7, 7, 320)
archive1 = ffbc_load_exact(root + "matmul_7x7_rank248_d2958_sedoglavic_gf2.txt", 7, 7, 7, 320)
archive2 = ffbc_load_exact(root + "matmul_7x7_rank248_d3015_connectivity_sedoglavic_gf2.txt", 7, 7, 7, 320)
fflcb_expect("load exact outer and archive", outer != nil && leader != nil && archive1 != nil && archive2 != nil)

alloc_n = i64[2]
alloc_m = i64[2]
alloc_p = i64[2]
alloc_n[0] = 4
alloc_n[1] = 3
alloc_m[0] = 4
alloc_m[1] = 3
alloc_p[0] = 4
alloc_p[1] = 3

count = samples + 5 ## i64
densities = i64[count]
pairs = i64[count]
novelties = i64[count]
masks = i64[count]
exact = 0 ## i64

# Candidates 0--2 are the existing rank-248 archive. Candidate 3 is the
# canonical composition; candidate 4 is the older fixed conjugation recipe.
exact += fflcb_record(leader, archive1, archive2, leader, 0, densities, pairs, novelties)
exact += fflcb_record(leader, archive1, archive2, archive1, 1, densities, pairs, novelties)
exact += fflcb_record(leader, archive1, archive2, archive2, 2, densities, pairs, novelties)
baseline = ffbc_compose(outer, alloc_n, alloc_m, alloc_p, leaves)
exact += fflcb_record(leader, archive1, archive2, baseline, 3, densities, pairs, novelties)

defaults = []
slot = 0
while slot < leaves.size()
  defaults.push(fflc_default_leaf_image(leaves[slot]))
  slot += 1
fixed = ffbc_compose(outer, alloc_n, alloc_m, alloc_p, defaults)
masks[4] = 15
exact += fflcb_record(leader, archive1, archive2, fixed, 4, densities, pairs, novelties)

sample = 0 ## i64
while sample < samples
  id = sample + 5 ## i64
  # Rotate through every nonempty subset of the four leaf shapes, then vary
  # sparse word length and generators on subsequent passes.
  mask = 1 + (sample % 15) ## i64
  masks[id] = mask
  images = []
  slot = 0
  while slot < leaves.size()
    image = leaves[slot]
    if ((mask >> slot) & 1) != 0
      moves = 1 + ((sample * 3 + slot * 5) % 8) ## i64
      seed = (sample + 1) * 104729 + (slot + 1) * 13007 ## i64
      image = fflc_sparse_leaf_image(leaves[slot], seed, moves)
      fflcb_expect("sparse leaf image", image != nil)
    images.push(image)
    slot += 1
  candidate = ffbc_compose(outer, alloc_n, alloc_m, alloc_p, images)
  exact += fflcb_record(leader, archive1, archive2, candidate, id, densities, pairs, novelties)
  sample += 1

fflcb_expect("every composed sample exact", exact == count)
keep = i64[count]
front = fflc_pareto_mark(densities, pairs, novelties, count, keep) ## i64
min_density = densities[0] ## i64
max_pairs = pairs[0] ## i64
max_novelty = novelties[0] ## i64
i = 1 ## i64
while i < count
  if densities[i] < min_density
    min_density = densities[i]
  if pairs[i] > max_pairs
    max_pairs = pairs[i]
  if novelties[i] > max_novelty
    max_novelty = novelties[i]
  i += 1

<< "LEAF_GL_SUMMARY candidates=" + count.to_s() + " exact=" + exact.to_s() + " pareto=" + front.to_s() + " min-density=" + min_density.to_s() + " max-pairs=" + max_pairs.to_s() + " max-novelty=" + max_novelty.to_s()
i = 0
while i < 5
  << "LEAF_GL_BASELINE id=" + i.to_s() + " density=" + densities[i].to_s() + " pairs=" + pairs[i].to_s() + " archive-novelty=" + novelties[i].to_s()
  i += 1
i = 0
while i < count
  if keep[i] == 1
    << "LEAF_GL_PARETO id=" + i.to_s() + " mask=" + masks[i].to_s() + " density=" + densities[i].to_s() + " pairs=" + pairs[i].to_s() + " novelty=" + novelties[i].to_s()
  i += 1
