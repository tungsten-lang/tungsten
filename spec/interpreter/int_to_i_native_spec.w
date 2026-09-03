# Tree-walker value parity for source-only Integer#to_i.

# Surplus arguments are an error on both engines (E_LOWER_ARITY at compile
# time where the callee is known; the interpreter raises at the call).
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

values = [-140_737_488_355_328, -1, 0, 1, 42, 140_737_488_355_327]
i = 0
while i < values.size
  value = values[i]
  check("plain identity", value.to_i, value)
  check("surplus-argument rejected", surplus_rejected?(->() value.to_i(7, 8, 9)), true)
  i += 1

hits = 0
values[4].to_i -> (ignored)
  hits += 1
# Tree-walker native dispatch historically ignores an attached block on this
# identity conversion; the source method preserves that interpreter behavior.
check("trailing block compatibility", hits, 0)

<< "PASS interpreter Integer#to_i source parity"
