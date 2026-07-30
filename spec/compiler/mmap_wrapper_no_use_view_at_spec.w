# view_at-only opaque boundary pins its retained native decoder. It must work
# without loading the Mmap source class through this representation-sensitive
# spelling.
m = ccall("w_mwr_fixture", 64)
view = m.view_at(4, :u16, 4)
if ccall("w_mwr_view_size", view) != 4 || ccall("w_mwr_view_ebits", view) != 16
  << "FAIL mmap wrapper opaque view_at"
  exit(1)
ccall("w_mwr_release_view", view)

i32_view = m.view_at(0, :i32, 4)
if ccall("w_mwr_view_ebits", i32_view) != 33
  << "FAIL mmap wrapper i32 view_at encoding"
  exit(1)
ccall("w_mwr_release_view", i32_view)

i64_view = m.view_at(0, :i64, 2)
if ccall("w_mwr_view_ebits", i64_view) != 66
  << "FAIL mmap wrapper i64 view_at encoding"
  exit(1)
ccall("w_mwr_release_view", i64_view)

ccall("w_mwr_release_mmap", m)
<< "PASS mmap wrapper native view_at without source autoload"
