use flipfleet_ternary_gl3_tunnel

-> fftg3t_expect(label, condition) (String bool) i64
  if !condition
    << "FAIL " + label
    exit(1)
  1

-> fftg3t_local_cell(st, ai,bi,ci) (i64[] i64 i64 i64) i64
  value = 0 ## i64
  term = 0 ## i64
  while term < 3
    value += fft_coefficient(st[st[32]+term],st[st[33]+term],ai) * fft_coefficient(st[st[34]+term],st[st[35]+term],bi) * fft_coefficient(st[st[36]+term],st[st[37]+term],ci)
    term += 1
  value

-> fftg3t_best_distance(left, right) (i64[] i64[]) i64
  common = 0 ## i64
  i = 0 ## i64
  while i < left[6]
    j = 0 ## i64
    found = 0 ## i64
    while j < right[6] && found == 0
      equal = 1 ## i64
      axis = 0 ## i64
      while axis < 6
        if left[left[38+axis]+i] != right[right[38+axis]+j]
          equal = 0
        axis += 1
      if equal == 1
        found = 1
      j += 1
    common += found
    i += 1
  left[6] + right[6] - 2 * common

# Every checked-in catalogue representative really is unimodular with the
# advertised inverse.
kind = 0 ## i64
while kind < 5
  row = 0 ## i64
  while row < 3
    column = 0 ## i64
    while column < 3
      product = 0 ## i64
      k = 0 ## i64
      while k < 3
        product += fft_gl3_matrix(kind,row,k) * fft_gl3_inverse(kind,k,column)
        k += 1
      want = 0 ## i64
      if row == column
        want = 1
      z = fftg3t_expect("GL3 representative inverse", product == want) ## i64
      column += 1
    row += 1
  kind += 1

# Planted tunnel.  These three U*V terms share projective W.  After gauge
# canonicalization no legal pair flip exists on any axis or sign, yet GL3
# representative 1/gauge 4 has a different valid ternary endpoint.  One
# output coordinate contains a (+1)+(+1)+(-1) cancellation.  The exhaustive
# pair probe, rather than that cancellation alone, proves the blocked source.
planted = i64[fft_state_size(8)]
z = fft_prepare(planted,2,8,2026071431,2) ## i64
planted[5] = 3
planted[planted[32]+0] = 10
planted[planted[33]+0] = 1
planted[planted[34]+0] = 10
planted[planted[35]+0] = 4
planted[planted[36]+0] = 1
planted[planted[37]+0] = 0
planted[planted[32]+1] = 9
planted[planted[33]+1] = 4
planted[planted[34]+1] = 6
planted[planted[35]+1] = 8
planted[planted[36]+1] = 1
planted[planted[37]+1] = 0
planted[planted[32]+2] = 9
planted[planted[33]+2] = 4
planted[planted[34]+2] = 1
planted[planted[35]+2] = 0
planted[planted[36]+2] = 1
planted[planted[37]+2] = 0
i = 0
while i < 3
  z = fft_canonicalize_slot(planted,i)
  i += 1
planted[20] = fft_current_density(planted)
planted[6] = 3
planted[21] = planted[20]
before = i64[64]
ai = 0 ## i64
while ai < 4
  bi = 0 ## i64
  while bi < 4
    ci = 0 ## i64
    while ci < 4
      before[(ai*4+bi)*4+ci] = fftg3t_local_cell(planted,ai,bi,ci)
      ci += 1
    bi += 1
  ai += 1

pair_accepts = 0 ## i64
left = 0 ## i64
while left < 3
  right = 0 ## i64
  while right < 3
    if left != right
      axis = 0 ## i64
      while axis < 3
        pair_accepts += fft_basis_flip_pair(planted,left,right,axis,1,1)
        pair_accepts += fft_basis_flip_pair(planted,left,right,axis,0-1,1)
        axis += 1
    right += 1
  left += 1
z = fftg3t_expect("planted pair-flip component is singleton", pair_accepts == 0)
old_fingerprint = fft_current_fingerprint(planted) ## i64
result = fft_gl3_apply(planted,0,1,2,2,1,4,1) ## i64
z = fftg3t_expect("planted GL3 endpoint accepted", result == 1)
z = fftg3t_expect("planted GL3 endpoint changed", fft_current_fingerprint(planted) != old_fingerprint)
z = fftg3t_expect("planted GL3 endpoint used three-way cancellation", planted[52] == 1)
ai = 0
while ai < 4
  bi = 0
  while bi < 4
    ci = 0
    while ci < 4
      z = fftg3t_expect("planted GL3 local tensor preserved", fftg3t_local_cell(planted,ai,bi,ci) == before[(ai*4+bi)*4+ci])
      ci += 1
    bi += 1
  ai += 1

root = "benchmarks/matmul/metaflip/"
capacity5 = fft_default_capacity(5) ## i64
source5 = i64[fft_state_size(capacity5)]
descent5 = i64[fft_state_size(capacity5)]
rank5 = fft_load_seed(source5,root + "matmul_5x5_rank93_d1249_ternary_walk.txt",5,capacity5,2026071451,3) ## i64
z = fftg3t_expect("5x5 density seed integer-gates", rank5 == 93)
z = fft_clone_gated_seed(descent5,source5,2026071452,3)
improvements = fft_gl3_directed_descent(descent5) ## i64
z = fftg3t_expect("5x5 GL3 descent found one strict improvement", improvements == 1)
z = fftg3t_expect("5x5 GL3 descent reaches r93/d1248", descent5[6] == 93 && descent5[21] == 1248)
z = fftg3t_expect("5x5 GL3 result exact over integers", fft_verify_best_exact(descent5) == 1)
z = fftg3t_expect("5x5 GL3 result has term-set distance six", fftg3t_best_distance(source5,descent5) == 6)
z = fftg3t_expect("5x5 GL3 descent is at fixed point", fft_gl3_directed_descent(descent5) == 0 && descent5[21] == 1248)
z = fftg3t_expect("5x5 GL3 best dumps", fft_dump_best(descent5,"/tmp/matmul_5x5_rank93_d1248_gl3_ternary.txt") == 93)

paths = [
  root + "matmul_4x4_rank49_dronperminov_ternary.txt",
  root + "matmul_6x6_rank153_d2502_ternary_walk.txt",
  root + "matmul_7x7_rank250_dronperminov_ternary.txt"
]
dimensions = [4,6,7]
densities = [432,2502,2966]
i = 0
while i < paths.size()
  n = dimensions[i] ## i64
  capacity = fft_default_capacity(n) ## i64
  state = i64[fft_state_size(capacity)]
  rank = fft_load_seed(state,paths[i],n,capacity,2026071470+i,3) ## i64
  z = fftg3t_expect("control seed integer-gates", rank > 0)
  z = fftg3t_expect("control GL3 has no strict density descent", fft_gl3_directed_descent(state) == 0 && state[21] == densities[i])
  z = fftg3t_expect("control remains exact", fft_verify_best_exact(state) == 1)
  i += 1

<< "PASS ternary GL3 tunnel: planted pair component=1, 5x5 r93 d1249->d1248 distance=6 fixed-point, 4x4/6x6/7x7 strict controls negative"
