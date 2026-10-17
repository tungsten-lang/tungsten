# spec: skip -- compiled: clang: error: linker command failed with exit code 1 (use -v to see invocation); interpreter: Unsupported ccall 'w_mwr_fixture' in interpreter
# Subscript-only opaque boundary pins retained native dispatch. It must work
# without loading the Mmap source class through this ubiquitous spelling.
m = ccall("w_mwr_fixture", 64)
if m[0] != 3
  << "FAIL mmap wrapper opaque subscript"
  exit(1)
ccall("w_mwr_release_mmap", m)
<< "PASS mmap wrapper subscript autoload"
