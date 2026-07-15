# Tree-walker parity for the source-defined Hash#size body. The compiled body
# reads WHash.count directly through `$count`; the interpreter must mirror that
# native view-field read instead of treating `$count` as an unset global.

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
check("extra arguments", h.size(99, 100), 2)

h.delete("b")
check("delete", h.size, 1)

<< "hash_size_view_field_spec: all checks passed"
