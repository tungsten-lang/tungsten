# spec: skip -- compiled: clang: error: linker command failed with exit code 1 (use -v to see invocation); interpreter: Unsupported ccall 'w_strlen_one_string_array' in interpreter
# No imports, array literal, or explicit .length call. lower_method_call
# synthesizes the per-element String#length call after the loader walk.
values = ccall("w_strlen_one_string_array")
got = values.count(:length)
if got != 1
  << "FAIL no-use count(:length)"
  exit(1)
<< "PASS no-use count(:length)"
