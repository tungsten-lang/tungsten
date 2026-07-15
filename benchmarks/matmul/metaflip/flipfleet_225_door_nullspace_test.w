use flipfleet_rect_archive_nullspace

-> ff225dnt_expect(label, condition)
  if !condition
    << "FAIL " + label
    exit(1)
  1

root = "benchmarks/matmul/metaflip/"
paths = []
labels = []
paths.push(root + "matmul_2x2x5_rank18_d84_gf2.txt")
paths.push(root + "matmul_2x2x5_rank18_d88_gf2.txt")
paths.push(root + "matmul_2x2x5_rank18_d92_block_local_gl_gf2.txt")
paths.push(root + "matmul_2x2x5_rank18_d84_block_splice_gf2.txt")
paths.push(root + "matmul_2x2x5_rank18_d84_gpu_block_tunnel_gf2.txt")
labels.push("d84")
labels.push("d88")
labels.push("block")
labels.push("splice")
labels.push("gpu-tunnel")

doors = []
i = 0 ## i64
while i < paths.size()
  door = ffbc_load_exact(paths[i], 2, 2, 5, 32)
  z = ff225dnt_expect(labels[i] + " exact", door != nil && door.rank() == 18 && ffbc_verify_exact(door) == 1) ## i64
  doors.push(door)
  i += 1

pairs = 0 ## i64
proper = 0 ## i64
rank17 = 0 ## i64
nullity_one = 0 ## i64
nullity_two = 0 ## i64
difference_sum = 0 ## i64
i = 0
while i < doors.size()
  j = i + 1 ## i64
  while j < doors.size()
    meta = i64[9]
    child = ffran_crossover(doors[i], doors[j], 1048576, meta)
    pairs += 1
    difference_sum += meta[0]
    if meta[1] == 1
      nullity_one += 1
    if meta[1] == 2
      nullity_two += 1
    if child != nil
      proper += 1
      z = ff225dnt_expect("child exact", meta[8] == 1 && child.rank() == meta[4] && ffbc_verify_exact(child) == 1)
      << "FF225_DOOR_CHILD left=" + labels[i] + " right=" + labels[j] + " density=" + fflc_density(child).to_s() + " distances=" + fflc_term_set_distance(child,doors[0]).to_s() + "/" + fflc_term_set_distance(child,doors[1]).to_s() + "/" + fflc_term_set_distance(child,doors[2]).to_s() + "/" + fflc_term_set_distance(child,doors[3]).to_s() + "/" + fflc_term_set_distance(child,doors[4]).to_s()
      if child.rank() == 17
        rank17 += 1
    << "FF225_DOOR_PAIR left=" + labels[i] + " right=" + labels[j] + " difference=" + meta[0].to_s() + " nullity=" + meta[1].to_s() + " column_rank=" + meta[2].to_s() + " evaluated=" + meta[3].to_s() + " child_rank=" + meta[4].to_s() + " exact=" + meta[8].to_s()
    j += 1
  i += 1

z = ff225dnt_expect("all pairs", pairs == 10)
z = ff225dnt_expect("complete pair geometry", difference_sum == 268 && nullity_one == 8 && nullity_two == 2 && proper == 2)
z = ff225dnt_expect("no false rank drop", rank17 == 0)
<< "PASS flipfleet 225 five-door nullspace pairs=" + pairs.to_s() + " proper=" + proper.to_s() + " rank17=" + rank17.to_s()
