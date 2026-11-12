# spec: compiled
# Integer#to_i is source-only. Integer literals and locals must autoload its
# class without an explicit `use core/integer`. Surplus arguments are a
# rescuable ArgumentError at the call (never silently dropped); a trailing
# block still passes through to the result.

-> check(name, got, want)
  if got != want
    << "FAIL [name]: got=[got] want=[want]"
    exit(1)

-> surplus_rejected?(f)
  begin
    f.call
    false
  rescue surplus_error
    true

values = [-140_737_488_355_328, -1, 0, 1, 42, 140_737_488_355_327]
i = 0
while i < values.size
  value = values[i]
  plain = value.to_i
  check("plain value", plain, value)
  check("plain bits", wvalue_bits(plain), wvalue_bits(value))
  check("surplus rejected", surplus_rejected?(->() value.to_i(7, 8, 9)), true)
  i += 1

hits = 0
values[4].to_i -> (ignored)
  hits += 1
check("trailing block passthrough", hits, 42)

<< "PASS Integer#to_i source autoload"
