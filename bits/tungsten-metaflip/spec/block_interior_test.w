use ../lib/metaflip/strategies/block_interior
use ../lib/metaflip/strategies/span_refactor

-> ffbirt_expect(label, condition)
  if !condition
    << "FAIL " + label
    exit(1)
  1

-> ffbirt_selected_sequence_equal(left_u, left_v, left_w, left_selected, right_u, right_v, right_w, right_selected, count) (i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64) i64
  i = 0 ## i64
  while i < count
    li = left_selected[i] ## i64
    ri = right_selected[i] ## i64
    if left_u[li] != right_u[ri] || left_v[li] != right_v[ri] || left_w[li] != right_w[ri]
      return 0
    i += 1
  1

# Explicit uneven rectangular cuts exercise all four occupancy quadrants.
four = (1 << 0) | (1 << 4) | (1 << 15) | (1 << 19) ## i64
z = ffbirt_expect("4x5 explicit cut quadrants", ffbir_quadrants(four,4,5,2,3) == 15)
z = ffbirt_expect("bottom-right quadrant", ffbir_quadrants(1 << 13,4,5,2,3) == 8)
z = ffbirt_expect("top-right quadrant", ffbir_quadrants(1 << 4,4,5,2,3) == 2)
z = ffbirt_expect("invalid row cut rejected", ffbir_quadrants(four,4,5,0,3) == 0)
z = ffbirt_expect("odd default cut keeps upper block first", ffbir_default_cut(7) == 4)
z = ffbirt_expect("even default cut", ffbir_default_cut(6) == 3)

# A deliberately asymmetric rectangular term set.  Reversing its physical
# order must preserve the selected algebraic sequence, not merely its score.
n = 4 ## i64
m = 5 ## i64
p = 3 ## i64
cut_n = 2 ## i64
cut_m = 3 ## i64
cut_p = 1 ## i64
rank = 7 ## i64
us = i64[rank]
vs = i64[rank]
ws = i64[rank]
us[0] = four
vs[0] = (1 << 0) | (1 << 2) | (1 << 12) | (1 << 14)
ws[0] = (1 << 0) | (1 << 2) | (1 << 9) | (1 << 11)
us[1] = us[0]
vs[1] = (1 << 0) | (1 << 14)
ws[1] = (1 << 2) | (1 << 9)
us[2] = (1 << 0) | (1 << 19)
vs[2] = vs[0]
ws[2] = (1 << 0) | (1 << 11)
us[3] = (1 << 4) | (1 << 15)
vs[3] = (1 << 2) | (1 << 12)
ws[3] = ws[0]
us[4] = 1 << 1
vs[4] = 1 << 4
ws[4] = 1 << 5
us[5] = 1 << 18
vs[5] = 1 << 13
ws[5] = 1 << 10
us[6] = (1 << 6) | (1 << 12)
vs[6] = (1 << 6) | (1 << 9)
ws[6] = (1 << 4) | (1 << 7)

reverse_u = i64[rank]
reverse_v = i64[rank]
reverse_w = i64[rank]
i = 0 ## i64
while i < rank
  reverse_u[i] = us[rank - 1 - i]
  reverse_v[i] = vs[rank - 1 - i]
  reverse_w[i] = ws[rank - 1 - i]
  i += 1

selected = i64[4]
reverse_selected = i64[4]
chosen = ffbir_choose_window(us,vs,ws,rank,n,m,p,cut_n,cut_m,cut_p,4,73,selected) ## i64
reverse_chosen = ffbir_choose_window(reverse_u,reverse_v,reverse_w,rank,n,m,p,cut_n,cut_m,cut_p,4,73,reverse_selected) ## i64
z = ffbirt_expect("rectangular block window selected", chosen == 4 && reverse_chosen == 4)
z = ffbirt_expect("term-order-independent selected sequence", ffbirt_selected_sequence_equal(us,vs,ws,selected,reverse_u,reverse_v,reverse_w,reverse_selected,4) == 1)
anchor_seam = ffbir_term_seam_score(us[selected[0]],vs[selected[0]],ws[selected[0]],n,m,p,cut_n,cut_m,cut_p) ## i64
maximum_seam = 0 ## i64
i = 0
while i < rank
  seam = ffbir_term_seam_score(us[i],vs[i],ws[i],n,m,p,cut_n,cut_m,cut_p) ## i64
  if seam > maximum_seam
    maximum_seam = seam
  i += 1
z = ffbirt_expect("anchor maximizes seam crossing", anchor_seam == maximum_seam)

# Exact planted 3->2 debt: the first two terms are a one-factor split of one
# rank-one tensor, while the third is independent.  Selection is followed by
# the production complete span refactor and its local exact gate.
plant_u = i64[3]
plant_v = i64[3]
plant_w = i64[3]
plant_u[0] = 1
plant_v[0] = (1 << 0) | (1 << 8)
plant_w[0] = (1 << 2) | (1 << 6)
plant_u[1] = 1 << 8
plant_v[1] = plant_v[0]
plant_w[1] = plant_w[0]
plant_u[2] = 1 << 1
plant_v[2] = 1 << 4
plant_w[2] = 1 << 7
plant_selected = i64[4]
plant_chosen = ffbir_choose_window(plant_u,plant_v,plant_w,3,3,3,3,2,2,2,3,19,plant_selected) ## i64
z = ffbirt_expect("planted window selected", plant_chosen == 3)
source_u = i64[4]
source_v = i64[4]
source_w = i64[4]
i = 0
while i < 3
  source_u[i] = plant_u[plant_selected[i]]
  source_v[i] = plant_v[plant_selected[i]]
  source_w[i] = plant_w[plant_selected[i]]
  i += 1
out_u = i64[4]
out_v = i64[4]
out_w = i64[4]
meta = i64[12]
replacement = ffsr_find_terms(source_u,source_v,source_w,3,2,out_u,out_v,out_w,meta) ## i64
z = ffbirt_expect("planted 3-to-2 found", replacement == 2)
z = ffbirt_expect("planted replacement exact", ffsr_verify_local_replacement(source_u,source_v,source_w,3,out_u,out_v,out_w,replacement) == 1)

<< "PASS block interior cuts, permutation robustness, and exact planted refactor"
