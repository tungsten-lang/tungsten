# spec: skip -- compiled: clang: error: linker command failed with exit code 1 (use -v to see invocation); interpreter: Unsupported ccall 'w_strlen_fixture' in interpreter
# No import; the receiver crosses a parameter boundary and is a rope before
# dispatch. Candidate source dispatch must autoload and flatten exactly once.
-> probe(value)
  value.length

value = ccall("w_strlen_fixture", 8)
got = probe(value)
if got != 81
  << "FAIL no-use rope String#length got=[got]"
  exit(1)
<< "PASS no-use rope String#length"
