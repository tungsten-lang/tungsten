# No use: the exact low-level constructor is an opaque native-return boundary.
m = ccall("__w_file_mmap", "VERSION")
if m.byte_at(0) != m[0]
  << "FAIL mmap wrapper native producer byte parity"
  exit(1)
view = m.as_f64
if view.size != m.size / 8
  << "FAIL mmap wrapper native producer view size"
  exit(1)
m.close
<< "PASS mmap wrapper native producer autoload"
