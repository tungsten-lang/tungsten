# No imports, array literal, or explicit .size call. lower_method_call
# synthesizes the per-element String#size call after the loader walk.
values = ccall("w_strlen_one_string_array")
got = values.count(:size)
if got != 1
  << "FAIL no-use count(:size)"
  exit(1)
<< "PASS no-use count(:size)"
