# Tree-walker parity for the source-defined Hash#size body. The compiled body
# reads WHash.count directly through `$count`; the interpreter must mirror that
# native view-field read instead of treating `$count` as an unset global.

# Surplus arguments are an error on both engines: E_LOWER_ARITY at compile
# time where the receiver's class is statically known, otherwise a rescuable
# ArgumentError at the call (the interpreter when it binds parameters, the
# compiled engine on the inline-cache miss path). The probes below erase the
# receiver through an untyped container so the call is reached on both
# engines. This spec runs in both lanes.
-> surplus_rejected?(f)
  begin
    f.call
    false
  rescue surplus_error
    true

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

erased = [h, nil]
check("extra arguments rejected", surplus_rejected?(->() erased[0].size(99, 100)), true)

h.delete("b")
check("delete", h.size, 1)

<< "hash_size_view_field_spec: all checks passed"
