use ../lib/metaflip/kernels/rect_kxor

-> ffrxspt_fail(label) (String) i64
  << "FAIL rectangular kxor shoulder parent: " + label
  exit(1)
  0

root = __DIR__ + "/../lib/metaflip/seeds/gf2"
shoulder227 = root + "/matmul_2x2x7_rank26_isotropy_split_plus1_gf2.txt"
parent227 = "/tmp/metaflip_rect_kxor_227_isotropy_parent_r25.txt"
rank227 = ffrx_materialize_merged_parent(shoulder227, parent227, 2, 2, 7, 8, 10) ## i64
if rank227 != 25
  z = ffrxspt_fail("2x2x7 merged parent rank=" + rank227.to_s())

shoulder228 = root + "/matmul_2x2x8_rank29_isotropy_split_plus1_gf2.txt"
parent228 = "/tmp/metaflip_rect_kxor_228_isotropy_parent_r28.txt"
rank228 = ffrx_materialize_merged_parent(shoulder228, parent228, 2, 2, 8, 0, 17) ## i64
if rank228 != 28
  z = ffrxspt_fail("2x2x8 merged parent rank=" + rank228.to_s())

parent229 = root + "/matmul_2x2x9_rank32_d156_perminov_2025_gf2.txt"
shoulder229 = "/tmp/metaflip_rect_kxor_229_split_plus1_r33.txt"
# Parent term four has V=32832=64 XOR 32768.
rank229 = ffrx_materialize_split_shoulder(parent229, shoulder229, 2, 2, 9, 4, 1, 64) ## i64
if rank229 != 33
  z = ffrxspt_fail("2x2x9 split shoulder rank=" + rank229.to_s())

<< "PASS rectangular kxor artificial shoulders parents=" + rank227.to_s() + "/" + rank228.to_s() + " shoulder229=" + rank229.to_s()
