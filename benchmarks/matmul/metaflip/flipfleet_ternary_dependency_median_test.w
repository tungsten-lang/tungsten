use flipfleet_ternary_dependency_median

-> fftdmt_expect(label, condition) (String bool) i64
  if !condition
    << "TERNARY_DEPENDENCY_MEDIAN_FAIL " + label
    exit(1)
  1

-> fftdmt_prepare_local(st, up, un, vp, vn, wp, wn, rank, n, capacity) (i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64 i64 i64) i64
  if fft_prepare(st,n,capacity,97101,4) != 1
    return 0
  st[5] = rank
  i = 0 ## i64
  while i < rank
    st[st[32] + i] = up[i]
    st[st[33] + i] = un[i]
    st[st[34] + i] = vp[i]
    st[st[35] + i] = vn[i]
    st[st[36] + i] = wp[i]
    st[st[37] + i] = wn[i]
    if fft_canonicalize_slot(st,i) != 1
      return 0
    i += 1
  1

-> fftdmt_local_equal(st, rank, up, un, vp, vn, wp, wn, other_rank) (i64[] i64 i64[] i64[] i64[] i64[] i64[] i64[] i64) i64
  ai = 0 ## i64
  while ai < st[3]
    bi = 0 ## i64
    while bi < st[3]
      ci = 0 ## i64
      while ci < st[3]
        left = 0 ## i64
        term = 0 ## i64
        while term < rank
          left += fft_coefficient(st[st[32]+term],st[st[33]+term],ai) * fft_coefficient(st[st[34]+term],st[st[35]+term],bi) * fft_coefficient(st[st[36]+term],st[st[37]+term],ci)
          term += 1
        right = 0 ## i64
        term = 0
        while term < other_rank
          right += fft_coefficient(up[term],un[term],ai) * fft_coefficient(vp[term],vn[term],bi) * fft_coefficient(wp[term],wn[term],ci)
          term += 1
        if left != right
          return 0
        ci += 1
      bi += 1
    ai += 1
  1

# Independent tiny brute force used to check the pair/triple enumerator.  The
# first selected coefficient is fixed positive, removing overall-sign copies.
-> fftdmt_brute_unit_relations(st) (i64[]) i64
  count = 0 ## i64
  selected = i64[5]
  signs = i64[5]
  axis = 0 ## i64
  while axis < 3
    a = 0 ## i64
    while a < st[5] - 4
      b = a + 1 ## i64
      while b < st[5] - 3
        c = b + 1 ## i64
        while c < st[5] - 2
          d = c + 1 ## i64
          while d < st[5] - 1
            e = d + 1 ## i64
            while e < st[5]
              selected[0] = a
              selected[1] = b
              selected[2] = c
              selected[3] = d
              selected[4] = e
              pattern = 0 ## i64
              while pattern < 16
                signs[0] = 1
                i = 1 ## i64
                while i < 5
                  signs[i] = 1
                  if ((pattern >> (i - 1)) & 1) != 0
                    signs[i] = 0 - 1
                  i += 1
                if fftdm_relation_minimal(st,selected,signs,axis) == 1
                  count += 1
                pattern += 1
              e += 1
            d += 1
          c += 1
        b += 1
      a += 1
    axis += 1
  count

# Bit-sliced first-sign helpers cover cancellations and three-way majorities.
z = fftdmt_expect("pair cancel",fftdm_pair_first_sign(1,0,1,0,-1) == 0) ## i64
z = fftdmt_expect("pair double positive",fftdm_pair_first_sign(1,0,1,0,1) == 1)
z = fftdmt_expect("triple positive majority",fftdm_triple_first_sign(1,0,1,0,1,0,1,1) == 1)
z = fftdmt_expect("triple negative majority",fftdm_triple_first_sign(0,1,0,1,1,1,0,1) == -1)

# Planted primitive relation
#
#   e0 + e1 + e2 + e3 - (e0+e1+e2+e3) = 0.
#
# Four complementary matrices are y tensor (q_i-z), while the fifth is
# y tensor z.  Adding s_i*(y tensor z) leaves four y tensor q_i terms and
# cancels the fifth: a strict signed 5->4 median.
rank = 5 ## i64
capacity = 24 ## i64
up = i64[rank]
un = i64[rank]
vp = i64[rank]
vn = i64[rank]
wp = i64[rank]
wn = i64[rank]
up[0] = 1
up[1] = 2
up[2] = 4
up[3] = 8
up[4] = 15
q = i64[4]
q[0] = 1
q[1] = 4
q[2] = 8
q[3] = 5
i = 0 ## i64
while i < 5
  vp[i] = 1
  if i < 4
    wp[i] = q[i]
    wn[i] = 2
  else
    wp[i] = 2
  i += 1
local = i64[fft_state_size(capacity)]
z = fftdmt_expect("local prepare",fftdmt_prepare_local(local,up,un,vp,vn,wp,wn,rank,2,capacity) == 1)
selected = i64[5]
signs = i64[5]
i = 0
while i < 5
  selected[i] = i
  signs[i] = 1
  i += 1
signs[4] = 0 - 1
z = fftdmt_expect("integer relation",fftdm_relation_minimal(local,selected,signs,0) == 1)
out_up = i64[capacity]
out_un = i64[capacity]
out_vp = i64[capacity]
out_vn = i64[capacity]
out_wp = i64[capacity]
out_wn = i64[capacity]
made = fftdm_build_endpoint(local,selected,signs,0,1,1,0,2,0,out_up,out_un,out_vp,out_vn,out_wp,out_wn) ## i64
z = fftdmt_expect("planted 5to4",made == 4)
z = fftdmt_expect("local integer equality",fftdmt_local_equal(local,5,out_up,out_un,out_vp,out_vn,out_wp,out_wn,made) == 1)
search_meta = i64[16]
searched = fftdm_search(local,0,2,out_up,out_un,out_vp,out_vn,out_wp,out_wn,search_meta) ## i64
z = fftdmt_expect("complete search finds planted",searched == 4 && search_meta[4] >= 1 && search_meta[8] >= 1)
z = fftdmt_expect("pair triple equals brute force",search_meta[4] == fftdmt_brute_unit_relations(local))
z = fftdmt_expect("searched integer equality",fftdmt_local_equal(local,5,out_up,out_un,out_vp,out_vn,out_wp,out_wn,searched) == 1)

# A genuine GF(2) five-circuit with no +/-1 integer dependency must not enter
# the signed lane.  Modulo two, 1 xor 3 xor 5 xor 9 xor 14 is zero; its four
# coordinate equations would require one coefficient to equal three others.
false_up = i64[5]
false_un = i64[5]
false_vp = i64[5]
false_vn = i64[5]
false_wp = i64[5]
false_wn = i64[5]
false_values = i64[5]
false_values[0] = 1
false_values[1] = 3
false_values[2] = 5
false_values[3] = 9
false_values[4] = 14
i = 0
while i < 5
  false_up[i] = false_values[i]
  false_vp[i] = false_values[i]
  false_wp[i] = false_values[i]
  i += 1
false_state = i64[fft_state_size(capacity)]
z = fftdmt_expect("false local prepare",fftdmt_prepare_local(false_state,false_up,false_un,false_vp,false_vn,false_wp,false_wn,5,2,capacity) == 1)
false_meta = i64[16]
false_rank = fftdm_search(false_state,0,2,out_up,out_un,out_vp,out_vn,out_wp,out_wn,false_meta) ## i64
z = fftdmt_expect("reject mod2-only circuit",false_rank == 0 && false_meta[4] == 0 && false_meta[4] == fftdmt_brute_unit_relations(false_state))

# Embed the planted equality as S-R=0 next to Laderman.  The complete integer
# matrix-multiplication gate accepts the shoulder, and the median replaces S
# by R so opposite compaction returns all the way to rank 23.
n = 3 ## i64
capacity3 = fft_default_capacity(n) ## i64
base = i64[fft_state_size(capacity3)]
base_rank = fft_init_laderman(base,capacity3,97201,4) ## i64
z = fftdmt_expect("laderman exact",base_rank == 23 && fft_verify_current_exact(base) == 1)
mapped_up = i64[5]
mapped_un = i64[5]
mapped_vp = i64[5]
mapped_vn = i64[5]
mapped_wp = i64[5]
mapped_wn = i64[5]
mapped_up[0] = 256
mapped_up[1] = 128
mapped_up[2] = 64
mapped_up[3] = 32
mapped_up[4] = 480
mapped_q = i64[4]
mapped_q[0] = 1
mapped_q[1] = 2
mapped_q[2] = 4
mapped_q[3] = 64
i = 0
while i < 5
  mapped_vp[i] = 16
  if i < 4
    mapped_wp[i] = mapped_q[i]
    mapped_wn[i] = 8
  else
    mapped_wp[i] = 8
  i += 1
mapped_local = i64[fft_state_size(capacity3)]
z = fftdmt_expect("mapped prepare",fftdmt_prepare_local(mapped_local,mapped_up,mapped_un,mapped_vp,mapped_vn,mapped_wp,mapped_wn,5,n,capacity3) == 1)
replacement_up = i64[capacity3]
replacement_un = i64[capacity3]
replacement_vp = i64[capacity3]
replacement_vn = i64[capacity3]
replacement_wp = i64[capacity3]
replacement_wn = i64[capacity3]
replacement_rank = fftdm_build_endpoint(mapped_local,selected,signs,0,1,16,0,8,0,replacement_up,replacement_un,replacement_vp,replacement_vn,replacement_wp,replacement_wn) ## i64
z = fftdmt_expect("mapped replacement",replacement_rank == 4 && fftdmt_local_equal(mapped_local,5,replacement_up,replacement_un,replacement_vp,replacement_vn,replacement_wp,replacement_wn,4) == 1)

shoulder_up = i64[capacity3]
shoulder_un = i64[capacity3]
shoulder_vp = i64[capacity3]
shoulder_vn = i64[capacity3]
shoulder_wp = i64[capacity3]
shoulder_wn = i64[capacity3]
shoulder_rank = 0 ## i64
i = 0
while i < base_rank
  shoulder_rank = fftdm_append(shoulder_up,shoulder_un,shoulder_vp,shoulder_vn,shoulder_wp,shoulder_wn,shoulder_rank,capacity3,base[base[32]+i],base[base[33]+i],base[base[34]+i],base[base[35]+i],base[base[36]+i],base[base[37]+i])
  i += 1
i = 0
while i < 5
  shoulder_rank = fftdm_append(shoulder_up,shoulder_un,shoulder_vp,shoulder_vn,shoulder_wp,shoulder_wn,shoulder_rank,capacity3,mapped_up[i],mapped_un[i],mapped_vp[i],mapped_vn[i],mapped_wp[i],mapped_wn[i])
  i += 1
i = 0
while i < replacement_rank
  shoulder_rank = fftdm_append(shoulder_up,shoulder_un,shoulder_vp,shoulder_vn,shoulder_wp,shoulder_wn,shoulder_rank,capacity3,replacement_up[i],replacement_un[i],replacement_vp[i],replacement_vn[i],replacement_wn[i],replacement_wp[i])
  i += 1
shoulder = i64[fft_state_size(capacity3)]
shoulder_loaded = fft_init_terms(shoulder,shoulder_up,shoulder_un,shoulder_vp,shoulder_vn,shoulder_wp,shoulder_wn,shoulder_rank,n,capacity3,97301,4) ## i64
z = fftdmt_expect("shoulder full integer gate",shoulder_rank == 32 && shoulder_loaded == 32 && fft_verify_current_exact(shoulder) == 1)

restored_up = i64[capacity3]
restored_un = i64[capacity3]
restored_vp = i64[capacity3]
restored_vn = i64[capacity3]
restored_wp = i64[capacity3]
restored_wn = i64[capacity3]
restore_meta = i64[16]
restored_rank = fftdm_search(shoulder,0,2,restored_up,restored_un,restored_vp,restored_vn,restored_wp,restored_wn,restore_meta) ## i64
restored = i64[fft_state_size(capacity3)]
restored_loaded = fft_init_terms(restored,restored_up,restored_un,restored_vp,restored_vn,restored_wp,restored_wn,restored_rank,n,capacity3,97401,4) ## i64
z = fftdmt_expect("restored rank23 full gate",restored_rank == 23 && restored_loaded == 23 && fft_verify_current_exact(restored) == 1)

<< "flipfleet_ternary_dependency_median_test: pass local=5->" + made.to_s() + " shoulder=" + shoulder_rank.to_s() + "->" + restored_rank.to_s() + " circuits=" + restore_meta[4].to_s() + " changed=" + restore_meta[7].to_s()
