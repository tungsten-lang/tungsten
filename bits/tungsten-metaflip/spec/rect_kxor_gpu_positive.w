# Constructed end-to-end controls for rectangular GPU XOR surgery.
#
# Starting from a verified 2x5x6 scheme, split one rank-one term along a factor
# axis.  The resulting rank+1 shoulder is still exact.  The selected subset
# contains the two children and untouched terms, so the GPU must rediscover the
# parent and recover the original rank through the complete rectangular gate.

use ../lib/metaflip/kernels/rect_kxor
use core/system

-> ffrxpt_fail(label) (String) i64
  << "FAIL rectangular kxor GPU positive: " + label
  exit(1)
  0

n = 2 ## i64
m = 5 ## i64
p = 6 ## i64
root = __DIR__ + "/../lib/metaflip"
base_path = root + "/seeds/gf2/matmul_2x5x6_rank47_catalog_gf2.txt"
shoulder_path = "/tmp/metaflip_rect_kxor_positive_shoulder.txt"
output6 = "/tmp/metaflip_rect_kxor_positive_6to5.txt"
output7 = "/tmp/metaflip_rect_kxor_positive_7to6.txt"
shoulder75_path = "/tmp/metaflip_rect_kxor_positive_double_shoulder.txt"
output75 = "/tmp/metaflip_rect_kxor_positive_7to5.txt"
output64 = "/tmp/metaflip_rect_kxor_positive_6to4.txt"
output53 = "/tmp/metaflip_rect_kxor_positive_5to3.txt"
output_excluded = "/tmp/metaflip_rect_kxor_positive_excluded.txt"
metal_path = System.executable_path() + ".metal"

cap = ffr_default_capacity(n, m, p) ## i64
state = i64[ffr_state_size(cap)]
base_rank = ffr_load_scheme_cap(state, base_path, n, m, p, cap, 91801, 0, 1, 1, 1) ## i64
if base_rank < 7 || ffr_verify_best_exact(state, n, m, p) != 1
  z = ffrxpt_fail("base certificate")
us = i64[cap]
vs = i64[cap]
ws = i64[cap]
exported = ffw_export_best(state, us, vs, ws) ## i64
if exported != base_rank
  z = ffrxpt_fail("base export")

split_index = 0 - 1 ## i64
split_axis = 0 - 1 ## i64
i = 0 ## i64
while i < base_rank && split_index < 0
  if ffw_popcount(us[i]) > 1
    split_index = i
    split_axis = 0
  if split_index < 0 && ffw_popcount(vs[i]) > 1
    split_index = i
    split_axis = 1
  if split_index < 0 && ffw_popcount(ws[i]) > 1
    split_index = i
    split_axis = 2
  i += 1
if split_index < 0
  z = ffrxpt_fail("no splittable base term")

factor = us[split_index] ## i64
if split_axis == 1
  factor = vs[split_index]
if split_axis == 2
  factor = ws[split_index]
first = factor & (0 - factor) ## i64
second = factor ^ first ## i64
if first == 0 || second == 0
  z = ffrxpt_fail("invalid factor split")

shoulder_u = i64[cap]
shoulder_v = i64[cap]
shoulder_w = i64[cap]
shoulder_rank = 0 ## i64
i = 0
while i < base_rank
  if i != split_index
    shoulder_u[shoulder_rank] = us[i]
    shoulder_v[shoulder_rank] = vs[i]
    shoulder_w[shoulder_rank] = ws[i]
    shoulder_rank += 1
  i += 1
child_a = shoulder_rank ## i64
shoulder_u[shoulder_rank] = us[split_index]
shoulder_v[shoulder_rank] = vs[split_index]
shoulder_w[shoulder_rank] = ws[split_index]
if split_axis == 0
  shoulder_u[shoulder_rank] = first
if split_axis == 1
  shoulder_v[shoulder_rank] = first
if split_axis == 2
  shoulder_w[shoulder_rank] = first
shoulder_rank += 1
child_b = shoulder_rank ## i64
shoulder_u[shoulder_rank] = us[split_index]
shoulder_v[shoulder_rank] = vs[split_index]
shoulder_w[shoulder_rank] = ws[split_index]
if split_axis == 0
  shoulder_u[shoulder_rank] = second
if split_axis == 1
  shoulder_v[shoulder_rank] = second
if split_axis == 2
  shoulder_w[shoulder_rank] = second
shoulder_rank += 1
if shoulder_rank != base_rank + 1
  z = ffrxpt_fail("shoulder rank")

body = shoulder_rank.to_s() + "\n"
i = 0
while i < shoulder_rank
  body = body + shoulder_u[i].to_s() + " " + shoulder_v[i].to_s() + " " + shoulder_w[i].to_s() + "\n"
  i += 1
written = write_file(shoulder_path, body)
if written == false
  z = ffrxpt_fail("write shoulder")
shoulder_state = ffrx_load_exact(shoulder_path, n, m, p, 7)
if shoulder_state == nil || ffr_best_rank(shoulder_state) != shoulder_rank
  z = ffrxpt_fail("split shoulder exact gate")

selected6 = i64[6]
selected6[0] = child_a
selected6[1] = child_b
i = 0
while i < 4
  selected6[i + 2] = i
  i += 1
rank6 = ffrx_search_exact_subset(shoulder_path, output6, n, m, p, 6, 64, 2, selected6, metal_path) ## i64
if rank6 != base_rank
  z = ffrxpt_fail("6 -> 5 join/full gate rank=" + rank6.to_s())
verify6 = ffrx_load_exact(output6, n, m, p, 6)
if verify6 == nil || ffr_best_rank(verify6) != base_rank
  z = ffrxpt_fail("6 -> 5 output certificate")

selected7 = i64[7]
selected7[0] = child_a
selected7[1] = child_b
i = 0
while i < 5
  selected7[i + 2] = i
  i += 1
rank7 = ffrx_search_exact_subset(shoulder_path, output7, n, m, p, 7, 64, 2, selected7, metal_path) ## i64
if rank7 != base_rank
  z = ffrxpt_fail("7 -> 6 join/full gate rank=" + rank7.to_s())
verify7 = ffrx_load_exact(output7, n, m, p, 7)
if verify7 == nil || ffr_best_rank(verify7) != base_rank
  z = ffrxpt_fail("7 -> 6 output certificate")

# A planted 7 -> 5 control needs a rank+2 shoulder: split two unrelated base
# terms, then select their four children and three spectators. The pair/triple
# join must recover both parents and pass the complete rank-47 tensor gate.
split_a = split_index ## i64
axis_a = split_axis ## i64
split_b = 0 - 1 ## i64
axis_b = 0 - 1 ## i64
i = 0
while i < base_rank && split_b < 0
  if i != split_a
    if ffw_popcount(us[i]) > 1
      split_b = i
      axis_b = 0
    if split_b < 0 && ffw_popcount(vs[i]) > 1
      split_b = i
      axis_b = 1
    if split_b < 0 && ffw_popcount(ws[i]) > 1
      split_b = i
      axis_b = 2
  i += 1
if split_b < 0
  z = ffrxpt_fail("second splittable base term")

factor_a = us[split_a] ## i64
if axis_a == 1
  factor_a = vs[split_a]
if axis_a == 2
  factor_a = ws[split_a]
first_a = factor_a & (0 - factor_a) ## i64
second_a = factor_a ^ first_a ## i64
factor_b = us[split_b] ## i64
if axis_b == 1
  factor_b = vs[split_b]
if axis_b == 2
  factor_b = ws[split_b]
first_b = factor_b & (0 - factor_b) ## i64
second_b = factor_b ^ first_b ## i64
if first_a == 0 || second_a == 0 || first_b == 0 || second_b == 0
  z = ffrxpt_fail("double split factors")

shoulder75_u = i64[cap]
shoulder75_v = i64[cap]
shoulder75_w = i64[cap]
shoulder75_rank = 0 ## i64
i = 0
while i < base_rank
  if i != split_a && i != split_b
    shoulder75_u[shoulder75_rank] = us[i]
    shoulder75_v[shoulder75_rank] = vs[i]
    shoulder75_w[shoulder75_rank] = ws[i]
    shoulder75_rank += 1
  i += 1
child_a0 = shoulder75_rank ## i64
shoulder75_u[shoulder75_rank] = us[split_a]
shoulder75_v[shoulder75_rank] = vs[split_a]
shoulder75_w[shoulder75_rank] = ws[split_a]
if axis_a == 0
  shoulder75_u[shoulder75_rank] = first_a
if axis_a == 1
  shoulder75_v[shoulder75_rank] = first_a
if axis_a == 2
  shoulder75_w[shoulder75_rank] = first_a
shoulder75_rank += 1
child_a1 = shoulder75_rank ## i64
shoulder75_u[shoulder75_rank] = us[split_a]
shoulder75_v[shoulder75_rank] = vs[split_a]
shoulder75_w[shoulder75_rank] = ws[split_a]
if axis_a == 0
  shoulder75_u[shoulder75_rank] = second_a
if axis_a == 1
  shoulder75_v[shoulder75_rank] = second_a
if axis_a == 2
  shoulder75_w[shoulder75_rank] = second_a
shoulder75_rank += 1
child_b0 = shoulder75_rank ## i64
shoulder75_u[shoulder75_rank] = us[split_b]
shoulder75_v[shoulder75_rank] = vs[split_b]
shoulder75_w[shoulder75_rank] = ws[split_b]
if axis_b == 0
  shoulder75_u[shoulder75_rank] = first_b
if axis_b == 1
  shoulder75_v[shoulder75_rank] = first_b
if axis_b == 2
  shoulder75_w[shoulder75_rank] = first_b
shoulder75_rank += 1
child_b1 = shoulder75_rank ## i64
shoulder75_u[shoulder75_rank] = us[split_b]
shoulder75_v[shoulder75_rank] = vs[split_b]
shoulder75_w[shoulder75_rank] = ws[split_b]
if axis_b == 0
  shoulder75_u[shoulder75_rank] = second_b
if axis_b == 1
  shoulder75_v[shoulder75_rank] = second_b
if axis_b == 2
  shoulder75_w[shoulder75_rank] = second_b
shoulder75_rank += 1
if shoulder75_rank != base_rank + 2
  z = ffrxpt_fail("double shoulder rank")

body75 = shoulder75_rank.to_s() + "\n"
i = 0
while i < shoulder75_rank
  body75 = body75 + shoulder75_u[i].to_s() + " " + shoulder75_v[i].to_s() + " " + shoulder75_w[i].to_s() + "\n"
  i += 1
if write_file(shoulder75_path, body75) == false
  z = ffrxpt_fail("write double shoulder")
double_state = ffrx_load_exact(shoulder75_path, n, m, p, 7)
if double_state == nil || ffr_best_rank(double_state) != shoulder75_rank
  z = ffrxpt_fail("double shoulder exact gate")

selected75 = i64[7]
selected75[0] = child_a0
selected75[1] = child_a1
selected75[2] = child_b0
selected75[3] = child_b1
selected75[4] = 0
selected75[5] = 1
selected75[6] = 2
rank75 = ffrx_search_exact_subset(shoulder75_path, output75, n, m, p, 7, 128, 4, selected75, metal_path, "", "", 5) ## i64
if rank75 != base_rank
  z = ffrxpt_fail("7 -> 5 join/full gate rank=" + rank75.to_s())
verify75 = ffrx_load_exact(output75, n, m, p, 7)
if verify75 == nil || ffr_best_rank(verify75) != base_rank
  z = ffrxpt_fail("7 -> 5 output certificate")
out75_u = i64[cap]
out75_v = i64[cap]
out75_w = i64[cap]
if ffw_export_best(verify75, out75_u, out75_v, out75_w) != base_rank
  z = ffrxpt_fail("7 -> 5 output export")
if ffrx_term_sets_equal(out75_u, out75_v, out75_w, base_rank, us, vs, ws, base_rank) != 1
  z = ffrxpt_fail("7 -> 5 did not recover planted base")

selected64 = i64[6]
selected64[0] = child_a0
selected64[1] = child_a1
selected64[2] = child_b0
selected64[3] = child_b1
selected64[4] = 0
selected64[5] = 1
rank64 = ffrx_search_exact_subset(shoulder75_path, output64, n, m, p, 6, 128, 4, selected64, metal_path, "", "", 4) ## i64
if rank64 != base_rank
  z = ffrxpt_fail("6 -> 4 join/full gate rank=" + rank64.to_s())
verify64 = ffrx_load_exact(output64, n, m, p, 6)
if verify64 == nil || ffr_best_rank(verify64) != base_rank
  z = ffrxpt_fail("6 -> 4 output certificate")
out64_u = i64[cap]
out64_v = i64[cap]
out64_w = i64[cap]
if ffw_export_best(verify64, out64_u, out64_v, out64_w) != base_rank
  z = ffrxpt_fail("6 -> 4 output export")
if ffrx_term_sets_equal(out64_u, out64_v, out64_w, base_rank, us, vs, ws, base_rank) != 1
  z = ffrxpt_fail("6 -> 4 did not recover planted base")

selected53 = i64[5]
selected53[0] = child_a0
selected53[1] = child_a1
selected53[2] = child_b0
selected53[3] = child_b1
selected53[4] = 0
rank53 = ffrx_search_exact_subset(shoulder75_path, output53, n, m, p, 5, 128, 4, selected53, metal_path, "", "", 3) ## i64
if rank53 != base_rank
  z = ffrxpt_fail("5 -> 3 join/full gate rank=" + rank53.to_s())
verify53 = ffrx_load_exact(output53, n, m, p, 5)
if verify53 == nil || ffr_best_rank(verify53) != base_rank
  z = ffrxpt_fail("5 -> 3 output certificate")
out53_u = i64[cap]
out53_v = i64[cap]
out53_w = i64[cap]
if ffw_export_best(verify53, out53_u, out53_v, out53_w) != base_rank
  z = ffrxpt_fail("5 -> 3 output export")
if ffrx_term_sets_equal(out53_u, out53_v, out53_w, base_rank, us, vs, ws, base_rank) != 1
  z = ffrxpt_fail("5 -> 3 did not recover planted base")

# Excluding the known parent must not stop at the first exact collision.  The
# split parent has multiple tuple partitions in this deliberately broad pool;
# seeing at least two excluded endpoints proves the ordinal/query loops keep
# walking after the first one instead of treating it as a terminal hit.
device = metal_device()
msl = read_file(metal_path)
if msl == nil || msl.size() == 0
  z = ffrxpt_fail("generated Metal source for exclusion")
library = metal_compile_source(device, msl)
queue = metal_queue(device)
cu = i64[64]
cv = i64[64]
cw = i64[64]
count = ffx_candidates(shoulder_u, shoulder_v, shoulder_w, shoulder_rank, selected6, 6, 64, 2, cu, cv, cw) ## i64
metrics = i64[13]
excluded_rank = ffrx_gpu_subset_excluding(device, library, queue, shoulder_u, shoulder_v, shoulder_w, shoulder_rank, selected6, 6, cu, cv, cw, count, n, m, p, output_excluded, us, vs, ws, base_rank, metrics) ## i64
if excluded_rank != 0
  z = ffrxpt_fail("known-parent exclusion returned rank=" + excluded_rank.to_s())
if metrics[12] < 2
  z = ffrxpt_fail("known-parent continuation count=" + metrics[12].to_s())
if metrics[10] != 0
  z = ffrxpt_fail("excluded parents reached full gate=" + metrics[10].to_s())
excluded_body = read_file(output_excluded)
if excluded_body != nil && excluded_body.size() != 0
  z = ffrxpt_fail("excluded parent was dumped")

<< "PASS rectangular kxor GPU controls base_rank=" + base_rank.to_s() + " shoulder_rank=" + shoulder_rank.to_s() + " double_shoulder_rank=" + shoulder75_rank.to_s() + " split_axis=" + split_axis.to_s() + " excluded_endpoints=" + metrics[12].to_s()
