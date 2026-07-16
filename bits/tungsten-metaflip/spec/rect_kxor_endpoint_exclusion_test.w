use ../lib/metaflip/kernels/rect_kxor

-> ffrxeet_fail(label) (String) i64
  << "FAIL rectangular kxor endpoint exclusion: " + label
  exit(1)
  0

# Six selected terms share V/W. Their U XOR equals the five-term excluded
# endpoint below. This exercises the logical set gate before any full tensor
# reconstruction, so the test remains CPU-only.
us = i64[6]
vs = i64[6]
ws = i64[6]
selected = i64[6]
i = 0 ## i64
while i < 6
  us[i] = 1 << i
  vs[i] = 3
  ws[i] = 5
  selected[i] = i
  i += 1

cu = i64[5]
cv = i64[5]
cw = i64[5]
indices = i64[5]
cu[0] = 3
cu[1] = 4
cu[2] = 8
cu[3] = 16
cu[4] = 32
i = 0
while i < 5
  cv[i] = 3
  cw[i] = 5
  indices[i] = i
  i += 1

# Reverse the exclusion order to prove comparison is permutation-invariant.
exclude_u = i64[5]
exclude_v = i64[5]
exclude_w = i64[5]
i = 0
while i < 5
  exclude_u[i] = cu[4-i]
  exclude_v[i] = cv[4-i]
  exclude_w[i] = cw[4-i]
  i += 1
status = i64[1]
rank = ffrx_accept_and_dump(us, vs, ws, 6, selected, 6, cu, cv, cw, indices, 5, 2, 2, 2, "/tmp/metaflip_rect_kxor_exclusion_cpu.txt", exclude_u, exclude_v, exclude_w, 5, status) ## i64
if rank != 0 || status[0] != 1
  z = ffrxeet_fail("known parent was not excluded")

exclude_u[0] = 99
status[0] = 0
rank = ffrx_accept_and_dump(us, vs, ws, 6, selected, 6, cu, cv, cw, indices, 5, 2, 2, 2, "/tmp/metaflip_rect_kxor_exclusion_cpu.txt", exclude_u, exclude_v, exclude_w, 5, status)
if rank != 0 || status[0] != 1
  z = ffrxeet_fail("distance-two endpoint was not excluded")

exclude_u[1] = 98
status[0] = 0
rank = ffrx_accept_and_dump(us, vs, ws, 6, selected, 6, cu, cv, cw, indices, 5, 2, 2, 2, "/tmp/metaflip_rect_kxor_exclusion_cpu.txt", exclude_u, exclude_v, exclude_w, 5, status)
if rank != 0 || status[0] != 1
  z = ffrxeet_fail("distance-four endpoint was not excluded")

exclude_u[2] = 97
status[0] = 0
rank = ffrx_accept_and_dump(us, vs, ws, 6, selected, 6, cu, cv, cw, indices, 5, 2, 2, 2, "/tmp/metaflip_rect_kxor_exclusion_cpu.txt", exclude_u, exclude_v, exclude_w, 5, status)
if rank != 0 || status[0] != 0
  z = ffrxeet_fail("distance-six endpoint was falsely excluded")

<< "PASS rectangular kxor endpoint parent-neighborhood exclusion"
