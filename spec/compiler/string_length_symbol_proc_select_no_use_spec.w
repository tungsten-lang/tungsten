# No imports, array literal, or explicit .length call. lower_method_call
# synthesizes the per-element String#length call after the loader walk.
values = ccall("w_strlen_one_string_array")
got = values.select(:length)
if ccall("w_array_size", got) != 1 || ccall("w_array_get", got, 0) != "a"
  << "FAIL no-use select(:length)"
  exit(1)
<< "PASS no-use select(:length)"
