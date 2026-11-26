# blade/jsn_t/typed_ebits — Raw Tungsten `ebits` WArray Views for JS TypedArrays,
# Page-Aligned ArrayBuffers (zero-copy CPU <-> Metal GPU), and SmallArray helpers.
#
# Every single one of ECMAScript's 12 TypedArray kinds maps 1-to-1 to a native
# Tungsten WArray `ebits` encoding (from runtime/runtime_arrays.c):
#   0: Int8Array         -> ebits = 108  (i8[])
#   1: Uint8Array        -> ebits =   8  (u8[])
#   2: Uint8ClampedArray -> ebits =   8  (u8[], with clamping on JS writes)
#   3: Int16Array        -> ebits = 116  (i16[])
#   4: Uint16Array       -> ebits =  16  (u16[])
#   5: Int32Array        -> ebits =  33  (i32[])
#   6: Uint32Array       -> ebits =  32  (u32[])
#   7: Float32Array      -> ebits = -32  (f32[])
#   8: Float64Array      -> ebits = -64  (f64[])
#   9: BigInt64Array     -> ebits =  66  (i64[])
#  10: BigUint64Array    -> ebits =  64  (u64[])
#  11: Float16Array      -> ebits = -16  (f16[], ARM64 native __fp16 fcvt!)
#
# Using `w_array_view_raw(buf_ptr + byteOffset, ebits, length)`:
#   - Zero copies: shares the exact physical memory of `ArrayBuffer.data`.
#   - Multiple overlapping TypedArray views (e.g. Uint8Array & Float32Array on the
#     same ArrayBuffer) alias cleanly without duplication.
#   - When the ArrayBuffer is backed by `metal_array(8, byte_len)` (page-aligned mmap),
#     the exact same TypedArray view can be bound zero-copy to a Metal `@gpu fn`!

use core/metal
use core/small_array

# Map JS:TypedArray kind (0..11) -> Tungsten WArray ebits code.
JST_KIND_TO_EBITS = [108, 8, 8, 116, 16, 33, 32, -32, -64, 66, 64, -16]
JST_KIND_TO_TYPE  = ["i8[]", "u8[]", "u8[]", "i16[]", "u16[]", "i32[]", "u32[]", "f32[]", "f64[]", "i64[]", "u64[]", "f16[]"]
JST_KIND_TO_ELEM  = ["i8", "u8", "u8", "i16", "u16", "i32", "u32", "f32", "f64", "i64", "u64", "f16"]
JST_KIND_TO_BYTES = [1, 1, 1, 2, 2, 4, 4, 4, 8, 8, 8, 2]

# Direct C call into runtime_arrays.c:
#   WValue w_array_view_raw(uint8_t *data, int64_t element_bits, int64_t length)
# Using ccall_nobox automatically declares `@w_array_view_raw` in the LLVM IR.
-> jst_make_raw_view(ptr, ebits, len)
  ccall_nobox("w_array_view_raw", ptr ## i64, ebits ## i64, len ## i64) ## i64

# Direct raw pointer read from a WArray WValue (slots pointer at offset +16).
fn jst_warray_slots(arr_bits) (i64) i64
  ll <<~IR
    %p = and i64 %arr_bits, 140737488355312
    %q = inttoptr i64 %p to ptr
    %a = getelementptr i8, ptr %q, i64 16
    %s = load i64, ptr %a, align 8
    ret i64 %s
  IR

# Obtain a zero-copy raw-ebits Tungsten WArray view over a JS:TypedArray.
# Delegates directly to the cached `@view` slot on JS:TypedArray (b_typed.w)
# with zero Hash overhead and automatic JS_AB_EPOCH invalidation.
-> jst_ta_view(ta)
  js_ta_ebits_view(ta)

# Upgrade a JS:ArrayBuffer's backing storage to a page-aligned mmap (`metal_array(8, blen)`)
# so Metal GPU can bind its TypedArrays with ZERO COPY on Apple Silicon Unified Memory.
# Copies existing bytes once if not already page-aligned.
-> jst_buffer_ensure_page_aligned(buf)
  return nil if buf == nil || buf.detached || buf.blen <= 0
  # Check if slots pointer is already 16KB page-aligned (Apple Silicon page size)
  old_ptr = jst_warray_slots(wvalue_bits(buf.data) ## i64)
  return buf.data if (old_ptr & 16383) == 0
  aligned = metal_array(8, buf.blen)
  new_ptr = jst_warray_slots(wvalue_bits(aligned) ## i64)
  ccall_nobox("memcpy", new_ptr, old_ptr, buf.blen)
  buf.data = aligned
  JS_AB_EPOCH[0] += 1
  aligned

# Convenience: allocate a JS:TypedArray backed by a page-aligned ArrayBuffer from the start
# (for zero-copy CPU ebits WArray AND Metal GPU dispatch!).
-> jst_new_aligned_typed_array(kind, len)
  r = js_realm()
  elem_sz = JST_KIND_TO_BYTES[kind]
  blen = len * elem_sz
  ab = js_special_new(r.intrinsics["%ArrayBufferPrototype%"], "ArrayBuffer", :buffer)
  ab.data = metal_array(8, blen > 0 ? blen : 16)
  ab.blen = blen
  ab.max_len = nil
  ab.detached = false
  ab.shared = false
  name = TA_KINDS[kind][0]
  ta = js_special_new(r.intrinsics["%" + name + "Prototype%"], name, :typed)
  ta.buffer = ab
  ta.offset = 0
  ta.len = len
  ta.kind = kind
  ta.track = false
  ta

# Create a Tungsten SmallArray (frozen, compact 2-byte header + inline elements, <= 255 elems)
# from a small fixed JS numeric Array (e.g. frozen vector literal `[x, y, z]`).
-> jst_freeze_small_f64(js_arr)
  n = js_arr.size
  return nil if n <= 0 || n > 255
  # Build f64[] first, then wrap into compact SmallArray via w_small_array_new
  tmp = f64[n]
  i = 0
  while i < n
    v = js_arr[i]
    tmp[i] = js_to_number(v)
    i += 1
  ptr = jst_warray_slots(wvalue_bits(tmp) ## i64)
  wvalue_from_bits(ccall_nobox("w_small_array_new", (-64) ## i64, n ## i64, ptr ## i64) ## i64)
