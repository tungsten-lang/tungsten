# No imports, array literal, or explicit .size call. lower_method_call
# synthesizes the per-element String#size call after the loader walk.
values = ccall("w_strlen_one_string_array")
got = values.select(:size)
if ccall("w_array_size", got) != 1 || ccall("w_array_get", got, 0) != "a"
  << "FAIL no-use select(:size)"
  exit(1)
<< "PASS no-use select(:size)"
