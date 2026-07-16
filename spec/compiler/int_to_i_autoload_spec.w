# Integer#to_i is source-only. Integer literals and locals must autoload its
# class without an explicit `use core/integer`, while retaining native IC
# compatibility for surplus arguments and trailing blocks.

-> check(name, got, want)
  if got != want
    << "FAIL [name]: got=[got] want=[want]"
    exit(1)

values = [-140_737_488_355_328, -1, 0, 1, 42, 140_737_488_355_327]
i = 0
while i < values.size
  value = values[i]
  plain = value.to_i
  extra = value.to_i(7, 8, 9)
  check("plain value", plain, value)
  check("plain bits", wvalue_bits(plain), wvalue_bits(value))
  check("surplus value", extra, value)
  check("surplus bits", wvalue_bits(extra), wvalue_bits(value))
  i += 1

hits = 0
values[4].to_i -> (ignored)
  hits += 1
check("trailing block passthrough", hits, 42)

<< "PASS Integer#to_i source autoload"
