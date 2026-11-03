# `(float expression) ## i64` converts the expression's VALUE: the arithmetic
# runs in floating point and the result is truncated toward zero, as `.to_i`
# does. The compiled lowering used to push the integer context into the
# operands, so `(a * ~48000.0) ## i64` computed trunc(a) * 48000 (0 for
# a = ~0.279) on the compiled engine while the interpreter printed 13392.
# Integer arithmetic under the same hints keeps its machine-width wrapping.

$failures = 0

-> check(label, got, want)
  if got != want
    << "FAIL [label]: got [got], want [want]"
    $failures = $failures + 1

-> samples(t0) (f64) i64
  (t0 * ~48000.0) ## i64

-> samples_return(t0) (f64) i64
  return t0 * ~48000.0 ## i64

-> samples_i32(t0) (f64) i32
  (t0 * ~48000.0) ## i32

-> seconds() f64
  ~0.279

-> scaled_at(xs, i) (f64[] i64) i64
  (xs[i] * ~10.0) ## i64

-> untyped_product(t, k)
  (t * k) ## i64

-> untyped_half(t)
  (t * ~0.5) ## i64

-> main(args)
  # The original report (audio sample offsets at 48 kHz).
  a = ~0.279
  b = (a * ~48000.0) ## i64
  check("assign product i64", b, 13392)
  check("typed fn body", samples(~1.484), 71232)
  check("typed fn return", samples_return(~1.484), 71232)
  check("to_i agrees", (a * ~48000.0).to_i, 13392)
  check("inline product", ((a * ~48000.0) ## i64) + 0, 13392)

  # The unparenthesized assignment hint covers the whole right-hand side.
  d = a * ~48000.0 ## i64
  check("unparenthesized assign", d, 13392)

  # Products, sums and quotients cast to i64.
  x = ~1.75
  check("sum i64", (~2.5 + ~0.75) ## i64, 3)
  check("sum var i64", (~1.484 + ~0.6) ## i64, 2)
  check("difference i64", (x - ~0.5) ## i64, 1)
  check("quotient i64", (x / ~0.25) ## i64, 7)
  check("literal product i64", (~2.5 * ~3.0) ## i64, 7)
  check("negative product i64", (~-2.5 * ~3.0) ## i64, -7)
  na = ~1.5
  check("negated operand i64", (-na * ~3.0) ## i64, -4)
  i = 7
  check("int plus float i64", (i + ~0.5 * ~3.0) ## i64, 8)
  check("int times float i64", (i * ~0.5) ## i64, 3)
  check("float power i64", (~1.5 ** 2) ## i64, 2)

  # The same expressions cast to i32.
  check("product i32", (a * ~48000.0) ## i32, 13392)
  c = (a * ~48000.0) ## i32
  check("assign product i32", c, 13392)
  check("sum i32", (~2.5 + ~0.75) ## i32, 3)
  check("quotient i32", (x / ~0.25) ## i32, 7)
  check("typed fn i32", samples_i32(~1.484), 71232)

  # Casts to f32 keep the value floating-point (exactly representable here).
  check("product f32", (~0.5 * ~1.5) ## f32, ~0.75)
  check("quotient f32", (~3.0 / ~4.0) ## f32, ~0.75)
  n = 5
  check("int product f32", (n * 3) ## f32, ~15.0)
  check("int plus float f32", (n + ~0.25) ## f32, ~5.25)

  # Nested casts: each ascription converts its own value. `## T` runs to the
  # end of its group, so a cast used as an operand sits in its own parens.
  check("nested i64 plus int", (((a * ~48000.0) ## i64) + 1) ## i64, 13393)
  check("nested i64 times int", (((a * ~1000.0) ## i64) * 48) ## i64, 13392)
  check("nested i32 times float", (((a * ~10.0) ## i32) * ~1.5) ## i64, 3)
  check("nested f64 inside i64", ((((n ## f64) / ~2.0) ## f64) * ~3.0) ## i64, 7)
  check("nested float of int cast", (((i * 3) ## f64) / ~2.0) ## i64, 10)

  # Calls and indexing as operands.
  check("call operand", (seconds() * ~48000.0) ## i64, 13392)
  check("method call operand", (~2.0.sqrt * ~10.0) ## i64, 14)
  xs = [~0.25, ~1.75] ## f64[]
  check("typed array index", (xs[1] * ~10.0) ## i64, 17)
  check("typed array index fn", scaled_at(xs, 1), 17)
  ys = [~0.25, ~1.75]
  check("array index", (ys[1] * ~10.0) ## i64, 17)
  check("untyped params", untyped_product(~0.279, 48000), 13392)
  check("untyped float literal", untyped_half(7), 3)

  # Integer arithmetic under a machine-int hint still wraps at 64 bits.
  m = 3 ## i64
  check("i64 wrap", (m * 4611686018427387904) ## i64, -4611686018427387904)
  check("i64 shift", ((m << 4) | 1) ## i64, 49)
  check("i64 quotient", (-7 / 2) ## i64, -3)

  if $failures > 0
    exit(1)
  << "PASS float expression int cast"
  0

main(argv())
