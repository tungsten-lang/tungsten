# No imports, array literal, or explicit .length call. lower_method_call
# synthesizes the per-element String#length call after the loader walk.
values = ccall("w_strlen_one_string_array")
got = values.reject(:length)
if ccall("w_array_size", got) != 0
  << "FAIL no-use reject(:length)"
  exit(1)
<< "PASS no-use reject(:length)"
