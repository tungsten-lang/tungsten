# spec: skip -- compiled: clang: error: linker command failed with exit code 1 (use -v to see invocation); interpreter: Unsupported ccall 'w_strlen_fixture' in interpreter
# No import and unknown native receiver: the size spelling alone must schedule
# the shared 0xF9 source class once the native IC is absent.
-> probe(value)
  value.size

value = ccall("w_strlen_fixture", 6)
got = probe(value)
if got != 80
  << "FAIL no-use native String#size got=[got]"
  exit(1)
<< "PASS no-use native String#size"
