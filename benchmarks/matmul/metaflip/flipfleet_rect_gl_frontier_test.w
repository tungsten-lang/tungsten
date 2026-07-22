use flipfleet_rect_global_isotropy

-> ffrgft_expect(label, condition) i64
  if condition == false || condition == 0
    << "FAIL " + label
    exit(1)
  1

# The 4x4x5 factors fit one FFBC word apiece.  Replace one known term in
# place; complete reconstruction after each pair is the authoritative gate.
-> ffrgft_replace(scheme, old_u, old_v, old_w, new_u, new_v, new_w) (FFBCScheme i64 i64 i64 i64 i64 i64) i64
  i = 0 ## i64
  while i < scheme.rank()
    if scheme.us()[i] == old_u && scheme.vs()[i] == old_v && scheme.ws()[i] == old_w
      scheme.us()[i] = new_u
      scheme.vs()[i] = new_v
      scheme.ws()[i] = new_w
      return 1
    i += 1
  0

-> ffrgft_move(scheme, old_u0, old_v0, old_w0, old_u1, old_v1, old_w1, new_u0, new_v0, new_w0, new_u1, new_v1, new_w1, expected_density) (FFBCScheme i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64) i64
  if ffrgft_replace(scheme, old_u0, old_v0, old_w0, new_u0, new_v0, new_w0) != 1
    return 0
  if ffrgft_replace(scheme, old_u1, old_v1, old_w1, new_u1, new_v1, new_w1) != 1
    return 0
  if scheme.rank() != 60 || fflc_density(scheme) != expected_density
    return 0
  ffbc_verify_exact(scheme)

root = "benchmarks/matmul/metaflip/"
source = ffbc_load_exact(root + "matmul_4x4x5_rank60_d655_global_isotropy_gf2.txt", 4, 4, 5, 64)
target = ffbc_load_exact(root + "matmul_4x4x5_rank60_d628_gl_frontier_gf2.txt", 4, 4, 5, 64)
z = ffrgft_expect("exact d655 source", source != nil && source.rank() == 60 && fflc_density(source) == 655 && ffbc_verify_exact(source) == 1)
z = ffrgft_expect("exact d628 target", target != nil && target.rank() == 60 && fflc_density(target) == 628 && ffbc_verify_exact(target) == 1)

z = ffrgft_expect("escape move 1", ffrgft_move(source, 16,132,291720, 16,12953,279332, 16,132,12460, 16,12829,279332, 653) == 1)
z = ffrgft_expect("escape move 2", ffrgft_move(source, 128,131200,160, 128,968096,36, 128,131200,132, 128,836896,36, 651) == 1)
z = ffrgft_expect("escape move 3", ffrgft_move(source, 176,4224,12684, 672,4224,12288, 176,4224,396, 528,4224,12288, 648) == 1)
z = ffrgft_expect("escape move 4", ffrgft_move(source, 2048,363529,5120, 2048,494605,4100, 2048,131076,4100, 2048,363529,1028, 641) == 1)
z = ffrgft_expect("escape move 5", ffrgft_move(source, 240,4096,20672, 4080,4096,20480, 240,4096,192, 3840,4096,20480, 635) == 1)
z = ffrgft_expect("escape move 6", ffrgft_move(source, 32768,622705,163840, 32768,753781,131076, 32768,131076,131076, 32768,622705,32772, 628) == 1)
z = ffrgft_expect("replay reaches checked-in endpoint", fflc_term_set_distance(source, target) == 0)

<< "PASS flipfleet rectangular GL frontier replay"
