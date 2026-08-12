# Decimal methods must keep their packed/native and source behavior when the
# receiver crosses an untyped function boundary. BigDecimal exercises the
# heap-backed representation of the same public class.

-> check(name, got, want)
  if got == want
    << "PASS [name]"
  else
    << "FAIL [name] got=[got] want=[want]"
    exit 1

-> exercise(value)
  check("decimal.dynamic.to_i", value.to_i(), 0)
  check("decimal.dynamic.to_f", value.to_f(), ~0.5)
  check("decimal.dynamic.to_d", value.to_d(), 0.5)
  check("decimal.dynamic.abs", (0.0 - value).abs(), 0.5)
  check("decimal.dynamic.floor", value.floor(), 0)
  check("decimal.dynamic.ceil", value.ceil(), 1)
  check("decimal.dynamic.round", value.round(), 1)
  check("decimal.dynamic.sqrt", value.sqrt() > ~0.70 && value.sqrt() < ~0.71, true)
  check("decimal.dynamic.sq", value.sq(), 0.25)
  check("decimal.dynamic.normalize", value.normalize(), 0.5)
  check("decimal.dynamic.reciprocal", value.reciprocal(), 2.0)
  check("decimal.dynamic.inv", value.inv(), 2.0)
  check("decimal.dynamic.sin", value.sin(), Math.sin(~0.5))
  check("decimal.dynamic.cos", value.cos(), Math.cos(~0.5))
  check("decimal.dynamic.tan", value.tan(), Math.tan(~0.5))
  check("decimal.dynamic.arcsin", value.arcsin(), Math.asin(~0.5))
  check("decimal.dynamic.arccos", value.arccos(), Math.acos(~0.5))
  check("decimal.dynamic.arctan", value.arctan(), Math.atan(~0.5))
  check("decimal.dynamic.sinh", value.sinh(), Math.sinh(~0.5))
  check("decimal.dynamic.cosh", value.cosh(), Math.cosh(~0.5))
  check("decimal.dynamic.tanh", value.tanh(), Math.tanh(~0.5))
  check("decimal.dynamic.arcsinh", value.arcsinh(), Math.asinh(~0.5))
  check("decimal.dynamic.arctanh", value.arctanh(), Math.atanh(~0.5))

-> exercise_heap(value)
  check("decimal.dynamic.heap.type", type(value), "BigDecimal")
  check("decimal.dynamic.heap.abs", value.abs().to_s(), "123456789012345678901234567890.5")
  check("decimal.dynamic.heap.normalize", value.normalize().to_s(), "-123456789012345678901234567890.5")

# Decimal and Quantity share the physical 0xFFFD value tag. They must not
# share a monomorphic method-cache identity: alternating the same erased
# `to_f` call site used to reuse whichever handler ran first.
-> erased_to_f(value)
  value.to_f()

exercise(0.5)
exercise_heap(0.0 - 123456789012345678901234567890.5)
check("decimal.dynamic.cache.decimal.first", erased_to_f(0.5), ~0.5)
check("decimal.dynamic.cache.quantity", erased_to_f(2 m), ~2.0)
check("decimal.dynamic.cache.decimal.again", erased_to_f(0.25), ~0.25)
