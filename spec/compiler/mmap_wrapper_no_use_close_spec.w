# Close-only opaque boundary pins retained native dispatch. A broad `close`
# autoload trigger would affect sockets, files, channels, and many user types.
m = ccall("w_mwr_fixture", 64)
if m.close != nil
  << "FAIL mmap wrapper native close return"
  exit(1)
ccall("w_mwr_release_mmap", m)
<< "PASS mmap wrapper native close without source autoload"
