# ByteArray value-equality (Phase 6i.1 lifted ByteArray to WArray with
# ebits=8; w_eq didn't have a bytes branch, so two ByteArrays with
# identical content compared as false in compiled code).

# Round-trip through base64 round-trip — decoded bytes must equal original.
raw = "Hello, world!"
enc = base64_encode(raw)
dec = base64_decode(enc)

# `raw` is a String, `dec` is a ByteArray — cross-type compare is correctly
# false in current semantics (no implicit string↔bytes coercion). Compare
# bytes-to-bytes by going through base64_decode on the encoded form twice.
dec2 = base64_decode(base64_encode(raw))
if dec != dec2
  << "FAIL: base64 round-trip equality"
  exit 1

# Two empty ByteArrays should be equal.
empty_a = base64_decode("")
empty_b = base64_decode("")
if empty_a != empty_b
  << "FAIL: empty ByteArray equality"
  exit 1

# Different content of same size: unequal.
diff_a = base64_decode("AAAA")
diff_b = base64_decode("AAAB")
if diff_a == diff_b
  << "FAIL: ByteArray same-size-different-content should be unequal"
  exit 1

# Different sizes: unequal.
short_b = base64_decode("AAAA")
long_b  = base64_decode("AAAAAAAA")
if short_b == long_b
  << "FAIL: ByteArray different sizes should be unequal"
  exit 1

# File round-trip — same bytes via different paths must compare equal.
write_file_bytes("/tmp/tungsten-bytes-eq-spec.bin", dec)
back = read_file_bytes("/tmp/tungsten-bytes-eq-spec.bin")
if back != dec
  << "FAIL: file round-trip ByteArray equality"
  exit 1

<< "ok"
