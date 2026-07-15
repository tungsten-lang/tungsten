# Isolated Array#uniq source candidates shared by compiled and tree-walker
# correctness harnesses. Production core/array.w and the runtime IC remain
# untouched until a candidate clears every semantic and timing gate.

use ../../core/array
use ../../core/hash

ARRAY_UNIQ_SMALL_THRESHOLD = 16

# Hash and w_eq have the same key contract only for String/rope and Symbol.
# Recognize the common String/Symbol representation entirely from the WValue:
# high tag 0xFFF9 covers inline, slab, and heap text. Ropes are the one text
# representation in the generic-object bucket, whose ABI guarantees a type
# discriminator in byte zero. The pointer load is guarded by tag, sentinel,
# and subtag checks, so it can never inspect nil, an immediate, or another
# heap-object family.
#
# Keep these constants beside the benchmark candidate rather than exporting a
# new runtime predicate. If the WValue layout changes, this WIRE gate should
# fail alongside runtime/wvalue.h instead of silently widening the Hash path.
-> array_uniq_text_hash_safe?(value)
  bits = wvalue_bits(value) ## i64
  tag = (bits >> 48) & 0xFFFF ## i64
  if tag == 0xFFF9
    return true
  if tag != 0 || bits < 16 || (bits & 0xF) != 0
    return false
  raw_load_u8(bits, 0) == 9

+ Array
  -> __w_uniq_v1
    out = []
    i = 0
    while i < $size
      value = self[i]
      seen = false
      j = 0
      while j < out$size
        # Source `==` lowers directly to w_eq for unknown WValues and the
        # tree walker evaluates it through the same host runtime semantics.
        if out[j] == value
          seen = true
          break
        j += 1
      if !seen
        out.push(value)
      i += 1
    out

  -> __w_uniq_v2
    # Allocate the returned Array first, matching w_ic_array_uniq's observable
    # default-capacity/growth behavior even when pools contain old arrays.
    out = []

    # Hash setup loses on tiny inputs. A non-text first item also selects the
    # exact quadratic path, avoiding a full classification prepass/regression
    # for the common numeric-array case.
    use_text_hash = false
    first = nil
    if $size > ARRAY_UNIQ_SMALL_THRESHOLD
      first = self[0]
      use_text_hash = array_uniq_text_hash_safe?(first)

    if use_text_hash
      # Keep the recycled Hash in this explicit lexical branch. A
      # recycle declaration lowered after a preceding branch containing
      # `break` currently attaches to a stale compile-time scope. Emitting the
      # Hash branch first avoids that compiler bug; its rare non-text fallback
      # uses a condition instead of `break` for the same reason.
      text_seen = {} ## recycle
      # The branch predicate already proved item zero is text, and an empty
      # output cannot contain it. Seed both structures directly: this removes a
      # second classification plus a guaranteed-miss Hash probe.
      ccall("w_hash_set", text_seen, first, true)
      out.push(first)
      i = 1
      while i < $size
        value = self[i]
        if array_uniq_text_hash_safe?(value)
          # These two storage primitives are narrowly interpreter-allowlisted;
          # ordinary Hash method dispatch here would obscure the algorithmic
          # comparison. Only text keys ever cross this boundary.
          present = ccall("w_hash_has_key", text_seen, value)
          # w_hash_has_key returns canonical W_FALSE (raw bit pattern 1) or
          # W_TRUE. Compare the raw bit directly instead of calling generic w_eq.
          if wvalue_bits(present) == 1
            ccall("w_hash_set", text_seen, value, true)
            out.push(value)
        else
          # Hash is deliberately bypassed here. This retains w_eq's NaN
          # multiplicity, numeric cross-type behavior, rational normalization,
          # structural ByteArray/WNetAddr equality, and object identity.
          seen = false
          j = 0
          while j < out$size && !seen
            if out[j] == value
              seen = true
            j += 1
          if !seen
            out.push(value)
        i += 1
    else
      i = 0
      while i < $size
        value = self[i]
        seen = false
        j = 0
        while j < out$size
          if out[j] == value
            seen = true
            break
          j += 1
        if !seen
          out.push(value)
        i += 1
    out
