# Regression: a typed top-level helper must resolve another typed function's
# signature when the argument list mixes a user class, a typed array, and a
# plain Array.  Falling back to the bare function name leaves an undefined
# `__w_typed_signature_composer` symbol at link time because typed definitions
# are emitted under their signature-mangled name.

+ TypedSignatureBox
  -> new(value)
    @value = value

  -> value
    @value

-> typed_signature_target(box, values, leaves) (TypedSignatureBox i64[] Array) i64
  box.value() + values[0] + leaves[0]

-> typed_signature_helper(box, values, leaves) (TypedSignatureBox i64[] Array) i64
  typed_signature_target(box, values, leaves)

# Match the motivating block-composer shape exactly: a user-class return is
# inferred, three typed-array arguments precede the plain Array, and the
# wrapper itself also relies on return inference.
-> typed_signature_composer(box, alloc_n, alloc_m, alloc_p, leaves) (TypedSignatureBox i64[] i64[] i64[] Array)
  if leaves.size() == alloc_n.size() + alloc_m.size() + alloc_p.size()
    return box
  nil

-> typed_signature_wrapper(box, alloc_n, alloc_m, alloc_p, leaves) (TypedSignatureBox i64[] i64[] i64[] Array)
  typed_signature_composer(box, alloc_n, alloc_m, alloc_p, leaves)

-> typed_signature_local_array(box, alloc_n, alloc_m, alloc_p) (TypedSignatureBox i64[] i64[] i64[])
  local_leaves = [box, box, box]
  typed_signature_composer(box, alloc_n, alloc_m, alloc_p, local_leaves)

values = i64[1]
values[0] = 20
leaves = [21]
got = typed_signature_helper(TypedSignatureBox.new(1), values, leaves)
if got != 42
  << "FAIL typed helper Array signature got=" + got.to_s()
  exit(1)
alloc_n = i64[1]
alloc_m = i64[1]
alloc_p = i64[1]
scheme_leaves = [TypedSignatureBox.new(2), TypedSignatureBox.new(3), TypedSignatureBox.new(4)]
composed = typed_signature_wrapper(TypedSignatureBox.new(42), alloc_n, alloc_m, alloc_p, scheme_leaves)
if composed == nil || composed.value() != 42
  << "FAIL typed composer wrapper"
  exit(1)
local_composed = typed_signature_local_array(TypedSignatureBox.new(42), alloc_n, alloc_m, alloc_p)
if local_composed == nil || local_composed.value() != 42
  << "FAIL typed composer local Array"
  exit(1)
<< "PASS typed helper Array signature"
