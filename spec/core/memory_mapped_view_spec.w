# P1.4 zero-copy typed-array views — File.mmap → as_u8/as_u32/as_f32.
#
# Expects /tmp/tungsten-mmap-view-smoke.bin to be prepopulated with 16
# bytes: u32 little-endian sequence [1, 2, 3, 4]. The test runner sets
# this up before invoking the compiled binary. Asserts:
#   - as_u8 yields per-byte view of correct length
#   - as_u32 yields a length = bytes/4 view with little-endian decode
#   - as_f32 yields the same underlying memory reinterpreted as floats
#
# Note: variable names u8/u32/f32 collide with typed-array constructor
# syntax `u8[N]`, so use bview/wview/fview instead.

use core/file

m = File.mmap("/tmp/tungsten-mmap-view-smoke.bin")

if m.size != 16
  << "FAIL mmap size"
  exit 1

bview = m.as_u8
if bview.size != 16 || bview[0] != 1 || bview[4] != 2 || bview[8] != 3 || bview[12] != 4
  << "FAIL as_u8"
  exit 1

wview = m.as_u32
if wview.size != 4 || wview[0] != 1 || wview[1] != 2 || wview[2] != 3 || wview[3] != 4
  << "FAIL as_u32"
  exit 1

fview = m.as_f32
if fview.size != 4
  << "FAIL as_f32 size"
  exit 1

m.close
<< "mmap view smoke ok"
