use flipfleet_projective_plane

-> ffppt_expect(label, condition) (String bool) i64
  if !condition
    << "PROJECTIVE_PLANE_TEST_FAIL " + label
    exit(1)
  1

# A Fano plane has exactly seven line complements / four-point circuits.
points = i64[7]
ffppt_expect("plane generated",ffpp_plane_from(1,2,4,points) == 7)
i = 0 ## i64
while i < 7
  ffppt_expect("canonical points",points[i] == i + 1)
  i += 1
ffppt_expect("seven quadrilateral circuits",ffpp_count_circuits(points) == 7)

# Planted projective-plane rank drop.  The five source terms are bucket-rank
# minimal and use the four-point circuit {1,2,4,7}.  Their best common-matrix
# toggle has rank four.  An exhaustive audit below proves that none of the ten
# 3-term or five 4-term subsets has a rank-lowering span-complete refactor.
su = i64[5]
sv = i64[5]
sw = i64[5]
su[0] = 4
sv[0] = 3
sw[0] = 1
su[1] = 1
sv[1] = 7
sw[1] = 1
su[2] = 2
sv[2] = 4
sw[2] = 7
su[3] = 7
sv[3] = 5
sw[3] = 1
su[4] = 4
sv[4] = 7
sw[4] = 4
out_u = i64[32]
out_v = i64[32]
out_w = i64[32]
meta = i64[16]
made = ffpp_optimize_group(su,sv,sw,5,0,points,9,out_u,out_v,out_w,meta) ## i64
ffppt_expect("planted 5 to 4",made == 4 && meta[5] == 5 && meta[6] == 4)
ffppt_expect("planted circuit used",meta[7] != 0 && ffw_popcount(meta[7]) == 4 && meta[8] != 0)
ffppt_expect("planted exact",meta[10] == 1 && ffgr_replacement_exact(su,sv,sw,5,out_u,out_v,out_w,made) == 1)
ffppt_expect("planted changed set",meta[11] == 0 && meta[12] > 0)

# Complete old span-lane audit: no 3->2 or 4->3 subset can make this drop.
span_drops = 0 ## i64
a = 0 ## i64
while a < 3
  b = a + 1 ## i64
  while b < 4
    c = b + 1 ## i64
    while c < 5
      sub_u = i64[4]
      sub_v = i64[4]
      sub_w = i64[4]
      sub_u[0] = su[a]
      sub_v[0] = sv[a]
      sub_w[0] = sw[a]
      sub_u[1] = su[b]
      sub_v[1] = sv[b]
      sub_w[1] = sw[b]
      sub_u[2] = su[c]
      sub_v[2] = sv[c]
      sub_w[2] = sw[c]
      sub_out_u = i64[4]
      sub_out_v = i64[4]
      sub_out_w = i64[4]
      sub_meta = i64[12]
      if ffsr_find_terms(sub_u,sub_v,sub_w,3,2,sub_out_u,sub_out_v,sub_out_w,sub_meta) > 0
        span_drops += 1
      c += 1
    b += 1
  a += 1
a = 0
while a < 2
  b = a + 1
  while b < 3
    c = b + 1
    while c < 4
      d = c + 1 ## i64
      while d < 5
        sub_u = i64[4]
        sub_v = i64[4]
        sub_w = i64[4]
        sub_u[0] = su[a]
        sub_v[0] = sv[a]
        sub_w[0] = sw[a]
        sub_u[1] = su[b]
        sub_v[1] = sv[b]
        sub_w[1] = sw[b]
        sub_u[2] = su[c]
        sub_v[2] = sv[c]
        sub_w[2] = sw[c]
        sub_u[3] = su[d]
        sub_v[3] = sv[d]
        sub_w[3] = sw[d]
        sub_out_u = i64[4]
        sub_out_v = i64[4]
        sub_out_w = i64[4]
        sub_meta = i64[12]
        if ffsr_find_terms(sub_u,sub_v,sub_w,4,3,sub_out_u,sub_out_v,sub_out_w,sub_meta) > 0
          span_drops += 1
        d += 1
      c += 1
    b += 1
  a += 1
ffppt_expect("outside k4 span drops",span_drops == 0)

# Exhaust every projective line in the planted plane.  No single pencil line
# lowers rank, and every line contains at most three source terms; the plane
# quadrilateral is therefore not a hidden direct matrix-pencil drop.
line_drops = 0 ## i64
max_line_group = 0 ## i64
mask = 1 ## i64
while mask < 128
  if ffw_popcount(mask) == 3
    line_xor = 0 ## i64
    point = 0 ## i64
    while point < 7
      if ((mask >> point) & 1) != 0
        line_xor = line_xor ^ points[point]
      point += 1
    if line_xor == 0
      line = i64[3]
      position = 0 ## i64
      point = 0
      while point < 7
        if ((mask >> point) & 1) != 0
          line[position] = points[point]
          position += 1
        point += 1
      selected = i64[5]
      line_u = i64[5]
      line_v = i64[5]
      line_w = i64[5]
      line_count = ffmp_capture_line(su,sv,sw,5,0,line,selected,line_u,line_v,line_w) ## i64
      if line_count > max_line_group
        max_line_group = line_count
      if line_count > 0
        line_out_u = i64[16]
        line_out_v = i64[16]
        line_out_w = i64[16]
        line_meta = i64[14]
        no_table = i32[1]
        line_made = ffmp_optimize_group(line_u,line_v,line_w,line_count,0,line,9,no_table,line_out_u,line_out_v,line_out_w,line_meta) ## i64
        if line_made < line_count
          line_drops += 1
  mask += 1
ffppt_expect("outside direct pencil drops",line_drops == 0 && max_line_group == 3)

# Honest overlap control: a general flatten-gauge search acts on the entire
# rank factorization, so the Fano identity is not a new algebraic orbit.  The
# shipped depth-four beam already reproduces a drop on this tiny plant.  The
# value of the projective operator is its complete structured D optimization,
# not disjointness from arbitrary flatten-gauge words.
packed_source = i64[15]
z = ffgr_pack(su,sv,sw,5,packed_source) ## i64
gauge_drops = 0 ## i64
axis = 0 ## i64
while axis < 3
  gauge_config = i64[4]
  gauge_config[0] = 5
  gauge_config[1] = axis
  gauge_config[2] = 4
  gauge_config[3] = 32
  gauge_output = i64[75]
  gauge_meta = i64[7]
  gauge_made = ffgr_search_packed(packed_source,gauge_config,gauge_output,gauge_meta) ## i64
  if gauge_made > 0 && gauge_made < 5
    gauge_drops += 1
  axis += 1
ffppt_expect("flatten gauge overlap exposed",gauge_drops > 0)

# Corrupting one output factor must fail the exhaustive local coefficient gate.
saved = out_w[0] ## i64
out_w[0] = out_w[0] ^ 8
ffppt_expect("negative local gate",ffgr_replacement_exact(su,sv,sw,5,out_u,out_v,out_w,made) == 0)
out_w[0] = saved

# Full n^6 control: add a four-term zero circuit to Strassen in a 3D U-plane.
# The plane contains only Strassen's U=9 term, so its maximal five-term subtotal
# is unambiguous.  The projective operator removes the null circuit and the
# generic splice helper must recover exact rank seven under the complete MMT
# verifier.
n = 2 ## i64
capacity = ffw_default_capacity(n) ## i64
base = i64[ffw_state_size(capacity)]
base_rank = ffw_load_scheme_cap(base,"benchmarks/matmul/metaflip/matmul_2x2_rank7_strassen_gf2.txt",n,capacity,971001,0,1,1,1) ## i64
ffppt_expect("Strassen exact",base_rank == 7 && ffw_verify_current_exact(base,n) == 1)
base_u = i64[capacity]
base_v = i64[capacity]
base_w = i64[capacity]
ffppt_expect("Strassen export",ffw_export_current(base,base_u,base_v,base_w) == 7)
shoulder_u = i64[capacity]
shoulder_v = i64[capacity]
shoulder_w = i64[capacity]
i = 0
while i < base_rank
  shoulder_u[i] = base_u[i]
  shoulder_v[i] = base_v[i]
  shoulder_w[i] = base_w[i]
  i += 1
zero_circuit = i64[4]
zero_circuit[0] = 2
zero_circuit[1] = 4
zero_circuit[2] = 11
zero_circuit[3] = 13
i = 0
while i < 4
  shoulder_u[base_rank+i] = zero_circuit[i]
  shoulder_v[base_rank+i] = 2
  shoulder_w[base_rank+i] = 4
  i += 1
shoulder = i64[ffw_state_size(capacity)]
shoulder_rank = ffw_init_terms_cap(shoulder,shoulder_u,shoulder_v,shoulder_w,11,n,capacity,971003,0,1,1,1) ## i64
ffppt_expect("full shoulder exact",shoulder_rank == 11 && ffw_verify_current_exact(shoulder,n) == 1)
full_points = i64[7]
ffppt_expect("full plane",ffpp_plane_from(2,4,9,full_points) == 7)
selected = i64[capacity]
captured_u = i64[capacity]
captured_v = i64[capacity]
captured_w = i64[capacity]
captured = ffpp_capture_plane(shoulder_u,shoulder_v,shoulder_w,shoulder_rank,0,full_points,selected,captured_u,captured_v,captured_w) ## i64
ffppt_expect("maximal full plane captured",captured == 5)
full_out_u = i64[32]
full_out_v = i64[32]
full_out_w = i64[32]
full_meta = i64[16]
full_made = ffpp_optimize_group(captured_u,captured_v,captured_w,captured,0,full_points,4,full_out_u,full_out_v,full_out_w,full_meta) ## i64
ffppt_expect("full plane five to one",full_made == 1 && full_meta[6] == 1 && full_meta[7] != 0)
recovered = i64[ffw_state_size(capacity)]
recovered_rank = ffmp_splice_state(shoulder,selected,captured,full_out_u,full_out_v,full_out_w,full_made,recovered,971007) ## i64
ffppt_expect("full n6 gate",recovered_rank == 7 && ffw_verify_current_exact(recovered,n) == 1)

<< "flipfleet_projective_plane_test: pass planted=5->" + made.to_s() + " span_drops=" + span_drops.to_s() + " line_drops=" + line_drops.to_s() + " gauge_drops=" + gauge_drops.to_s() + " max_line=" + max_line_group.to_s() + " full=11->" + recovered_rank.to_s()
