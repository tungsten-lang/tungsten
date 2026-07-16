# No use and deliberately unknown C factory name: call-name fallback must load
# Mmap even though the receiver has no statically visible class.
m = ccall("w_mwr_fixture", 64)
if m.byte_at(0) != 3
  << "FAIL mmap wrapper opaque factory byte"
  exit(1)
view = m.as_i16
if ccall("w_mwr_view_size", view) != 32
  << "FAIL mmap wrapper opaque factory view"
  exit(1)
ccall("w_mwr_release_view", view)
m.close
ccall("w_mwr_release_mmap", m)
<< "PASS mmap wrapper opaque factory autoload"
