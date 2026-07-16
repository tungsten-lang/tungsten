# No use and no BigArray spelling. Loading Mmap must discover that
# __w_mmap_as_typed returns BigArray before cap/empty? dispatch.
m = ccall("w_mwr_fixture", 64)
view = m.as_u8
if view.size != 64 || view.cap != 64 || view.empty?
  << "FAIL mmap wrapper BigArray result autoload"
  exit(1)
ccall("w_mwr_release_view", view)
ccall("w_mwr_release_mmap", m)
<< "PASS mmap wrapper BigArray result autoload"
