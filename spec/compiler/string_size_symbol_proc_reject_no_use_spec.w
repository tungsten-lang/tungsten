# No imports, array literal, or explicit .size call. lower_method_call
# synthesizes the per-element String#size call after the loader walk.
values = ccall("w_strlen_one_string_array")
got = values.reject(:size)
if ccall("w_array_size", got) != 0
  << "FAIL no-use reject(:size)"
  exit(1)
<< "PASS no-use reject(:size)"
