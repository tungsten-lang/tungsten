# SIMD Vector WValue Tag 0xFFF2 & 0xFFF3 spec.

v2 = ccall("w_vec2f_w", ~3.0, ~4.0)
p2 = ccall("w_point2d_w", ~10.0, ~20.0)
v3 = ccall("w_vec3f_w", ~1.0, ~2.0, ~3.0)

is_v2_2d = ccall("w_is_simd2d_w", v2)
is_p2_2d = ccall("w_is_simd2d_w", p2)
is_v3_3d = ccall("w_is_simd3d_w", v3)
sub_v2 = ccall("w_simd2d_subtag_w", v2)
sub_p2 = ccall("w_simd2d_subtag_w", p2)

-> expect(name, cond)
  if cond
    << "PASS " + name
  else
    << "FAIL " + name
    exit 1

expect("simd2d.is_simd2d", is_v2_2d && is_p2_2d)
expect("simd3d.is_simd3d", is_v3_3d)
expect("simd2d.vec2f_subtag", sub_v2 == 0)
expect("simd2d.point2d_subtag", sub_p2 == 2)
