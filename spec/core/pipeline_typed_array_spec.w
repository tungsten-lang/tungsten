# Fused slash-pipelines over TYPED arrays — correctness matrix.
#
# Regression spec for the 2026-08-28 fix: the fused pipeline loop read every
# array source through the boxed-WValue inline slot read (:array_get_inline),
# which is only valid for plain arrays. Typed arrays store raw elements
# (different encodings and strides), so `%f64[…] /sq :sum` returned silently
# wrong numbers, f32 sources crashed, and i64[n] sources returned nil.
# Now: proven :array keeps the inline read; a proven f64 buffer takes a raw
# double loop (min/max via llvm.minimumnum/maximumnum where the host clang
# has them — NaN treated as missing, matching the runtime's NEON .min/.max);
# every other layout routes through the kind-dispatching w_array_get.
#
# Compiled-engine spec (the Ruby tree-walker does not evaluate pipeline
# :calc terminals at all — pre-existing gap, tracked separately):
#   bin/tungsten spec/core/pipeline_typed_array_spec.w

-> pipe_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

# --- %f64 literal source (raw fast path via Array#to_f64 inference) ---
a = %f64[1.5 2.5 0.5]
pipe_check("f64 sq max", a /sq :max == 6.25)
pipe_check("f64 sq min", a /sq :min == 0.25)
pipe_check("f64 sq sum", a /sq :sum == 8.75)
pipe_check("f64 sq product", a /sq :product == 3.515625)
pipe_check("f64 count", a /positive? :count == 3)
# Element-wise: array structural == is strict about Float-vs-Decimal
# representation, so compare scalars (which use relaxed numeric ==).
am = a /sq
pipe_check("f64 map materialize", am.size == 3 && am[0] == 2.25 && am[1] == 6.25 && am[2] == 0.25)
pipe_check("f64 empty select nil", (a /select(:negative?) :max) == nil)

# --- f64[n] constructor source ---
f = f64[4]
f[0] = 4.0
f[1] = -1.5
f[2] = 9.5
f[3] = 2.0
pipe_check("f64[n] max", f /sq :max == 90.25)
pipe_check("f64[n] sum", f /sq :sum == 112.5)
pipe_check("f64[n] min", f /sq :min == 2.25)

# --- NaN treated as missing data (IEEE-754-2019 minimumNumber/maximumNumber,
# --- consistent with the runtime NEON kernels behind bare .max/.min) ---
g = f64[3]
g[0] = Math.sqrt(-1.0) ## f64
g[1] = 2.5
g[2] = 1.5
pipe_check("f64 NaN-seed max", g /sq :max == 6.25)
pipe_check("f64 NaN-seed min", g /sq :min == 2.25)
g2 = f64[3]
g2[0] = Math.sqrt(-1.0) ## f64
g2[1] = 6.25
g2[2] = 2.25
pipe_check("f64 NaN matches runtime .max", g2.max == 6.25)

# --- i64[n] source (w_array_get fallback; was nil before the fix) ---
b = i64[3]
b[0] = 7
b[1] = 9
b[2] = 8
pipe_check("i64 sq max", b /sq :max == 81)
pipe_check("i64 sq sum", b /sq :sum == 194)

# --- %f32 source (w_array_get fallback; crashed before the fix) ---
c = %f32[1.5 2.5 0.5]
pipe_check("f32 sq sum", c /sq :sum == 8.75)
pipe_check("f32 sq max", c /sq :max == 6.25)

# --- u8 typed source (fallback, distinct stride) ---
u = u8[3]
u[0] = 3
u[1] = 5
u[2] = 4
pipe_check("u8 sq max", u /sq :max == 25)
pipe_check("u8 sq sum", u /sq :sum == 50)

# --- plain boxed array unchanged (inline fast path) ---
d = [1, 5, 3]
pipe_check("plain sq max", d /sq :max == 25)
pipe_check("plain sq sum", d /sq :sum == 35)
pipe_check("plain select", (d /select(:odd?)) == [1, 5, 3])

<< "pipeline_typed_array_spec: all passed"
