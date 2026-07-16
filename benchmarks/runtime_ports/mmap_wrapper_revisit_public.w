# Public-dispatch correctness and per-method timing driver for the remaining
# Mmap wrappers. The native baseline and source candidate compile this exact
# file and link the same C fixture/reference implementation.

use core/big_array

+ Mmap
  -> __c_close
    ccall("w_mwr_ref_close", self)

  -> __c_byte_at(index)
    ccall("w_mwr_ref_byte_at", self, index)

  -> __c_idx(index)
    ccall("w_mwr_ref_byte_at", self, index)

  -> __c_as_u8
    ccall("w_mwr_ref_as_u8", self)

  -> __c_as_u16
    ccall("w_mwr_ref_as_u16", self)

  -> __c_as_u32
    ccall("w_mwr_ref_as_u32", self)

  -> __c_as_u64
    ccall("w_mwr_ref_as_u64", self)

  -> __c_as_i8
    ccall("w_mwr_ref_as_i8", self)

  -> __c_as_i16
    ccall("w_mwr_ref_as_i16", self)

  -> __c_as_i32
    ccall("w_mwr_ref_as_i32", self)

  -> __c_as_i64
    ccall("w_mwr_ref_as_i64", self)

  -> __c_as_f32
    ccall("w_mwr_ref_as_f32", self)

  -> __c_as_f64
    ccall("w_mwr_ref_as_f64", self)

FAST_ITERS = 20_000_000
FAST_WARMUP = 300_000
VIEW_ITERS = 10_000_000
VIEW_WARMUP = 200_000

-> fail_check(name, detail)
  << "FAIL [name]: [detail]"
  exit(1)

-> check(name, got, expected)
  if got != expected
    fail_check(name, "got=[got] expected=[expected]")

-> fixture
  ccall("w_mwr_fixture", 64)

-> release_mmap(value)
  ccall("w_mwr_release_mmap", value)

-> closed?(value)
  ccall("w_mwr_mmap_closed", value)

-> view_ebits(value)
  ccall("w_mwr_view_ebits", value)

-> view_size(value)
  ccall("w_mwr_view_size", value)

-> view_signature(value)
  ccall("w_mwr_view_signature", value)

-> views_share_data?(left, right)
  ccall("w_mwr_views_share_data", left, right)

-> release_view(value)
  ccall("w_mwr_release_view", value)

-> thread_ns
  ccall_nobox("w_mwr_thread_cpu_ns") ## i64

-> check_typed_pair(name, public_view, reference_view, expected_ebits, expected_size)
  check("[name].signature", view_signature(public_view), view_signature(reference_view))
  check("[name].borrowed-data", views_share_data?(public_view, reference_view), true)
  check("[name].ebits", view_ebits(public_view), expected_ebits)
  check("[name].size", view_size(public_view), expected_size)
  release_view(public_view)
  release_view(reference_view)

-> run_correctness
  mapping = fixture()
  indexes = [0, 1, 2, 31, 63]
  i = 0
  while i < indexes.size
    index = indexes[i]
    check("byte_at.[index]", mapping.byte_at(index), mapping.__c_byte_at(index))
    check("idx.[index]", mapping[index], mapping.__c_idx(index))
    i += 1
  check("byte_at.extra", mapping.byte_at(3, "ignored", 99), mapping.__c_byte_at(3, "ignored", 99))
  check("idx.extra", mapping.[](4, "ignored", 99), mapping.__c_idx(4, "ignored", 99))

  ref_raised = false
  public_raised = false
  begin
    mapping.__c_byte_at(64)
  rescue error
    ref_raised = true
  begin
    mapping.byte_at(64)
  rescue error
    public_raised = true
  check("byte_at.bounds.reference", ref_raised, true)
  check("byte_at.bounds.public", public_raised, true)

  check_typed_pair("as_u8", mapping.as_u8, mapping.__c_as_u8, 8, 64)
  check_typed_pair("as_u16", mapping.as_u16, mapping.__c_as_u16, 16, 32)
  check_typed_pair("as_u32", mapping.as_u32, mapping.__c_as_u32, 32, 16)
  check_typed_pair("as_u64", mapping.as_u64, mapping.__c_as_u64, 64, 8)
  check_typed_pair("as_i8", mapping.as_i8, mapping.__c_as_i8, 108, 64)
  check_typed_pair("as_i16", mapping.as_i16, mapping.__c_as_i16, 116, 32)
  check_typed_pair("as_i32", mapping.as_i32, mapping.__c_as_i32, 32, 16)
  check_typed_pair("as_i64", mapping.as_i64, mapping.__c_as_i64, 64, 8)
  check_typed_pair("as_f32", mapping.as_f32, mapping.__c_as_f32, -32, 16)
  check_typed_pair("as_f64", mapping.as_f64, mapping.__c_as_f64, -64, 8)

  check_typed_pair("as_u8.extra1", mapping.as_u8(1), mapping.__c_as_u8(1), 8, 64)
  check_typed_pair("as_u16.extra1", mapping.as_u16(1), mapping.__c_as_u16(1), 16, 32)
  check_typed_pair("as_u32.extra1", mapping.as_u32(1), mapping.__c_as_u32(1), 32, 16)
  check_typed_pair("as_u64.extra1", mapping.as_u64(1), mapping.__c_as_u64(1), 64, 8)
  check_typed_pair("as_i8.extra1", mapping.as_i8(1), mapping.__c_as_i8(1), 108, 64)
  check_typed_pair("as_i16.extra1", mapping.as_i16(1), mapping.__c_as_i16(1), 116, 32)
  check_typed_pair("as_i32.extra1", mapping.as_i32(1), mapping.__c_as_i32(1), 32, 16)
  check_typed_pair("as_i64.extra1", mapping.as_i64(1), mapping.__c_as_i64(1), 64, 8)
  check_typed_pair("as_f32.extra1", mapping.as_f32(1), mapping.__c_as_f32(1), -32, 16)
  check_typed_pair("as_f64.extra1", mapping.as_f64(1), mapping.__c_as_f64(1), -64, 8)

  check_typed_pair("as_u8.extra3", mapping.as_u8(1, 2, 3), mapping.__c_as_u8(1, 2, 3), 8, 64)
  check_typed_pair("as_u16.extra3", mapping.as_u16(1, 2, 3), mapping.__c_as_u16(1, 2, 3), 16, 32)
  check_typed_pair("as_u32.extra3", mapping.as_u32(1, 2, 3), mapping.__c_as_u32(1, 2, 3), 32, 16)
  check_typed_pair("as_u64.extra3", mapping.as_u64(1, 2, 3), mapping.__c_as_u64(1, 2, 3), 64, 8)
  check_typed_pair("as_i8.extra3", mapping.as_i8(1, 2, 3), mapping.__c_as_i8(1, 2, 3), 108, 64)
  check_typed_pair("as_i16.extra3", mapping.as_i16(1, 2, 3), mapping.__c_as_i16(1, 2, 3), 116, 32)
  check_typed_pair("as_i32.extra3", mapping.as_i32(1, 2, 3), mapping.__c_as_i32(1, 2, 3), 32, 16)
  check_typed_pair("as_i64.extra3", mapping.as_i64(1, 2, 3), mapping.__c_as_i64(1, 2, 3), 64, 8)
  check_typed_pair("as_f32.extra3", mapping.as_f32(1, 2, 3), mapping.__c_as_f32(1, 2, 3), -32, 16)
  check_typed_pair("as_f64.extra3", mapping.as_f64(1, 2, 3), mapping.__c_as_f64(1, 2, 3), -64, 8)

  # Retained-native control: symbol and immediate encodings must still agree,
  # and the old handler must continue to ignore surplus arguments.
  view_symbol = mapping.view_at(4, :u16, 4)
  view_integer = mapping.view_at(4, 16, 4, "ignored")
  check("view_at.native-control", view_signature(view_symbol), view_signature(view_integer))
  release_view(view_symbol)
  release_view(view_integer)

  ref_byte_hits = 0
  ref_byte_sum = 0
  ref_byte_return = mapping.__c_byte_at(0) -> (value)
    ref_byte_hits += 1
    ref_byte_sum += value
  public_byte_hits = 0
  public_byte_sum = 0
  public_byte_return = mapping.byte_at(0) -> (value)
    public_byte_hits += 1
    public_byte_sum += value
  check("byte_at.block.hits", public_byte_hits, ref_byte_hits)
  check("byte_at.block.sum", public_byte_sum, ref_byte_sum)
  check("byte_at.block.return", public_byte_return, ref_byte_return)

  ref_view_hits = 0
  ref_view_sum = 0
  ref_view_return = mapping.__c_as_u8 -> (value)
    ref_view_hits += 1
    ref_view_sum += value
  public_view_hits = 0
  public_view_sum = 0
  public_view_return = mapping.as_u8 -> (value)
    public_view_hits += 1
    public_view_sum += value
  check("as_u8.block.hits", public_view_hits, ref_view_hits)
  check("as_u8.block.sum", public_view_sum, ref_view_sum)
  check("as_u8.block.signature", view_signature(public_view_return), view_signature(ref_view_return))
  release_view(public_view_return)
  release_view(ref_view_return)

  release_mmap(mapping)

  reference_closed = fixture()
  public_closed = fixture()
  check("close.return", public_closed.close(1, 2, 3), reference_closed.__c_close(1, 2, 3))
  check("close.reference-state", closed?(reference_closed), true)
  check("close.public-state", closed?(public_closed), true)
  check("close.idempotent", public_closed.close, reference_closed.__c_close)

  ref_byte_closed = false
  public_byte_closed = false
  begin
    reference_closed.__c_byte_at(0)
  rescue error
    ref_byte_closed = true
  begin
    public_closed.byte_at(0)
  rescue error
    public_byte_closed = true
  check("closed.byte.reference", ref_byte_closed, true)
  check("closed.byte.public", public_byte_closed, true)

  ref_view_closed = false
  public_view_closed = false
  begin
    reference_closed.__c_as_u8
  rescue error
    ref_view_closed = true
  begin
    public_closed.as_u8
  rescue error
    public_view_closed = true
  check("closed.view.reference", ref_view_closed, true)
  check("closed.view.public", public_view_closed, true)
  release_mmap(reference_closed)
  release_mmap(public_closed)

  << "PASS Mmap wrapper revisit: 10 source candidates, exact values/views/errors/extras/blocks, and native byte_at/close/[]/view_at controls"

-> time_close(mapping, iters)
  mapping.close
  i = 0
  checksum = 0
  start = thread_ns()
  while i < iters
    checksum += mapping.close == nil ? 1 : 0
    i += 1
  [thread_ns() - start, checksum]

-> time_byte_at(mapping, iters)
  i = 0
  checksum = 0
  start = thread_ns()
  while i < iters
    checksum += mapping.byte_at(i & 63)
    i += 1
  [thread_ns() - start, checksum]

-> time_idx(mapping, iters)
  i = 0
  checksum = 0
  start = thread_ns()
  while i < iters
    checksum += mapping[i & 63]
    i += 1
  [thread_ns() - start, checksum]

-> time_as_u8(mapping, iters)
  limit = iters ## i64
  i = 0 ## i64
  checksum = 0 ## i64
  start = thread_ns()
  while i < limit
    checksum += ccall_nobox("w_mwr_consume_release_view", mapping.as_u8) ## i64
    i += 1
  [thread_ns() - start, checksum]

-> time_as_u16(mapping, iters)
  limit = iters ## i64
  i = 0 ## i64
  checksum = 0 ## i64
  start = thread_ns()
  while i < limit
    checksum += ccall_nobox("w_mwr_consume_release_view", mapping.as_u16) ## i64
    i += 1
  [thread_ns() - start, checksum]

-> time_as_u32(mapping, iters)
  limit = iters ## i64
  i = 0 ## i64
  checksum = 0 ## i64
  start = thread_ns()
  while i < limit
    checksum += ccall_nobox("w_mwr_consume_release_view", mapping.as_u32) ## i64
    i += 1
  [thread_ns() - start, checksum]

-> time_as_u64(mapping, iters)
  limit = iters ## i64
  i = 0 ## i64
  checksum = 0 ## i64
  start = thread_ns()
  while i < limit
    checksum += ccall_nobox("w_mwr_consume_release_view", mapping.as_u64) ## i64
    i += 1
  [thread_ns() - start, checksum]

-> time_as_i8(mapping, iters)
  limit = iters ## i64
  i = 0 ## i64
  checksum = 0 ## i64
  start = thread_ns()
  while i < limit
    checksum += ccall_nobox("w_mwr_consume_release_view", mapping.as_i8) ## i64
    i += 1
  [thread_ns() - start, checksum]

-> time_as_i16(mapping, iters)
  limit = iters ## i64
  i = 0 ## i64
  checksum = 0 ## i64
  start = thread_ns()
  while i < limit
    checksum += ccall_nobox("w_mwr_consume_release_view", mapping.as_i16) ## i64
    i += 1
  [thread_ns() - start, checksum]

-> time_as_i32(mapping, iters)
  limit = iters ## i64
  i = 0 ## i64
  checksum = 0 ## i64
  start = thread_ns()
  while i < limit
    checksum += ccall_nobox("w_mwr_consume_release_view", mapping.as_i32) ## i64
    i += 1
  [thread_ns() - start, checksum]

-> time_as_i64(mapping, iters)
  limit = iters ## i64
  i = 0 ## i64
  checksum = 0 ## i64
  start = thread_ns()
  while i < limit
    checksum += ccall_nobox("w_mwr_consume_release_view", mapping.as_i64) ## i64
    i += 1
  [thread_ns() - start, checksum]

-> time_as_f32(mapping, iters)
  limit = iters ## i64
  i = 0 ## i64
  checksum = 0 ## i64
  start = thread_ns()
  while i < limit
    checksum += ccall_nobox("w_mwr_consume_release_view", mapping.as_f32) ## i64
    i += 1
  [thread_ns() - start, checksum]

-> time_as_f64(mapping, iters)
  limit = iters ## i64
  i = 0 ## i64
  checksum = 0 ## i64
  start = thread_ns()
  while i < limit
    checksum += ccall_nobox("w_mwr_consume_release_view", mapping.as_f64) ## i64
    i += 1
  [thread_ns() - start, checksum]

-> run_bench(method, iters, warmup)
  mapping = fixture()
  if method == "close"
    time_close(mapping, warmup)
    result = time_close(mapping, iters)
  elsif method == "byte_at"
    time_byte_at(mapping, warmup)
    result = time_byte_at(mapping, iters)
  elsif method == "idx"
    time_idx(mapping, warmup)
    result = time_idx(mapping, iters)
  elsif method == "as_u8"
    time_as_u8(mapping, warmup)
    result = time_as_u8(mapping, iters)
  elsif method == "as_u16"
    time_as_u16(mapping, warmup)
    result = time_as_u16(mapping, iters)
  elsif method == "as_u32"
    time_as_u32(mapping, warmup)
    result = time_as_u32(mapping, iters)
  elsif method == "as_u64"
    time_as_u64(mapping, warmup)
    result = time_as_u64(mapping, iters)
  elsif method == "as_i8"
    time_as_i8(mapping, warmup)
    result = time_as_i8(mapping, iters)
  elsif method == "as_i16"
    time_as_i16(mapping, warmup)
    result = time_as_i16(mapping, iters)
  elsif method == "as_i32"
    time_as_i32(mapping, warmup)
    result = time_as_i32(mapping, iters)
  elsif method == "as_i64"
    time_as_i64(mapping, warmup)
    result = time_as_i64(mapping, iters)
  elsif method == "as_f32"
    time_as_f32(mapping, warmup)
    result = time_as_f32(mapping, iters)
  elsif method == "as_f64"
    time_as_f64(mapping, warmup)
    result = time_as_f64(mapping, iters)
  else
    fail_check("bench", "unknown method [method]")
  release_mmap(mapping)
  # Report only integer observables. Decimal formatting is outside the method
  # under test and previously made the timing parser depend on unrelated
  # numeric-to-string behavior; the harness computes ns/call from elapsed_ns.
  << "RESULT|[method]|[result[0]]|[result[1]]"

args = argv()
mode = args.size > 0 ? args[0] : "check"
if mode == "check"
  run_correctness()
  exit(0)

if mode == "close-block-fatal"
  mapping = fixture()
  mapping.close -> (value)
    << value
  fail_check("close block", "unexpectedly returned")

if mode == "byte-missing-fatal"
  mapping = fixture()
  mapping.byte_at
  fail_check("byte_at missing argument", "unexpectedly returned")

if mode == "byte-nil-fatal"
  mapping = fixture()
  mapping.byte_at(nil)
  fail_check("byte_at nil argument", "unexpectedly returned")

if mode != "bench" || args.size < 2
  fail_check("mode", "expected check, fatal edge mode, or bench METHOD [ITERS] [WARMUP]")

method = args[1]
view_method = method.starts_with?("as_")
default_iters = view_method ? VIEW_ITERS : FAST_ITERS
default_warmup = view_method ? VIEW_WARMUP : FAST_WARMUP
iters = args.size > 2 ? args[2].to_i : default_iters
warmup = args.size > 3 ? args[3].to_i : default_warmup
if iters <= 0 || warmup <= 0
  fail_check("iterations", "must be positive")
run_bench(method, iters, warmup)
