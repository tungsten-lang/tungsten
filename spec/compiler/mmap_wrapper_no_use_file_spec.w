# No use: exact File.mmap producer must load Mmap, and source typed-view calls
# must in turn load BigArray for the opaque native return.
m = File.mmap("VERSION")
if m.byte_at(0) != m[0]
  << "FAIL mmap wrapper File producer byte parity"
  exit(1)
view = m.as_u8
if view.size != m.size
  << "FAIL mmap wrapper File producer view size"
  exit(1)
m.close
<< "PASS mmap wrapper File producer autoload"
