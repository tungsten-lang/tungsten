# Boxed-operator inline fast helpers (__w_mul/div/mod/band/bor/bxor/shl/shr_fast,
# __w_int_fast/__w_to_i64_fast — emitter.w) routed via the lowering op map.
# Pins the fast arms AND every slow-path semantic they must preserve:
# i48-boundary BigInt promotion, BigInt operands, polymorphic `<<`
# (strbuf/string/array append), negative/huge shift counts, arithmetic shr.
# Values verified against the interpreter (arbitrary-precision oracle).
#
# Run: `bin/tungsten -o /tmp/baf spec/compiler/boxed_arith_fast_spec.w && /tmp/baf`

-> check(name, got, want)
  if got.to_s() == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want
    exit 1

-> b2(x, y)
  [x * y, x & y, x | y, x ^ y, x << y, x >> y]

-> shr2(x, y)
  x >> y

-> divmod2(x, y)
  [x / y, x % y]

-> shl_str(a, b)
  a << b

-> apush(a, v)
  a << v

check("fast.small", b2(12345, 7), "\[86415, 1, 12351, 12350, 1580160, 96]")
check("fast.negative", b2(0 - 99, 3), "\[-297, 1, -97, -98, -792, -13]")
check("fast.divmod_positive", divmod2(99, 7), "\[14, 1]")
check("fast.divmod_negative", divmod2(0 - 99, 7), "\[-14, -1]")
check("fast.div_promotes_i48_boundary", (0 - 140737488355328) / (0 - 1), "140737488355328")
check("fast.i48_boundary", b2(140737488355327, 4), "\[562949953421308, 4, 140737488355327, 140737488355323, 2251799813685232, 8796093022207]")
check("fast.shl_overflow_bignum", b2(1, 60)[4], "1152921504606846976")
check("fast.shr_negative_arith", (0 - 1024) >> 4, "-64")
check("fast.shr_count_over_63_pos", shr2(500, 100), "0")
check("fast.shr_count_over_63_neg", shr2(0 - 500, 100), "-1")
check("fast.negative_shift_swaps", shr2(8, 0 - 2), "32")
bigv = 140737488355327 * 16
check("fast.bigint_operands", b2(bigv, 3), "\[6755399441055696, 0, 2251799813685235, 2251799813685235, 18014398509481856, 281474976710654]")
check("fast.divmod_bigint_operands", divmod2(bigv, 7), "\[321685687669318, 6]")
check("fast.divmod_float_fallback", divmod2(~9.5, ~2.0), "\[4.75, 1.5]")

sb = StringBuffer(8)
sb << "ab"
sb << 12
check("fast.shl_strbuf_append", sb.to_s(), "ab12")
arr = [1]
apush(arr, 9)
check("fast.shl_array_push", arr, "\[1, 9]")
# Append results canonicalize through w_string_n (<=61 bytes inline/slab or
# frozen-lookup), so == against an equal literal holds — this was FALSE when
# w_str_append minted mode-7 heap strings for canonical-range lengths.
app = shl_str("xy", "z")
check("fast.shl_string_append_size", app.size(), "3")
check("fast.shl_string_append_eq", app == "xyz", "true")
