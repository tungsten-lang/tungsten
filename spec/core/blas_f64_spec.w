use core/blas

-> expect(name, condition)
  if condition
    << "PASS " + name
  else
    << "FAIL " + name
    exit 1

-> close?(actual, expected)
  delta = actual - expected
  delta = ~0.0 - delta if delta < ~0.0
  delta < ~0.00001

a = f64_array(6)
b = f64_array(3)
x = f64_array(3)
y = f64_array(3)
i = 0
while i < 6
  a[i] = (i + 1).to_f
  i += 1
b[0] = ~4.0
b[1] = ~5.0
b[2] = ~6.0
x[0] = ~1.0
x[1] = ~2.0
x[2] = ~3.0
y[0] = ~4.0
y[1] = ~5.0
y[2] = ~6.0

expect("blas.ddot", close?(ddot(a, b, 3), ~32.0))
expect("blas.dnrm2", close?(dnrm2(x, 3), Math.sqrt(~14.0)))
daxpy(~2.0, x, y, 3)
expect("blas.daxpy", close?(y[0], ~6.0) && close?(y[2], ~12.0))

dscal(~2.0, x, 3)
expect("blas.dscal", close?(x[0], ~2.0) && close?(x[2], ~6.0))

out = f64_array(2)
dgemv(a, b, out, 2, 3)
expect("blas.dgemv", close?(out[0], ~32.0) && close?(out[1], ~77.0))

sym = f64_array(9)
sym_values = [~4.0, ~1.0, ~2.0, ~1.0, ~5.0, ~3.0, ~2.0, ~3.0, ~6.0]
i = 0
while i < 9
  sym[i] = sym_values[i]
  i += 1
sym_x = f64_array(3)
sym_y = f64_array(3)
sym_x[0] = ~1.0
sym_x[1] = ~2.0
sym_x[2] = ~3.0
dsymv(sym, sym_x, sym_y, 3)
expect("blas.dsymv", close?(sym_y[0], ~12.0) && close?(sym_y[1], ~20.0) && close?(sym_y[2], ~26.0))

rank_a = f64_array(6)
rank_c = f64_array(4)
i = 0
while i < 6
  rank_a[i] = (i + 1).to_f
  i += 1
rank_c[0] = ~1.0
rank_c[1] = ~0.0
rank_c[2] = ~0.0
rank_c[3] = ~1.0
dsyrk(rank_a, rank_c, 2, 3, ~1.0, ~0.5)
expect("blas.dsyrk", close?(rank_c[0], ~14.5) && close?(rank_c[1], ~32.0) && close?(rank_c[2], ~0.0) && close?(rank_c[3], ~77.5))

tri = f64_array(4)
tri_rhs = f64_array(4)
tri[0] = ~2.0
tri[1] = ~0.0
tri[2] = ~3.0
tri[3] = ~4.0
tri_rhs[0] = ~2.0
tri_rhs[1] = ~4.0
tri_rhs[2] = ~11.0
tri_rhs[3] = ~18.0
dtrsm(tri, tri_rhs, 2, 2, ~1.0)
expect("blas.dtrsm", close?(tri_rhs[0], ~1.0) && close?(tri_rhs[1], ~2.0) && close?(tri_rhs[2], ~2.0) && close?(tri_rhs[3], ~3.0))

# Public scalar arguments accept ordinary integer literals. Native BLAS
# bridges consume f64 values, so Core must coerce before crossing the ccall.
integer_x = f64_array(1)
integer_y = f64_array(1)
integer_x[0] = ~3.0
integer_y[0] = ~4.0
daxpy(2, integer_x, integer_y, 1)
expect("blas.daxpy integer alpha", close?(integer_y[0], ~10.0))
integer_x[0] = ~3.0
dscal(2, integer_x, 1)
expect("blas.dscal integer alpha", close?(integer_x[0], ~6.0))

integer_rank_a = f64_array(1)
integer_rank_c = f64_array(1)
integer_rank_a[0] = ~3.0
integer_rank_c[0] = ~7.0
dsyrk(integer_rank_a, integer_rank_c, 1, 1, 2, 0)
expect("blas.dsyrk integer scalars", close?(integer_rank_c[0], ~18.0))

integer_tri = f64_array(1)
integer_rhs = f64_array(1)
integer_tri[0] = ~3.0
integer_rhs[0] = ~4.0
dtrsm(integer_tri, integer_rhs, 1, 1, 2)
expect("blas.dtrsm integer alpha", close?(integer_rhs[0], ~2.6666666666666665))

# Structured/output BLAS contracts reject overlapping typed-array storage.
# Distinct slice wrappers are covered at the shared byte-range boundary too.
alias_matrix = f64_array(4)
alias_matrix[0] = ~1.0
alias_matrix[1] = ~2.0
alias_matrix[2] = ~2.0
alias_matrix[3] = ~3.0
alias_vector = f64_array(2)
alias_vector[0] = ~1.0
alias_vector[1] = ~1.0
dgemv_alias_rejected = false
begin
  dgemv(alias_matrix, alias_vector, alias_vector, 2, 2)
rescue err
  dgemv_alias_rejected = true
expect("blas.dgemv rejects input/output alias", dgemv_alias_rejected)

dsymv_alias_rejected = false
begin
  dsymv(alias_matrix, alias_vector, alias_vector, 2)
rescue err
  dsymv_alias_rejected = true
expect("blas.dsymv rejects input/output alias", dsymv_alias_rejected)

dsyrk_alias_rejected = false
begin
  dsyrk(alias_matrix, alias_matrix, 2, 2, 1, 0)
rescue err
  dsyrk_alias_rejected = true
expect("blas.dsyrk rejects input/output alias", dsyrk_alias_rejected)

dtrsm_alias_rejected = false
begin
  dtrsm(alias_matrix, alias_matrix, 2, 2, 1)
rescue err
  dtrsm_alias_rejected = true
expect("blas.dtrsm rejects input/output alias", dtrsm_alias_rejected)
