# view_at-only opaque boundary pins its retained native decoder. It must work
# without loading the Mmap source class through this representation-sensitive
# spelling.
m = ccall("w_mwr_fixture", 64)
view = m.view_at(4, :u16, 4)
if ccall("w_mwr_view_size", view) != 4 || ccall("w_mwr_view_ebits", view) != 16
  << "FAIL mmap wrapper opaque view_at"
  exit(1)
ccall("w_mwr_release_view", view)
ccall("w_mwr_release_mmap", m)
<< "PASS mmap wrapper native view_at without source autoload"
