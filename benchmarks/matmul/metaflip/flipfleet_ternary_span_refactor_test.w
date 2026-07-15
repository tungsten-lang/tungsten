use flipfleet_ternary_span_refactor

-> fftsrtest_expect(label, condition) (String bool) i64
  if !condition
    << "FAIL " + label
    exit(1)
  1

-> fftsrtest_exact(left_up,left_un,left_vp,left_vn,left_wp,left_wn,left_count,right_up,right_un,right_vp,right_vn,right_wp,right_wn,right_count,dim) (i64[] i64[] i64[] i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[] i64[] i64[] i64 i64) i64
  ai = 0 ## i64
  while ai < dim
    bi = 0 ## i64
    while bi < dim
      ci = 0 ## i64
      while ci < dim
        left = 0 ## i64
        t = 0 ## i64
        while t < left_count
          left += fft_coefficient(left_up[t],left_un[t],ai) * fft_coefficient(left_vp[t],left_vn[t],bi) * fft_coefficient(left_wp[t],left_wn[t],ci)
          t += 1
        right = 0 ## i64
        t = 0
        while t < right_count
          right += fft_coefficient(right_up[t],right_un[t],ai) * fft_coefficient(right_vp[t],right_vn[t],bi) * fft_coefficient(right_wp[t],right_wn[t],ci)
          t += 1
        if left != right
          return 0
        ci += 1
      bi += 1
    ai += 1
  1

-> fftsrtest_same_multiset(left_up,left_un,left_vp,left_vn,left_wp,left_wn,left_count,right_up,right_un,right_vp,right_vn,right_wp,right_wn,right_count) (i64[] i64[] i64[] i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[] i64[] i64[] i64) i64
  if left_count != right_count
    return 0
  used = 0 ## i64
  i = 0 ## i64
  while i < left_count
    match = 0 - 1 ## i64
    j = 0 ## i64
    while j < right_count && match < 0
      if ((used >> j) & 1) == 0
        if left_up[i] == right_up[j] && left_un[i] == right_un[j] && left_vp[i] == right_vp[j] && left_vn[i] == right_vn[j] && left_wp[i] == right_wp[j] && left_wn[i] == right_wn[j]
          match = j
      j += 1
    if match < 0
      return 0
    used = used | (1 << match)
    i += 1
  1

-> fftsrtest_zero(arr, count) (i64[] i64) i64
  i = 0 ## i64
  while i < count
    arr[i] = 0
    i += 1
  1

workspace = FFTSRWorkspace.new(5000)
sup = i64[4]
sun = i64[4]
svp = i64[4]
svn = i64[4]
swp = i64[4]
swn = i64[4]
out_up = i64[4]
out_un = i64[4]
out_vp = i64[4]
out_vn = i64[4]
out_wp = i64[4]
out_wn = i64[4]
meta = i64[20]

# 3->2: merge a strict U split while retaining an unrelated third term.
sup[0] = 1
svp[0] = 1
swp[0] = 1
sup[1] = 2
svp[1] = 1
swp[1] = 1
sup[2] = 4
svp[2] = 2
swp[2] = 2
found = fftsr_find_terms_ws(sup,sun,svp,svn,swp,swn,2,3,2,workspace,out_up,out_un,out_vp,out_vn,out_wp,out_wn,meta) ## i64
z = fftsrtest_expect("planted strict 3->2 found",found == 2 && meta[6] >= 1) ## i64
z = fftsrtest_expect("planted strict 3->2 exact",fftsrtest_exact(sup,sun,svp,svn,swp,swn,3,out_up,out_un,out_vp,out_vn,out_wp,out_wn,2,4) == 1)

# 3<->3: ordinary shared-U two-term refactor plus an idle third term.  The
# engine must skip the original multiset and return a genuinely changed one.
z = fftsrtest_zero(sup,4) ## i64
z = fftsrtest_zero(sun,4)
z = fftsrtest_zero(svp,4)
z = fftsrtest_zero(svn,4)
z = fftsrtest_zero(swp,4)
z = fftsrtest_zero(swn,4)
sup[0] = 1
svp[0] = 1
swp[0] = 1
sup[1] = 1
svp[1] = 2
swp[1] = 2
sup[2] = 4
svp[2] = 4
swp[2] = 4
found = fftsr_find_terms_ws(sup,sun,svp,svn,swp,swn,2,3,3,workspace,out_up,out_un,out_vp,out_vn,out_wp,out_wn,meta)
z = fftsrtest_expect("planted strict 3<->3 found",found == 3 && meta[6] >= 1)
z = fftsrtest_expect("planted strict 3<->3 exact",fftsrtest_exact(sup,sun,svp,svn,swp,swn,3,out_up,out_un,out_vp,out_vn,out_wp,out_wn,3,4) == 1)
z = fftsrtest_expect("planted strict 3<->3 changes multiset",fftsrtest_same_multiset(sup,sun,svp,svn,swp,swn,3,out_up,out_un,out_vp,out_vn,out_wp,out_wn,3) == 0)

# 4->3: reverse a split while retaining two independent terms.
z = fftsrtest_zero(sup,4)
z = fftsrtest_zero(sun,4)
z = fftsrtest_zero(svp,4)
z = fftsrtest_zero(svn,4)
z = fftsrtest_zero(swp,4)
z = fftsrtest_zero(swn,4)
sup[0] = 1
svp[0] = 1
swp[0] = 1
sup[1] = 2
svp[1] = 1
swp[1] = 1
sup[2] = 4
svp[2] = 1
swp[2] = 2
sup[3] = 8
svp[3] = 1
swp[3] = 4
found = fftsr_find_terms_ws(sup,sun,svp,svn,swp,swn,2,4,3,workspace,out_up,out_un,out_vp,out_vn,out_wp,out_wn,meta)
z = fftsrtest_expect("planted strict 4->3 found",found == 3)
z = fftsrtest_expect("planted strict 4->3 exact",fftsrtest_exact(sup,sun,svp,svn,swp,swn,4,out_up,out_un,out_vp,out_vn,out_wp,out_wn,3,4) == 1)

# Goal-directed collision compaction.  The old pair
#   u*v*w + u*v'*w'
# refactors to
#   u*(v+v')*w + u*v'*(w'-w).
# An external negative copy of the first new term cancels, leaving the second
# new term and the unrelated third source: four terms compact to two.
z = fftsrtest_zero(sup,4)
z = fftsrtest_zero(sun,4)
z = fftsrtest_zero(svp,4)
z = fftsrtest_zero(svn,4)
z = fftsrtest_zero(swp,4)
z = fftsrtest_zero(swn,4)
sup[0] = 1
svp[0] = 1
swp[0] = 1
sup[1] = 1
svp[1] = 2
swp[1] = 2
sup[2] = 4
svp[2] = 4
swp[2] = 4
external_up = i64[1]
external_un = i64[1]
external_vp = i64[1]
external_vn = i64[1]
external_wp = i64[1]
external_wn = i64[1]
external_up[0] = 1
external_vp[0] = 3
external_wn[0] = 1
no_selected_external = i64[3]
no_selected_external[0] = 0 - 1
no_selected_external[1] = 0 - 1
no_selected_external[2] = 0 - 1
found = fftsr_find_collision_terms_ws(sup,sun,svp,svn,swp,swn,2,3,external_up,external_un,external_vp,external_vn,external_wp,external_wn,1,no_selected_external,workspace,out_up,out_un,out_vp,out_vn,out_wp,out_wn,meta)
z = fftsrtest_expect("planted external cancellation found",found == 3 && meta[15] == 0 && meta[14] == 1)
z = fftsrtest_expect("planted external replacement exact",fftsrtest_exact(sup,sun,svp,svn,swp,swn,3,out_up,out_un,out_vp,out_vn,out_wp,out_wn,3,4) == 1)
left_up = i64[4]
left_un = i64[4]
left_vp = i64[4]
left_vn = i64[4]
left_wp = i64[4]
left_wn = i64[4]
i = 0 ## i64
while i < 3
  left_up[i] = sup[i]
  left_un[i] = sun[i]
  left_vp[i] = svp[i]
  left_vn[i] = svn[i]
  left_wp[i] = swp[i]
  left_wn[i] = swn[i]
  i += 1
left_up[3] = external_up[0]
left_un[3] = external_un[0]
left_vp[3] = external_vp[0]
left_vn[3] = external_vn[0]
left_wp[3] = external_wp[0]
left_wn[3] = external_wn[0]
compact_up = i64[2]
compact_un = i64[2]
compact_vp = i64[2]
compact_vn = i64[2]
compact_wp = i64[2]
compact_wn = i64[2]
write = 0 ## i64
i = 0
while i < 3
  cancels = 0 ## i64
  if out_up[i] == external_up[0] && out_un[i] == external_un[0] && out_vp[i] == external_vp[0] && out_vn[i] == external_vn[0] && out_wp[i] == external_wn[0] && out_wn[i] == external_wp[0]
    cancels = 1
  if cancels == 0
    compact_up[write] = out_up[i]
    compact_un[write] = out_un[i]
    compact_vp[write] = out_vp[i]
    compact_vn[write] = out_vn[i]
    compact_wp[write] = out_wp[i]
    compact_wn[write] = out_wn[i]
    write += 1
  i += 1
z = fftsrtest_expect("external cancellation compacts four terms to two",write == 2)
z = fftsrtest_expect("compacted collision identity exact",fftsrtest_exact(left_up,left_un,left_vp,left_vn,left_wp,left_wn,4,compact_up,compact_un,compact_vp,compact_vn,compact_wp,compact_wn,2,4) == 1)

# The cap is explicit: a fully independent three-generator fixture has the
# maximum 2*13^3=4394 signed candidates and is rejected by a tiny workspace.
z = fftsrtest_zero(sup,4)
z = fftsrtest_zero(sun,4)
z = fftsrtest_zero(svp,4)
z = fftsrtest_zero(svn,4)
z = fftsrtest_zero(swp,4)
z = fftsrtest_zero(swn,4)
i = 0
while i < 3
  sup[i] = 1 << i
  svp[i] = 1 << i
  swp[i] = 1 << i
  i += 1
tiny = FFTSRWorkspace.new(16)
found = fftsr_find_terms_ws(sup,sun,svp,svn,swp,swn,2,3,2,tiny,out_up,out_un,out_vp,out_vn,out_wp,out_wn,meta)
z = fftsrtest_expect("bounded catalogue reports over-cap",found == 0 && meta[3] == 4394 && meta[8] == 1)

# Full matrix-multiplication splice: split one Strassen term to an exact rank-8
# shoulder, recover a 3->2 local refactor, splice it, and pass the complete
# 64-cell integer gate at rank seven.
capacity = fft_default_capacity(2) ## i64
state = i64[fft_state_size(capacity)]
rank = fft_init_strassen(state,capacity,2026071501,3) ## i64
z = fftsrtest_expect("Strassen seed gates",rank == 7 && fft_verify_current_exact(state) == 1)
z = fftsrtest_expect("Strassen split opens shoulder",fft_split_partition(state,0,0,1) == 1 && state[5] == 8 && fft_verify_current_exact(state) == 1)
selected = i64[3]
selected[0] = 0
selected[1] = 7
selected[2] = 1
found = fftsr_find_current_ws(state,selected,3,2,workspace,out_up,out_un,out_vp,out_vn,out_wp,out_wn,meta)
z = fftsrtest_expect("Strassen shoulder 3->2 found",found == 2)
spliced = fftsr_splice_current(state,selected,3,out_up,out_un,out_vp,out_vn,out_wp,out_wn,2,0) ## i64
z = fftsrtest_expect("Strassen shoulder splices to exact rank seven",spliced == 7 && state[5] == 7 && fft_verify_current_exact(state) == 1)

<< "PASS strict ternary signed-span refactor: planted 3->2, 3<->3, 4->3, external cancellation 4->2, explicit cap, and exact Strassen shoulder splice"
