# byte_at-only opaque boundary pins retained native dispatch and its dedicated
# missing-argument fatal surface without loading the Mmap source class.
m = ccall("w_mwr_fixture", 64)
if m.byte_at(0) != 3
  << "FAIL mmap wrapper byte_at-only autoload"
  exit(1)
ccall("w_mwr_release_mmap", m)
<< "PASS mmap wrapper native byte_at without source autoload"
