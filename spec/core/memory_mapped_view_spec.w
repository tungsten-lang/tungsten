# P1.4 zero-copy typed-array views — File.mmap → typed integer/float views.
#
# Expects /tmp/tungsten-mmap-view-smoke.bin to be prepopulated with 32
# bytes: u32 little-endian sequence
#   [1, 2, 3, 4, 0xFFFFFFFF, 0xFFFFFFFE, 0x89ABCDEF, 0x01234567].
# The test runner sets this up before invoking the compiled binary. Asserts:
#   - as_u8 yields per-byte view of correct length
#   - as_u32 yields a length = bytes/4 view with little-endian decode
#   - as_i32/as_i64 sign-extend high-bit lanes (the u32 view must NOT) --
#     the last four words exist to pin the signed-view encodings (33/66);
#     positive-only fixtures decode identically under the old unsigned
#     encodings and cannot catch a regression
#   - as_f32 yields the same underlying memory reinterpreted as floats
#
# Note: variable names u8/u32/f32 collide with typed-array constructor
# syntax `u8[N]`, so use bview/wview/fview instead.

use core/file

m = File.mmap("/tmp/tungsten-mmap-view-smoke.bin")

if m.size != 32
  << "FAIL mmap size"
  exit 1

bview = m.as_u8
if bview.size != 32 || bview[0] != 1 || bview[4] != 2 || bview[8] != 3 || bview[12] != 4
  << "FAIL as_u8"
  exit 1

if bview[16] != 255 || bview[19] != 255 || bview[20] != 254
  << "FAIL as_u8 high bytes"
  exit 1

wview = m.as_u32
if wview.size != 8 || wview[0] != 1 || wview[1] != 2 || wview[2] != 3 || wview[3] != 4
  << "FAIL as_u32"
  exit 1

if wview[4] != 4294967295 || wview[5] != 4294967294
  << "FAIL as_u32 unsigned high lanes"
  exit 1

i32view = m.as_i32
if i32view.size != 8 || i32view[0] != 1 || i32view[1] != 2 || i32view[2] != 3 || i32view[3] != 4
  << "FAIL as_i32"
  exit 1

if i32view[4] != -1 || i32view[5] != -2
  << "FAIL as_i32 sign extension"
  exit 1

i64view = m.as_i64
if i64view.size != 4 || i64view[0] != 8589934593 || i64view[1] != 17179869187
  << "FAIL as_i64"
  exit 1

if i64view[2] != -4294967297 || i64view[3] != 81985529216486895
  << "FAIL as_i64 sign extension"
  exit 1

native_i32view = m.view_at(0, :i32, 8)
if native_i32view[0] != 1 || native_i32view[3] != 4 || native_i32view[4] != -1
  << "FAIL view_at i32"
  exit 1

native_i64view = m.view_at(0, :i64, 4)
if native_i64view[0] != 8589934593 || native_i64view[1] != 17179869187 || native_i64view[2] != -4294967297
  << "FAIL view_at i64"
  exit 1

fview = m.as_f32
if fview.size != 8
  << "FAIL as_f32 size"
  exit 1

m.close
<< "mmap view smoke ok"
