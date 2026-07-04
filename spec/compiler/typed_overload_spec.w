# Dogfood for TOP-LEVEL typed function overloads (gap 4).
#
# Declaring the same function name+arity more than once, distinguished by a
# parameter type, used to HANG the compiler: both definitions collapsed onto
# the bare `__w_NAME` symbol (the `typed_overload` flag was never set because
# its setter wasn't declared, so the write was dropped), and two identically-
# named functions sent escape_pass's name-keyed topo-sort into an infinite
# loop. Now each overload gets a distinct signature-mangled symbol and the
# call site resolves by inferred argument type.
#
# Run: `bin/tungsten -o /tmp/to spec/compiler/typed_overload_spec.w && /tmp/to`.

-> describe/1(i64)
  "int"

-> describe/1(f64)
  "float"

-> describe/1(String)
  "string"

-> kind/2(i64 i64)
  "two-ints"

-> kind/2(f64 f64)
  "two-floats"

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()

# Dispatch by a single argument's type.
check("ovl.int", describe(5), "int")
check("ovl.float", describe(~5.0), "float")
check("ovl.string", describe("hi"), "string")

# Dispatch across a 2-arg overload set (distinct signatures, same arity).
check("ovl.two_ints", kind(1, 2), "two-ints")
check("ovl.two_floats", kind(~1.0, ~2.0), "two-floats")
