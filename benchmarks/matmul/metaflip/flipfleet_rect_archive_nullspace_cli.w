# Complete rectangular parent-difference nullspace audit and exact splice.
#
# Usage:
#   flipfleet_rect_archive_nullspace_cli LEFT RIGHT N M P COMBINATIONS OUTPUT

use flipfleet_rect_archive_nullspace

arguments = argv()
if arguments.size() != 7
  << "usage: flipfleet_rect_archive_nullspace_cli LEFT RIGHT N M P COMBINATIONS OUTPUT"
  exit(2)
left_path = arguments[0]
right_path = arguments[1]
n = arguments[2].to_i() ## i64
m = arguments[3].to_i() ## i64
p = arguments[4].to_i() ## i64
combinations = arguments[5].to_i() ## i64
output_path = arguments[6]
if n < 1 || m < 1 || p < 1 || n*m > 30 || m*p > 30 || n*p > 30 || combinations < 1
  << "RECT_ARCHIVE_NULLSPACE_ERROR code=arguments"
  exit(2)

left = ffbc_load_exact(left_path, n, m, p, 512)
right = ffbc_load_exact(right_path, n, m, p, 512)
if left == nil || right == nil || ffbc_verify_exact(left) != 1 || ffbc_verify_exact(right) != 1
  << "RECT_ARCHIVE_NULLSPACE_ERROR code=seed"
  exit(1)
meta = i64[9]
child = ffran_crossover(left, right, combinations, meta)
base = "RECT_ARCHIVE_NULLSPACE_RESULT shape=" + n.to_s() + "x" + m.to_s() + "x" + p.to_s() + " left_rank=" + left.rank().to_s() + " right_rank=" + right.rank().to_s() + " left_density=" + fflc_density(left).to_s() + " right_density=" + fflc_density(right).to_s() + " left_pairs=" + fflc_equal_factor_pairs(left).to_s() + " right_pairs=" + fflc_equal_factor_pairs(right).to_s() + " distance=" + fflc_term_set_distance(left,right).to_s() + " difference=" + meta[0].to_s() + " column_rank=" + meta[2].to_s() + " nullity=" + meta[1].to_s()
if child == nil
  << base + " proper=0 child_rank=0"
  exit(0)
if ffbc_write(output_path, child) != child.rank()
  << "RECT_ARCHIVE_NULLSPACE_ERROR code=write"
  exit(1)
reparsed = ffbc_load_exact(output_path, n, m, p, 512)
if reparsed == nil || reparsed.rank() != child.rank() || ffbc_verify_exact(reparsed) != 1 || fflc_term_set_distance(reparsed, child) != 0
  << "RECT_ARCHIVE_NULLSPACE_ERROR code=reparse"
  exit(1)
<< base + " proper=1 combinations=" + meta[3].to_s() + " child_rank=" + child.rank().to_s() + " child_density=" + fflc_density(child).to_s() + " selected=" + meta[5].to_s() + " mix=" + meta[6].to_s() + "/" + meta[7].to_s() + " child_distance_left=" + fflc_term_set_distance(child,left).to_s() + " child_distance_right=" + fflc_term_set_distance(child,right).to_s() + " exact=1 reparsed=1 output=" + output_path
