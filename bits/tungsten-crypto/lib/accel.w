# Hardware-accelerated mining via the ARMv8 SHA-256 crypto extension.
#
# The pure-Tungsten miner in miner.w is the reference: readable, portable,
# and the thing the specs pin to real blockchain data. This module routes
# the same search through `runtime/sha256_hw.c`, which issues the ARMv8
# SHA256H / SHA256H2 / SHA256SU0 / SHA256SU1 instructions — one instruction
# per four SHA-256 rounds instead of a dozen scalar ops per round.
#
# The algorithm is identical, including the midstate reuse; only the
# instruction selection differs. `crypto_accel_available` reports whether
# the CPU actually has the extension (the C side probes at runtime, so a
# toolchain that emitted the instructions for a CPU lacking them degrades
# to the scalar path rather than trapping).
#
# The C entry point takes raw pointers, so the arrays crossing the boundary
# are `i32[]` (matching `uint32_t*`) and `u8[]` (matching `uint8_t*`).
# Passing an `i64[]` here would silently corrupt: a 64-bit element array
# read through a 32-bit pointer reads two elements per word.

use bitcoin

-> crypto_accel_available
  ccall_nobox("w_sha256_hw_available")

# Search nonces [start, start+count) using the hardware path.
#
#   header   the 80 serialized header bytes (its nonce field is ignored)
#   target   8 big-endian target words, from btc_target_from_bits
#   out      i32[8] that receives the winning digest, big-endian words
#
# Returns the winning nonce, or -1.
-> crypto_accel_search(header, target, start, count, out, k)
  mid = i32[8]
  tail = u8[12]
  tgt = i32[8]
  # Midstate over the header's first 64 bytes — computed by the reference
  # implementation, so the two paths cannot disagree about it.
  st = sha256_iv()
  w = i64[64]
  j = 0 ## i64
  while j < 16
    off = j * 4
    w[j] = (header[off] << 24) | (header[off + 1] << 16) | (header[off + 2] << 8) | header[off + 3]
    j += 1
  sha256_block(st, w, k)
  j = 0
  while j < 8
    mid[j] = st[j]
    tgt[j] = target[j]
    j += 1
  # Header bytes 64..75: the merkle tail, time and bits. Bytes 76..79 are
  # the nonce, which the search supplies itself.
  j = 0
  while j < 12
    tail[j] = header[64 + j]
    j += 1
  mid_ptr = ccall_nobox("w_array_data_ptr", mid)
  tail_ptr = ccall_nobox("w_array_data_ptr", tail)
  tgt_ptr = ccall_nobox("w_array_data_ptr", tgt)
  out_ptr = ccall_nobox("w_array_data_ptr", out)
  s = start ## i64
  c = count ## i64
  best = i32[1]
  best_ptr = ccall_nobox("w_array_data_ptr", best)
  ccall_nobox("w_sha256_hw_mine", mid_ptr, tail_ptr, tgt_ptr, s, c, out_ptr, best_ptr, 0)

# Convert the accelerator's i32[8] digest into the i64[8] form the rest of
# the library uses, so btc_meets_target and sha256_hex_le apply unchanged.
-> crypto_accel_digest(out)
  d = i64[8]
  j = 0 ## i64
  while j < 8
    d[j] = out[j] & 0xFFFFFFFF
    j += 1
  d
