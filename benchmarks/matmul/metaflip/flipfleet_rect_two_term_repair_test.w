use flipfleet_rect_two_term_repair

-> ffr2trt_expect(label, condition) (String bool) i64
  if !condition
    << "FAIL " + label
    exit(1)
  1

n = 2 ## i64
m = 2 ## i64
p = 5 ## i64
words = ffrrw_tensor_words(n, m, p) ## i64

# Independent U factors: the U-slice space has rank two and both selected
# matrices are rank one.
u = i64[3]
v = i64[3]
w = i64[3]
u[0] = 3
v[0] = 5
w[0] = 9
u[1] = 6
v[1] = 12
w[1] = 17
carrier = i64[words]
z = ffrrw_build_term_target(u, v, w, 2, n, m, p, carrier) ## i64
du = i64[2]
dv = i64[2]
dw = i64[2]
meta = i64[3]
rank = ffr2tr_decompose(carrier, n, m, p, du, dv, dw, meta) ## i64
z = ffr2trt_expect("rank-two slice decomposition", rank == 2 && meta[0] == 2 && ffr2tr_rebuild(du, dv, dw, rank, n, m, p, carrier) == 1)

# Shared U factor: reduce to a rank-two VxW matrix.
u[0] = 5
u[1] = 5
v[0] = 3
w[0] = 5
v[1] = 12
w[1] = 18
z = ffrrw_build_term_target(u, v, w, 2, n, m, p, carrier)
rank = ffr2tr_decompose(carrier, n, m, p, du, dv, dw, meta)
z = ffr2trt_expect("rank-one U flattening", rank == 2 && meta[0] == 1 && ffr2tr_rebuild(du, dv, dw, rank, n, m, p, carrier) == 1)

# A true rank-one carrier materializes one term.
z = ffrrw_build_term_target(u, v, w, 1, n, m, p, carrier)
rank = ffr2tr_decompose(carrier, n, m, p, du, dv, dw, meta)
z = ffr2trt_expect("rank one", rank == 1 && ffr2tr_rebuild(du, dv, dw, rank, n, m, p, carrier) == 1)

# Three independent U slices force flattening rank three and must fail closed.
u[0] = 1
v[0] = 1
w[0] = 1
u[1] = 2
v[1] = 2
w[1] = 2
u[2] = 4
v[2] = 4
w[2] = 4
z = ffrrw_build_term_target(u, v, w, 3, n, m, p, carrier)
rank = ffr2tr_decompose(carrier, n, m, p, du, dv, dw, meta)
z = ffr2trt_expect("rank-three rejection", rank < 0 && meta[0] == 3)

# Shared U with a rank-three VxW matrix exercises the rank-one-U rejection.
u[0] = 5
u[1] = 5
u[2] = 5
v[0] = 1
w[0] = 1
v[1] = 2
w[1] = 2
v[2] = 4
w[2] = 4
z = ffrrw_build_term_target(u, v, w, 3, n, m, p, carrier)
rank = ffr2tr_decompose(carrier, n, m, p, du, dv, dw, meta)
z = ffr2trt_expect("rank-one U matrix-rank-three rejection", rank < 0 && meta[0] == 1)

# A two-dimensional U slice space whose three nonzero GF(2) matrices all have
# rank at least two must exhaust all basis variants and fail closed.
reject_u = i64[6]
reject_v = i64[6]
reject_w = i64[6]
reject_u[0] = 1
reject_v[0] = 1
reject_w[0] = 1
reject_u[1] = 1
reject_v[1] = 2
reject_w[1] = 2
reject_u[2] = 1
reject_v[2] = 4
reject_w[2] = 4
reject_u[3] = 2
reject_v[3] = 1
reject_w[3] = 2
reject_u[4] = 2
reject_v[4] = 2
reject_w[4] = 4
reject_u[5] = 2
reject_v[5] = 4
reject_w[5] = 1
z = ffrrw_build_term_target(reject_u, reject_v, reject_w, 6, n, m, p, carrier)
rank = ffr2tr_decompose(carrier, n, m, p, du, dv, dw, meta)
z = ffr2trt_expect("rank-two U all-bases rejection", rank < 0 && meta[0] == 2 && meta[2] == 3)

<< "PASS flipfleet rectangular two-term repair"
