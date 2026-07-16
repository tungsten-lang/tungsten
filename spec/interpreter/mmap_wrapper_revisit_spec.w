# Tree-walker parity for the source Mmap wrappers and retained native view_at.
use core/mmap

m = File.mmap("VERSION")

if m.byte_at(0) != m[0]
  << "FAIL interpreter mmap byte parity"
  exit(1)

size = m.size
if m.as_u8.size != size
  << "FAIL interpreter mmap as_u8"
  exit(1)
if m.as_u16.size != size / 2
  << "FAIL interpreter mmap as_u16"
  exit(1)
if m.as_u32.size != size / 4 || m.as_i32.size != size / 4 || m.as_f32.size != size / 4
  << "FAIL interpreter mmap 32-bit views"
  exit(1)
if m.as_u64.size != size / 8 || m.as_i64.size != size / 8 || m.as_f64.size != size / 8
  << "FAIL interpreter mmap 64-bit views"
  exit(1)
if m.as_i8.size != size || m.as_i16.size != size / 2
  << "FAIL interpreter mmap signed narrow views"
  exit(1)

native_view = m.view_at(0, :u8, 1)
if native_view.size != 1
  << "FAIL interpreter mmap retained view_at"
  exit(1)

m.close
closed_byte = false
begin
  m.byte_at(0)
rescue error
  closed_byte = true
if !closed_byte
  << "FAIL interpreter mmap closed byte"
  exit(1)

closed_view = false
begin
  m.as_u8
rescue error
  closed_view = true
if !closed_view
  << "FAIL interpreter mmap closed view"
  exit(1)

<< "PASS interpreter Mmap wrapper revisit"
