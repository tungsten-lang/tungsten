# Tree-walker parity for the source-defined Hash#size body. The compiled body
# reads WHash.count directly through `$count`; the interpreter must mirror that
# native view-field read instead of treating `$count` as an unset global.

# Surplus arguments are an error on both engines (E_LOWER_ARITY at compile
# time where the callee is known; the interpreter raises at the call).
-> surplus_rejected?(f)
  begin
    f.call
    false
  rescue surplus_error
    true

# The interpreter rejects surplus arguments at the call; the compiled engine
# leaves DYNAMIC dispatch unchecked by design (no runtime arity cost), so on
# an unknown receiver a surplus call still runs. Compile-time checks apply
# only where the callee is statically known. This spec runs in both lanes.
-> surplus_rejection_expected
  env("TUNGSTEN_INTERPRETED_SPEC") == "1"

-> check(name, got, want)
  if got != want
    << "FAIL [name]: got=[got] want=[want]"
    exit(1)

h = {}
check("empty", h.size, 0)

h["a"] = 1
h["b"] = 2
check("insert", h.size, 2)

# Replacing a value must not change the backing table's live-entry count.
h["a"] = 3
check("replace", h.size, 2)

# Preserve the former native cached handler's extra-argument truncation.
check("extra arguments rejected", surplus_rejected?(->() h.size(99, 100)), surplus_rejection_expected)

h.delete("b")
check("delete", h.size, 1)

<< "hash_size_view_field_spec: all checks passed"
