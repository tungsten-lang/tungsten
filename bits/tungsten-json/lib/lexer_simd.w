# JSON Lexer (SIMD classifier variant)
#
# Calls into a 16-byte SIMD JSON structural classifier in runtime.c
# (`w_json_simd_classify`). The classifier processes 64 source bytes per
# iteration via NEON intrinsics, identifies structural characters, and
# tracks JSON string state in parallel via the simdjson PMULL prefix-XOR
# trick. ~3× faster per-core than the per-character dispatch lexers.
#
# Output: i32[] offsets array, one offset per emitted position. The
# emitted positions are:
#   - structural characters: { } [ ] , :  (when not inside a string)
#   - opening quote " of each string
# The downstream parser walks consecutive offsets and recovers number
# and keyword positions by inspecting the bytes between structurals.
#
# This is a different output shape than lexer{,16,32}.w, which emit
# packed-i32 cells with type+offset and one entry per non-ws token
# (including numbers and literals). Use this lexer when you want raw
# simdjson-style stage-1 throughput; use lexer32.w when you want pre-
# typed tokens.

## i64: count, src_ptr, src_len, out_ptr
## i32[]: tokens
-> json_tokenize_simd(source, tokens)
  src_ptr = ccall_nobox("w_string_byte_ptr", source)
  src_len = ccall_nobox("w_string_byte_length", source)
  out_ptr = ccall_nobox("w_array_data_ptr", tokens)
  count = ccall_nobox("w_json_simd_classify", src_ptr, src_len, out_ptr)
  count
